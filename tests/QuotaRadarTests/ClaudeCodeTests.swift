import CoreGraphics
import XCTest
@testable import QuotaRadar

final class ClaudeCodeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func bridge() throws -> ClaudeStatusLineBridge {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return ClaudeStatusLineBridge(home: home)
    }

    private func payload(session: String = "session-a", used: Double = 25, weekly: Double = 40) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "session_id": session,
            "workspace": ["current_dir": "/private/not-to-be-saved"],
            "rate_limits": [
                "five_hour": ["used_percentage": used, "resets_at": now.timeIntervalSince1970 + 18_000],
                "seven_day": ["used_percentage": weekly, "resets_at": now.timeIntervalSince1970 + 604_800]
            ]
        ])
    }

    func testCollectorToProviderShowsRemainingAndDoesNotPersistPayload() throws {
        let bridge = try bridge()
        try bridge.collect(payload(), now: now)
        let data = try Data(contentsOf: bridge.snapshotURL)
        let snapshot = try ClaudeCodeProvider.parse(data: data, now: now)
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [75, 60])
        XCTAssertEqual(snapshot.windows[0].resetsAt, now.addingTimeInterval(18_000))
        XCTAssertTrue(snapshot.cards.isEmpty)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("not-to-be-saved"))
        XCTAssertFalse(text.contains("session-a"))
        let attributes = try FileManager.default.attributesOfItem(atPath: bridge.snapshotURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testRepeatedPayloadDoesNotMakeHistoricalQuotaLookFresh() throws {
        let bridge = try bridge()
        try bridge.collect(payload(), now: now)
        try bridge.collect(payload(), now: now.addingTimeInterval(1_000))
        let snapshot = try ClaudeCodeProvider.parse(data: Data(contentsOf: bridge.snapshotURL), now: now.addingTimeInterval(1_000))
        XCTAssertTrue(snapshot.statusMessage.contains("历史快照"))
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 75)
    }

    func testChangedPayloadUpdatesObservedTime() throws {
        let bridge = try bridge()
        try bridge.collect(payload(), now: now)
        try bridge.collect(payload(used: 30), now: now.addingTimeInterval(1_000))
        let saved = try JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: Data(contentsOf: bridge.snapshotURL))
        XCTAssertEqual(saved.observedAt, now.timeIntervalSince1970 + 1_000)
        XCTAssertEqual(saved.fiveHour?.usedPercentage, 30)
    }

    func testMultipleSessionsDoNotMergeAndResetAllowsNewSource() throws {
        let bridge = try bridge()
        try bridge.collect(payload(), now: now)
        try bridge.collect(payload(session: "other-account", used: 80), now: now)
        var snapshot = try ClaudeCodeProvider.parse(data: Data(contentsOf: bridge.snapshotURL), now: now)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 75)
        try bridge.resetSource()
        try bridge.collect(payload(session: "other-account", used: 80), now: now)
        snapshot = try ClaudeCodeProvider.parse(data: Data(contentsOf: bridge.snapshotURL), now: now)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 20)
    }

    func testMissingPayloadDoesNotBindAndMissingWindowDoesNotMeanFullQuota() throws {
        let bridge = try bridge()
        try bridge.collect(Data(#"{"session_id":"not-ready"}"#.utf8), now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.snapshotURL.path))
        let data = try JSONSerialization.data(withJSONObject: ["session_id": "ready", "rate_limits": [
            "seven_day": ["used_percentage": 0, "resets_at": now.timeIntervalSince1970 + 604_800]
        ]])
        try bridge.collect(data, now: now)
        let snapshot = try ClaudeCodeProvider.parse(data: Data(contentsOf: bridge.snapshotURL), now: now)
        XCTAssertEqual(snapshot.windows[0].isAvailable, false)
        XCTAssertEqual(snapshot.windows[1].remainingPercent, 100)
        XCTAssertEqual(snapshot.windows[1].isAvailable, true)
    }

    func testExpiredQuotaIsUnavailableAndFullUsageIsValidZero() throws {
        let bridge = try bridge()
        try bridge.collect(payload(used: 100), now: now)
        let data = try Data(contentsOf: bridge.snapshotURL)
        let current = try ClaudeCodeProvider.parse(data: data, now: now)
        XCTAssertEqual(current.windows[0].remainingPercent, 0)
        XCTAssertEqual(current.windows[0].isAvailable, true)
        let expired = try ClaudeCodeProvider.parse(data: data, now: now.addingTimeInterval(18_001))
        XCTAssertEqual(expired.windows[0].isAvailable, false)
        XCTAssertEqual(expired.windows[1].isAvailable, true)
    }

    func testInvalidOrMissingValuesNeverAppearAsQuota() throws {
        let bridge = try bridge()
        for raw in [#"{"session_id":"a","rate_limits":{"five_hour":{"used_percentage":true,"resets_at":1800018000}}}"#,
                    #"{"session_id":"a","rate_limits":{"five_hour":{"used_percentage":null,"resets_at":1800018000}}}"#,
                    #"{"session_id":"a","rate_limits":{"five_hour":{"used_percentage":101,"resets_at":1800018000}}}"#] {
            try bridge.collect(Data(raw.utf8), now: now)
            XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.snapshotURL.path))
        }
        XCTAssertThrowsError(try ClaudeCodeProvider.parse(data: Data("{".utf8), now: now))
    }

    func testInstallAndRestorePreserveOtherSettingsAndOriginalStatusLine() throws {
        let bridge = try bridge()
        try FileManager.default.createDirectory(at: bridge.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original: [String: Any] = ["statusLine": ["type": "command", "command": "cat", "padding": 3], "theme": "dark"]
        try JSONSerialization.data(withJSONObject: original).write(to: bridge.settingsURL)
        try bridge.install(executable: URL(fileURLWithPath: "/bin/cat"))
        try bridge.install(executable: URL(fileURLWithPath: "/bin/cat"))
        var settings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bridge.settingsURL)) as? [String: Any])
        let status = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(status["padding"] as? Int, 3)
        XCTAssertEqual(status["command"] as? String, bridge.command)
        settings["theme"] = "light"
        try JSONSerialization.data(withJSONObject: settings).write(to: bridge.settingsURL)
        try bridge.uninstall()
        settings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bridge.settingsURL)) as? [String: Any])
        XCTAssertEqual(settings["theme"] as? String, "light")
        XCTAssertEqual((settings["statusLine"] as? [String: Any])?["command"] as? String, "cat")
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.stateURL.path))
    }

    func testInstallFailureCanBeRetriedWithoutCorruptingSettings() throws {
        let bridge = try bridge()
        XCTAssertThrowsError(try bridge.install(executable: URL(fileURLWithPath: "/missing-binary")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.stateURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.settingsURL.path))
        try bridge.install(executable: URL(fileURLWithPath: "/bin/cat"))
        try bridge.uninstall()
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bridge.settingsURL)) as? [String: Any])
        XCTAssertNil(settings["statusLine"])
    }

    func testUninstallDoesNotOverwriteExternallyChangedStatusLine() throws {
        let bridge = try bridge()
        try bridge.install(executable: URL(fileURLWithPath: "/bin/cat"))
        let edited = Data(#"{"statusLine":{"type":"command","command":"echo new"}}"#.utf8)
        try edited.write(to: bridge.settingsURL)
        XCTAssertThrowsError(try bridge.uninstall())
        XCTAssertEqual(try Data(contentsOf: bridge.settingsURL), edited)
    }

    func testBridgePreservesOriginalStdinAndStdoutEvenWithInvalidQuotaJSON() throws {
        let bridge = try bridge()
        try FileManager.default.createDirectory(at: bridge.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"statusLine":{"type":"command","command":"cat"}}"#.utf8).write(to: bridge.settingsURL)
        try bridge.install(executable: URL(fileURLWithPath: "/bin/cat"))
        for input in [try payload(), Data("invalid-json-but-original-command-still-runs".utf8)] {
            let file = bridge.home.appendingPathComponent(UUID().uuidString)
            XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: nil))
            let output = try FileHandle(forWritingTo: file)
            XCTAssertEqual(bridge.run(input: input, output: output), 0)
            try output.close()
            XCTAssertEqual(try Data(contentsOf: file), input)
        }
    }

    func testConcurrentCollectorsLeaveOneCompleteSnapshot() throws {
        let bridge = try bridge()
        let inputs = try (0..<20).map { try payload(used: Double($0)) }
        let timestamp = now
        DispatchQueue.concurrentPerform(iterations: inputs.count) { index in
            try? bridge.collect(inputs[index], now: timestamp)
        }
        let snapshot = try JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: Data(contentsOf: bridge.snapshotURL))
        XCTAssertTrue((0..<20).contains(Int(try XCTUnwrap(snapshot.fiveHour).usedPercentage)))
        XCTAssertEqual(snapshot.sevenDay?.usedPercentage, 40)
        let names = try FileManager.default.contentsOfDirectory(atPath: bridge.snapshotURL.deletingLastPathComponent().path)
        XCTAssertEqual(names, ["statusline-snapshot.json"])
    }

    func testClaudePreferencesStayRingOnlyAcrossReloads() throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ProviderPreferences.defaults(for: .claude).save(provider: .claude, defaults: defaults)
        XCTAssertTrue(ProviderPreferences.load(provider: .claude, defaults: defaults).visibleCards.isEmpty)
    }

    func testThreeProviderLayoutsRemainReachableAcrossPresets() {
        for preset in LayoutPreset.allCases {
            for mode in ProviderLayoutMode.allCases {
                for mixed in [false, true] {
                    let policy = DashboardLayoutPolicy(preset: preset, providerLayoutMode: mode, providers: [
                        .init(provider: .codex, hasRenderedCards: mixed),
                        .init(provider: .glm, hasRenderedCards: mixed),
                        .init(provider: .claude, hasRenderedCards: false)
                    ])
                    XCTAssertEqual(policy.panelWidth(for: .claude, viewportWidth: 800), preset.ringOnlyPanelWidth)
                    if mode == .horizontal {
                        XCTAssertEqual(policy.scrollAxes(viewportWidth: 800), .both)
                    } else if !mixed {
                        XCTAssertEqual(policy.ringOnlyContentHeight,
                                       preset.ringOnlyPanelWidth * 3 + preset.contentSpacing * 2 + preset.contentVerticalPadding * 2)
                    }
                    let frame = WindowFramePolicy.frameSize(
                        contentLayoutSize: CGSize(width: policy.minimumContentWidth, height: policy.ringOnlyContentHeight ?? 1_200),
                        layoutInsets: CGSize(width: 0, height: 52),
                        visibleFrame: CGRect(x: 0, y: 0, width: 1_024, height: 768))
                    XCTAssertLessThanOrEqual(frame.width, 1_024)
                    XCTAssertLessThanOrEqual(frame.height, 768)
                }
            }
        }
    }
}
