import Foundation

struct ClaudeDesktopProvider: UsageProvider {
    let id: ProviderID = .claude
    let client: ClaudeDesktopClient

    func snapshot(force: Bool) async throws -> ProviderSnapshot {
        await client.snapshot(force: force)
    }
}

private final class ClaudeNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor ClaudeDesktopClient {
    typealias ReadCredentials = @Sendable (Bool) throws -> ClaudeDesktopCredentials
    typealias Fingerprint = @Sendable () throws -> String
    typealias Fetch = @Sendable (String, ClaudeDesktopCredentials) async throws -> Data

    private let read: ReadCredentials
    private let fingerprint: Fingerprint
    private let fetch: Fetch
    private var identity: String?
    private var cached: ProviderSnapshot?
    private var nextRequest = Date.distantPast
    private var pending: (id: UUID, identity: String, task: Task<ProviderSnapshot, Never>)?

    init(read: @escaping ReadCredentials = { try ClaudeDesktopCookieReader().read(allowInteraction: $0) },
         fingerprint: @escaping Fingerprint = { try ClaudeDesktopCookieReader().currentFingerprint() },
         fetch: @escaping Fetch = ClaudeDesktopClient.request) {
        self.read = read
        self.fingerprint = fingerprint
        self.fetch = fetch
    }

    func cancelPending() {
        pending?.task.cancel()
        pending = nil
        cached = nil
        identity = nil
        nextRequest = .distantPast
    }

    func snapshot(force: Bool) async -> ProviderSnapshot {
        do {
            let current = try fingerprint()
            if identity != current {
                pending?.task.cancel()
                pending = nil
                cached = nil
                nextRequest = .distantPast
                identity = current
            }
            if let pending, pending.identity == current { return await pending.task.value }
            // Manual refresh still respects the minimum interval and server backoff.
            if Date() < nextRequest, var cached {
                for index in cached.windows.indices {
                    if let reset = cached.windows[index].resetsAt, reset <= Date() {
                        let old = cached.windows[index]
                        cached.windows[index] = ClaudeCodeProvider.missingWindow(id: old.id, label: old.label)
                    }
                }
                return cached
            }
            let credentials = try read(force)
            guard credentials.fingerprint == current else {
                return ClaudeCodeProvider.unavailable("Claude 桌面端账号正在切换，请刷新")
            }
            let requestID = UUID()
            let fetch = self.fetch
            let fingerprint = self.fingerprint
            let task = Task<ProviderSnapshot, Never> {
                do {
                    let data = try await fetch("/api/organizations/\(credentials.organization)/usage", credentials)
                    try Task.checkCancellation()
                    var snapshot = try Self.parse(data, organization: credentials.organization, now: Date())
                    if let accountData = try? await fetch("/api/account", credentials),
                       let account = try? JSONDecoder().decode(Account.self, from: accountData),
                       let email = account.email_address, !email.isEmpty {
                        let label = String(email.filter { !$0.isNewline && !$0.isWhitespace }.prefix(120))
                        snapshot.statusMessage = snapshot.statusMessage.replacingOccurrences(of: "桌面端", with: "桌面端 · \(label)")
                    }
                    try Task.checkCancellation()
                    guard try fingerprint() == current else {
                        return ClaudeCodeProvider.unavailable("Claude 桌面端账号已切换，请刷新以读取新账号")
                    }
                    return snapshot
                } catch {
                    // Never include response bodies, cookie values, or raw network errors.
                    let message = (error as? ProviderError)?.errorDescription ?? "Claude 桌面端额度请求失败，请稍后刷新"
                    return ClaudeCodeProvider.unavailable("桌面端 · \(message)")
                }
            }
            pending = (requestID, current, task)
            let result = await task.value
            guard pending?.id == requestID else {
                return ClaudeCodeProvider.unavailable("Claude 桌面端账号已切换，等待新账号额度")
            }
            pending = nil
            guard (try? fingerprint()) == current else {
                cached = nil
                identity = nil
                return ClaudeCodeProvider.unavailable("Claude 桌面端登录已变化，请刷新")
            }
            cached = result
            nextRequest = Date().addingTimeInterval(result.windows.contains { $0.isAvailable == true } ? 60 : 300)
            return result
        } catch {
            pending?.task.cancel()
            pending = nil
            cached = nil
            identity = nil
            return ClaudeCodeProvider.unavailable("桌面端 · \((error as? ProviderError)?.errorDescription ?? "无法读取登录信息")")
        }
    }

    private struct Account: Decodable { let email_address: String? }

    static func request(path: String, credentials: ClaudeDesktopCredentials) async throws -> Data {
        guard (path == "/api/organizations/\(credentials.organization)/usage" || path == "/api/account"),
              UUID(uuidString: credentials.organization) != nil,
              let url = URL(string: "https://claude.ai" + path) else {
            throw ProviderError.dataUnavailable("额度请求地址无效")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: ClaudeNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(credentials.sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderError.dataUnavailable("额度响应无效") }
        switch response.statusCode {
        case 200: break
        case 401: throw ProviderError.missingCredentials("登录已失效，请在 Claude 桌面端重新登录")
        case 403: throw ProviderError.dataUnavailable("访问被拒绝或需要网页验证，请检查 Claude 桌面端登录")
        case 429: throw ProviderError.dataUnavailable("请求过于频繁，至少等待 5 分钟后重试")
        default: throw ProviderError.dataUnavailable("额度服务暂不可用（HTTP \(response.statusCode)）")
        }
        guard data.count <= 1_048_576 else { throw ProviderError.dataUnavailable("额度响应过大") }
        return data
    }

    static func parse(_ data: Data, organization: String, now: Date) throws -> ProviderSnapshot {
        struct Response: Decodable {
            struct Window: Decodable {
                let utilization: Double
                let resets_at: String?
            }
            let five_hour: Window?
            let seven_day: Window?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        func window(_ value: Response.Window?) -> ClaudeQuotaSnapshot.Window? {
            guard let value, let timestamp = value.resets_at else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: timestamp)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: timestamp)
            }
            guard let date else { return nil }
            return ClaudeQuotaSnapshot.Window(usedPercentage: value.utilization, resetsAt: date.timeIntervalSince1970)
        }
        let quota = ClaudeQuotaSnapshot(sessionHash: "desktop", observedAt: now.timeIntervalSince1970,
                                        fiveHour: window(response.five_hour), sevenDay: window(response.seven_day))
        var snapshot = try ClaudeCodeProvider.parse(data: JSONEncoder().encode(quota), now: now)
        let hasQuota = snapshot.windows.contains { $0.isAvailable == true }
        snapshot.statusMessage = hasQuota ? "桌面端" : "桌面端 · 账号未提供有效订阅额度"
        return snapshot
    }
}
