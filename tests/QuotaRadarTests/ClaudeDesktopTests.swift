import Foundation
import SQLite3
import XCTest
@testable import QuotaRadar

@MainActor
final class ClaudeDesktopTests: XCTestCase {
    private func hex(_ text: String) -> Data {
        Data(stride(from: 0, to: text.count, by: 2).map {
            let start = text.index(text.startIndex, offsetBy: $0)
            return UInt8(text[start..<text.index(start, offsetBy: 2)], radix: 16)!
        })
    }

    func testCookieEncryptionKnownVectorsAndHostBinding() throws {
        let key = try ClaudeDesktopCookieReader.deriveKey(password: Data("test-password".utf8))
        XCTAssertEqual(key, hex("c0ffe4c25f07f62bfc6ab011d9efa54e"))
        let old = hex("763130741945bb7b5ccdef0d35cd6a83c07445cea7184a5e63291a1507018c4e8daa57")
        let bound = hex("763130cba8d8b3b813f784aae46dea9258b58b3d19f5f789dc4778df01527afd73e93ef2273e166b323b586230da419bf5ebe63dde394476b84a59551c180af211045e")
        XCTAssertEqual(try ClaudeDesktopCookieReader.decrypt(old, key: key, host: ".claude.ai", version: 23), "synthetic-session")
        XCTAssertEqual(try ClaudeDesktopCookieReader.decrypt(bound, key: key, host: ".claude.ai", version: 24), "synthetic-session")
        XCTAssertThrowsError(try ClaudeDesktopCookieReader.decrypt(bound, key: key, host: "other.example", version: 24))
        XCTAssertThrowsError(try ClaudeDesktopCookieReader.decrypt(Data("v20invalid".utf8), key: key, host: ".claude.ai", version: 24))
        XCTAssertThrowsError(try ClaudeDesktopCookieReader.decrypt(old, key: key, host: ".claude.ai", version: 24))
    }

    func testCookieFingerprintIgnoresOtherDomainsAndTracksOrgAndLogout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("Cookies").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        func sql(_ text: String) { XCTAssertEqual(sqlite3_exec(db, text, nil, nil, nil), SQLITE_OK) }
        sql("CREATE TABLE meta(key TEXT, value INTEGER); INSERT INTO meta VALUES('version',24)")
        sql("CREATE TABLE cookies(name TEXT,host_key TEXT,encrypted_value BLOB,expires_utc INTEGER,path TEXT)")
        sql("INSERT INTO cookies VALUES('sessionKey','.claude.ai',X'010203',0,'/'),('lastActiveOrg','.claude.ai',X'040506',0,'/')")
        let reader = ClaudeDesktopCookieReader(root: root)
        let original = try reader.currentFingerprint()
        sql("INSERT INTO cookies VALUES('sessionKey','.other.ai',X'FFFFFF',0,'/')")
        XCTAssertEqual(try reader.currentFingerprint(), original)
        sql("UPDATE cookies SET encrypted_value=X'070809' WHERE name='lastActiveOrg'")
        XCTAssertNotEqual(try reader.currentFingerprint(), original)
        sql("DELETE FROM cookies WHERE name='sessionKey' AND host_key='.claude.ai'")
        XCTAssertThrowsError(try reader.currentFingerprint())
    }

    func testQuotaParsingPartialNullExpiredAndInvalidWindows() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let data = Data(#"{"five_hour":{"utilization":25,"resets_at":"2030-01-01T00:00:00.123Z"},"seven_day":null}"#.utf8)
        let snapshot = try ClaudeDesktopClient.parse(data, organization: "test-org", now: now)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 75)
        XCTAssertEqual(snapshot.windows[1].isAvailable, false)
        XCTAssertTrue(snapshot.statusMessage.hasPrefix("桌面端"))
        let invalid = Data(#"{"five_hour":{"utilization":101,"resets_at":"2030-01-01T00:00:00Z"},"seven_day":{"utilization":30,"resets_at":"2020-01-01T00:00:00Z"}}"#.utf8)
        XCTAssertTrue(try ClaudeDesktopClient.parse(invalid, organization: "test", now: now).windows.allSatisfy { $0.isAvailable == false })
        XCTAssertThrowsError(try ClaudeDesktopClient.parse(Data("<html>challenge</html>".utf8), organization: "test", now: now))
    }

    func testSourcePreferenceDefaultsCLIAndPersists() {
        let suite = "ClaudeDesktopTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.claudeQuotaSource, .cli)
        settings.claudeQuotaSource = .desktop
        XCTAssertEqual(AppSettings(defaults: defaults).claudeQuotaSource, .desktop)
    }

    func testCacheIsPerAccountAndLogoutClearsIt() async {
        let state = LoginState()
        let counter = RequestCounter()
        let client = ClaudeDesktopClient(read: { _ in try state.read() }, fingerprint: { try state.read().fingerprint }, fetch: { path, credentials in
            if path == "/api/account" { return Data(#"{"email_address":"test@example.com"}"#.utf8) }
            await counter.increment()
            return Self.payload(used: credentials.fingerprint == "a" ? 20 : 70)
        })
        let first = await client.snapshot(force: true)
        let cached = await client.snapshot(force: true)
        XCTAssertEqual(first.windows[0].remainingPercent, 80)
        XCTAssertEqual(cached, first)
        XCTAssertEqual(first.statusMessage, "桌面端 · test@example.com")
        state.set("b")
        let second = await client.snapshot(force: true)
        XCTAssertEqual(second.windows[0].remainingPercent, 30)
        let count = await counter.count
        XCTAssertEqual(count, 2)
        state.set(nil)
        let loggedOut = await client.snapshot(force: true)
        XCTAssertTrue(loggedOut.windows.allSatisfy { $0.isAvailable == false })
    }

    func testAccountSwitchWhileRequestPendingDiscardsOldResult() async {
        let state = LoginState()
        let gate = RequestGate()
        let client = ClaudeDesktopClient(read: { _ in try state.read() }, fingerprint: { try state.read().fingerprint }, fetch: { path, _ in
            if path == "/api/account" { return Data("{}".utf8) }
            await gate.wait()
            return Self.payload(used: 15)
        })
        let task = Task { await client.snapshot(force: true) }
        await gate.started()
        state.set("b")
        await gate.release()
        let result = await task.value
        XCTAssertTrue(result.windows.allSatisfy { $0.isAvailable == false })
    }

    func testFailuresBackOffAndDoNotExposeRawErrors() async {
        let state = LoginState()
        let counter = RequestCounter()
        let client = ClaudeDesktopClient(read: { _ in try state.read() }, fingerprint: { try state.read().fingerprint }, fetch: { _, _ in
            await counter.increment()
            throw NSError(domain: "secret-cookie-value", code: 1)
        })
        let result = await client.snapshot(force: true)
        _ = await client.snapshot(force: true)
        let count = await counter.count
        XCTAssertEqual(count, 1)
        XCTAssertFalse(result.statusMessage.contains("secret-cookie-value"))
        XCTAssertTrue(result.windows.allSatisfy { $0.isAvailable == false })
    }

    func testSourceSwitchCannotBeOverwrittenByPendingDesktopRequest() async {
        let state = LoginState()
        let gate = RequestGate()
        let client = ClaudeDesktopClient(read: { _ in try state.read() }, fingerprint: { try state.read().fingerprint }, fetch: { path, _ in
            if path == "/api/account" { return Data("{}".utf8) }
            await gate.wait()
            return Self.payload(used: 90)
        })
        let suite = "ClaudeDesktopTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.claudeQuotaSource = .desktop
        let store = UsageStore(settings: settings, claudeDesktopClient: client)
        let task = Task { await store.refresh(.claude) }
        await gate.started()
        settings.claudeQuotaSource = .cli
        // Starting the new refresh invalidates the old generation synchronously.
        await store.refresh(.claude)
        let cliResult = store.snapshots[.claude]
        await gate.release()
        await task.value
        XCTAssertEqual(store.snapshots[.claude], cliResult)
    }

    func testReadingTogglesPersistIndependently() {
        let suite = "ClaudeReadingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.claudeCLIReadingEnabled)
        XCTAssertTrue(settings.claudeDesktopReadingEnabled)
        settings.claudeCLIReadingEnabled = false
        settings.claudeQuotaSource = .desktop
        XCTAssertTrue(settings.claudeReadingEnabled)
        settings.claudeDesktopReadingEnabled = false
        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.claudeCLIReadingEnabled)
        XCTAssertFalse(restored.claudeDesktopReadingEnabled)
        XCTAssertFalse(restored.claudeReadingEnabled)
    }

    func testDisabledReadingDoesNotTouchDesktopCredentialsOrFetch() async {
        let state = LoginState()
        let counter = RequestCounter()
        let client = ClaudeDesktopClient(read: { _ in try state.read() }, fingerprint: { try state.read().fingerprint }, fetch: { _, _ in
            await counter.increment()
            return Self.payload(used: 10)
        })
        let suite = "ClaudeReadingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.claudeQuotaSource = .desktop
        settings.claudeDesktopReadingEnabled = false
        let store = UsageStore(settings: settings, claudeDesktopClient: client)
        await store.refresh(.claude, force: true)
        await store.refresh(.claude, force: false)
        XCTAssertEqual(state.readCalls, 0)
        let requests = await counter.count
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(store.snapshots[.claude]!.statusMessage.contains("已暂停读取"))
        settings.claudeQuotaSource = .cli
        settings.claudeCLIReadingEnabled = false
        await store.refresh(.claude)
        XCTAssertTrue(store.snapshots[.claude]!.statusMessage.contains("CLI"))
        XCTAssertTrue(store.snapshots[.claude]!.windows.allSatisfy { $0.isAvailable == false })
        settings.claudeQuotaSource = .desktop
        settings.claudeDesktopReadingEnabled = true
        await store.refresh(.claude)
        XCTAssertGreaterThan(state.readCalls, 0)
        XCTAssertEqual(store.snapshots[.claude]?.windows.first?.remainingPercent, 90)
    }

    func testDisablingReadingRejectsPendingResult() async {
        let state = LoginState()
        let gate = RequestGate()
        let client = ClaudeDesktopClient(read: { _ in try state.read() }, fingerprint: { try state.read().fingerprint }, fetch: { path, _ in
            if path == "/api/account" { return Data("{}".utf8) }
            await gate.wait()
            return Self.payload(used: 30)
        })
        let suite = "ClaudeReadingTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.claudeQuotaSource = .desktop
        let store = UsageStore(settings: settings, claudeDesktopClient: client)
        let request = Task { await store.refresh(.claude) }
        await gate.started()
        settings.claudeDesktopReadingEnabled = false
        store.changeClaudeSource()
        XCTAssertTrue(store.snapshots[.claude]!.statusMessage.contains("已暂停读取"))
        await gate.release()
        await request.value
        XCTAssertTrue(store.snapshots[.claude]!.windows.allSatisfy { $0.isAvailable == false })
    }

    nonisolated private static func payload(used: Int) -> Data {
        Data("{\"five_hour\":{\"utilization\":\(used),\"resets_at\":\"2099-01-01T00:00:00Z\"},\"seven_day\":null}".utf8)
    }
}

private final class LoginState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String? = "a"
    private var calls = 0
    var readCalls: Int { lock.withLock { calls } }
    func set(_ value: String?) { lock.withLock { self.value = value } }
    func read() throws -> ClaudeDesktopCredentials {
        try lock.withLock {
            calls += 1
            guard let value else { throw ProviderError.missingCredentials("未登录") }
            return ClaudeDesktopCredentials(sessionKey: "synthetic", organization: "00000000-0000-0000-0000-000000000001", fingerprint: value)
        }
    }
}

private actor RequestCounter {
    var count = 0
    func increment() { count += 1 }
}

private actor RequestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    func wait() async {
        didStart = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation = $0 }
    }
    func started() async {
        if didStart { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
