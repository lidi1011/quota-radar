import Darwin
import Foundation

struct CommandResult: Equatable {
    var status: Int32
    var stdout: String
    var stderr: String
}

enum CommandRunnerError: LocalizedError, Equatable {
    case timedOut(String, TimeInterval)

    var errorDescription: String? {
        switch self {
        case .timedOut(let command, let timeout):
            "\(command) 执行超过 \(String(format: "%.1f", timeout)) 秒，已终止。"
        }
    }
}

struct CommandRunner {
    func run(_ launchPath: String, arguments: [String] = [], stdin: String? = nil, timeout: TimeInterval = 5) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            termination.signal()
        }

        if let stdin {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            try process.run()
            if let data = stdin.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        let stdoutBox = CommandOutputBox()
        let stderrBox = CommandOutputBox()
        let outputGroup = DispatchGroup()

        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBox.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        if termination.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if termination.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = termination.wait(timeout: .now() + 0.5)
            }
            outputGroup.wait()
            throw CommandRunnerError.timedOut(URL(fileURLWithPath: launchPath).lastPathComponent, timeout)
        }

        outputGroup.wait()
        let stdout = String(data: stdoutBox.data, encoding: .utf8) ?? ""
        let stderr = String(data: stderrBox.data, encoding: .utf8) ?? ""
        return CommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    static func firstExecutable(candidates: [String]) -> String? {
        let fileManager = FileManager.default
        return candidates.first { path in
            fileManager.isExecutableFile(atPath: NSString(string: path).expandingTildeInPath)
        }?.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
    }
}

private final class CommandOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }
}
