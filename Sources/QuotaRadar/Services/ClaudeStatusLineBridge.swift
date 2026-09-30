import CryptoKit
import Darwin
import Foundation

/// Native statusLine bridge: no Python dependency, credentials or network requests.
struct ClaudeStatusLineBridge: Sendable {
    var home: URL = FileManager.default.homeDirectoryForCurrentUser

    static var defaultSnapshotURL: URL { Self().snapshotURL }
    var supportDirectory: URL { home.appendingPathComponent("Library/Application Support/QuotaRadar/claude-code") }
    var snapshotURL: URL { home.appendingPathComponent("Library/Caches/QuotaRadar/claude-code/statusline-snapshot.json") }
    var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    var stateURL: URL { supportDirectory.appendingPathComponent("integration.json") }
    var helperURL: URL { supportDirectory.appendingPathComponent("quota-radar-statusline") }
    var command: String { "'" + helperURL.path.replacingOccurrences(of: "'", with: "'\\''") + "' --claude-statusline" }

    func install(executable: URL) throws {
        try withLock {
            var settings = try readSettings()
            let alreadyInstalled = FileManager.default.fileExists(atPath: stateURL.path)
            var completed = false
            defer {
                if !completed && !alreadyInstalled { try? FileManager.default.removeItem(at: stateURL) }
            }
            if let state = try readState() {
                guard (settings["statusLine"] as? [String: Any])?["command"] as? String == state["installedCommand"] as? String else {
                    throw BridgeError.message("状态栏已被其他工具修改，请先恢复原状态栏后重新接入")
                }
            } else {
                let original = settings["statusLine"]
                if let original, !(original is NSNull) {
                    guard let object = original as? [String: Any], object["type"] as? String == "command",
                          let oldCommand = object["command"] as? String,
                          !oldCommand.contains("--claude-statusline") else {
                        throw BridgeError.message("现有状态栏配置无法安全包装，请先检查 Claude Code 设置")
                    }
                }
                // Keep a private, exact backup; uninstall restores only statusLine so later edits survive.
                if FileManager.default.fileExists(atPath: settingsURL.path) {
                    let backup = settingsURL.deletingLastPathComponent()
                        .appendingPathComponent("settings.quota-radar-backup-\(UUID().uuidString).json")
                    try writePrivate(Data(contentsOf: settingsURL), to: backup)
                }
                try writeJSON(["installedCommand": command, "originalStatusLine": original ?? NSNull()], to: stateURL)
            }
            // Copy to a stable path: moving/updating the App will not break Claude's command.
            try writePrivate(Data(contentsOf: executable), to: helperURL, mode: 0o700)
            let state = try readState()
            var statusLine = state?["originalStatusLine"] as? [String: Any] ?? [:]
            statusLine["type"] = "command"
            statusLine["command"] = command
            settings["statusLine"] = statusLine
            try writeJSON(settings, to: settingsURL)
            completed = true
        }
    }

    func uninstall() throws {
        try withLock {
            guard let state = try readState() else { return }
            var settings = try readSettings()
            let currentCommand = (settings["statusLine"] as? [String: Any])?["command"] as? String
            guard currentCommand == state["installedCommand"] as? String else {
                throw BridgeError.message("状态栏已被其他工具修改，未覆盖当前配置；原配置仍保存在本地备份中")
            }
            if let original = state["originalStatusLine"], !(original is NSNull) {
                settings["statusLine"] = original
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeJSON(settings, to: settingsURL)
            try FileManager.default.removeItem(at: stateURL)
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
                try FileManager.default.removeItem(at: snapshotURL)
            }
        }
    }

    func resetSource() throws {
        try withLock {
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
                try FileManager.default.removeItem(at: snapshotURL)
            }
        }
    }

    func collect(_ input: Data, now: Date = Date()) throws {
        guard input.count <= 1_048_576,
              let object = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              let session = object["session_id"] as? String, !session.isEmpty else { return }
        let hash = SHA256.hash(data: Data(session.utf8)).map { String(format: "%02x", $0) }.joined()
        let rates = object["rate_limits"] as? [String: Any] ?? [:]
        func window(_ key: String) -> ClaudeQuotaSnapshot.Window? {
            guard let source = rates[key] as? [String: Any],
                  let used = source["used_percentage"] as? NSNumber,
                  let reset = source["resets_at"] as? NSNumber,
                  CFGetTypeID(used) != CFBooleanGetTypeID(), CFGetTypeID(reset) != CFBooleanGetTypeID(),
                  used.doubleValue.isFinite, (0...100).contains(used.doubleValue),
                  reset.doubleValue.isFinite, reset.doubleValue > now.timeIntervalSince1970 else { return nil }
            return .init(usedPercentage: used.doubleValue, resetsAt: reset.doubleValue)
        }
        var snapshot = ClaudeQuotaSnapshot(sessionHash: hash, observedAt: now.timeIntervalSince1970,
                                          fiveHour: window("five_hour"), sevenDay: window("seven_day"))
        try withLock {
            let previous = try? JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: Data(contentsOf: snapshotURL))
            if let previous {
                // Bind to one session because statusLine does not identify the subscription account.
                // This avoids merging or alternating independent accounts. Settings can reset the binding.
                guard previous.sessionHash == hash else { return }
                if previous.fiveHour == snapshot.fiveHour && previous.sevenDay == snapshot.sevenDay {
                    snapshot.observedAt = previous.observedAt
                }
            } else if snapshot.fiveHour == nil && snapshot.sevenDay == nil {
                return
            }
            try writePrivate(JSONEncoder().encode(snapshot), to: snapshotURL)
        }
    }

    func run(input suppliedInput: Data? = nil, output: FileHandle = .standardOutput) -> Int32 {
        let input = suppliedInput ?? FileHandle.standardInput.readDataToEndOfFile()
        // Collection failure must not hide the user's original status line.
        try? collect(input)
        guard let state = try? readState(),
              let original = state["originalStatusLine"] as? [String: Any],
              let originalCommand = original["command"] as? String else { return 0 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", originalCommand]
        let pipe = Pipe()
        process.standardInput = pipe
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            // Broken pipes are possible when the original command doesn't read stdin.
            signal(SIGPIPE, SIG_IGN)
            try? pipe.fileHandleForWriting.write(contentsOf: input)
            try? pipe.fileHandleForWriting.close()
            process.waitUntilExit()
            return process.terminationStatus
        } catch { return 1 }
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any] else {
            throw BridgeError.message("Claude Code settings.json 格式无效，未修改")
        }
        return object
    }

    private func readState() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any] else {
            throw BridgeError.message("采集器安装记录损坏，请检查备份")
        }
        return object
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try writePrivate(JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), to: url)
    }

    private func writePrivate(_ data: Data, to url: URL, mode: Int = 0o600) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".quota-radar-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: mode]) else {
            throw BridgeError.message("无法写入 Claude Code 本地采集文件")
        }
        guard rename(temporary.path, url.path) == 0 else {
            throw BridgeError.message("无法保存 Claude Code 本地采集文件")
        }
    }

    private func withLock<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let descriptor = open(supportDirectory.appendingPathComponent("integration.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw BridgeError.message("无法打开采集器锁") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw BridgeError.message("无法锁定采集器") }
        defer { flock(descriptor, LOCK_UN) }
        return try action()
    }
}

private enum BridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
