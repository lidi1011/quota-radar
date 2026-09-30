import Foundation

struct ClaudeQuotaSnapshot: Codable, Equatable {
    struct Window: Codable, Equatable {
        var usedPercentage: Double
        var resetsAt: Double
    }

    var schemaVersion = 1
    var sessionHash: String
    // This is when the quota payload changed, not proof of a fresh server request.
    var observedAt: Double
    var fiveHour: Window?
    var sevenDay: Window?
}

struct ClaudeCodeProvider: UsageProvider {
    let id: ProviderID = .claude
    var snapshotURL = ClaudeStatusLineBridge.defaultSnapshotURL

    func snapshot(force: Bool) async throws -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return Self.unavailable("CLI · 请在设置 → Claude Code 中接入，等待终端会话返回额度")
        }
        do {
            let data = try Data(contentsOf: snapshotURL)
            return try Self.parse(data: data, now: Date())
        } catch {
            return Self.unavailable("Claude Code 额度快照无法读取，请重新接入")
        }
    }

    static func parse(data: Data, now: Date) throws -> ProviderSnapshot {
        let snapshot = try JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: data)
        guard snapshot.schemaVersion == 1, snapshot.observedAt.isFinite,
              snapshot.observedAt > 0, snapshot.observedAt <= now.timeIntervalSince1970 + 60 else {
            return unavailable("Claude Code 快照版本或时间无效")
        }
        let stale = now.timeIntervalSince1970 - snapshot.observedAt > 900
        func window(_ source: ClaudeQuotaSnapshot.Window?, id: String, label: String) -> UsageWindow {
            guard let source, source.usedPercentage.isFinite,
                  (0...100).contains(source.usedPercentage), source.resetsAt.isFinite,
                  source.resetsAt > now.timeIntervalSince1970 else {
                return missingWindow(id: id, label: label)
            }
            let reset = Date(timeIntervalSince1970: source.resetsAt)
            return UsageWindow(id: id, label: label,
                               remainingPercent: 100 - source.usedPercentage,
                               usedPercent: source.usedPercentage,
                               resetText: RadarFormatters.resetDateTime(reset), resetsAt: reset, isAvailable: true)
        }
        let windows = [window(snapshot.fiveHour, id: "5h", label: "5 小时"),
                       window(snapshot.sevenDay, id: "7d", label: "7 天")]
        let hasQuota = windows.contains { $0.isAvailable != false }
        let time = RadarFormatters.resetDateTime(Date(timeIntervalSince1970: snapshot.observedAt))
        let message: String
        if !hasQuota {
            message = "暂无有效额度 · 请在已接入的 Claude Code 会话中继续使用"
        } else if stale {
            message = "历史快照 \(time) · 超过 15 分钟未变化"
        } else {
            message = "剩余额度 · 快照 \(time) · 刷新仅重读本地数据"
        }
        return ProviderSnapshot(provider: .claude, generatedAt: now, windows: windows,
                                cards: [], progress: nil, statusMessage: "CLI · " + message)
    }

    static func missingWindow(id: String, label: String) -> UsageWindow {
        UsageWindow(id: id, label: label, remainingPercent: 0, usedPercent: 0,
                    resetText: "待更新", isAvailable: false)
    }

    static func unavailable(_ message: String) -> ProviderSnapshot {
        ProviderSnapshot(provider: .claude, generatedAt: Date(), windows: [
            missingWindow(id: "5h", label: "5 小时"),
            missingWindow(id: "7d", label: "7 天")
        ], cards: [], progress: nil, statusMessage: message)
    }
}
