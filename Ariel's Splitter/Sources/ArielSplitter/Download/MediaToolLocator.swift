import Foundation
import os.log

private func toolLog(_ message: String) {
    os_log("%{public}@", log: .default, type: .debug, "[ArielSplitter Tools] \(message)")
}

enum MediaTool: String {
    case ytDlp = "yt-dlp"
    case ffmpeg = "ffmpeg"
}

/// How a tool was installed, which decides how it must be updated.
///
/// This matters because Homebrew ships yt-dlp as a Python wheel, and yt-dlp's
/// own `-U` refuses to touch those installs ("you installed yt-dlp with pip...").
/// Running the wrong updater silently does nothing.
enum InstallMethod: Equatable {
    case homebrew
    case pip
    case standalone
    case unknown

    var label: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .pip: return "pip"
        case .standalone: return "standalone binary"
        case .unknown: return "unknown"
        }
    }

    var canSelfUpdate: Bool { self == .standalone }
}

/// Result of running a command to completion.
struct CommandResult {
    let status: Int32
    let output: String
    var succeeded: Bool { status == 0 }
}

enum MediaToolLocator {
    /// A GUI app launched from Finder gets a minimal PATH that excludes
    /// /opt/homebrew/bin, so `/usr/bin/env yt-dlp` fails even though the tool
    /// works fine in Terminal. Probe the real install locations directly.
    private static let searchDirectories: [String] = [
        "/opt/homebrew/bin",                       // Apple Silicon Homebrew
        "/usr/local/bin",                          // Intel Homebrew, manual installs
        "\(NSHomeDirectory())/.local/bin",         // pip --user, pipx
        "/opt/local/bin",                          // MacPorts
        "/usr/bin",
    ]

    private static func defaultsKey(_ tool: MediaTool) -> String {
        "toolPath.\(tool.rawValue)"
    }

    /// A path the user picked manually, which always wins over discovery.
    static func overridePath(for tool: MediaTool) -> String? {
        UserDefaults.standard.string(forKey: defaultsKey(tool))
    }

    static func setOverridePath(_ path: String?, for tool: MediaTool) {
        if let path {
            UserDefaults.standard.set(path, forKey: defaultsKey(tool))
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey(tool))
        }
    }

    static func locate(_ tool: MediaTool) -> URL? {
        if let override = overridePath(for: tool),
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        for directory in searchDirectories {
            let candidate = (directory as NSString).appendingPathComponent(tool.rawValue)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        // Last resort: ask a login shell, which sources the user's profile and
        // therefore knows about less conventional install locations.
        if let found = locateViaLoginShell(tool) {
            return found
        }

        toolLog("Could not locate \(tool.rawValue)")
        return nil
    }

    private static func locateViaLoginShell(_ tool: MediaTool) -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let result = run(URL(fileURLWithPath: shell), ["-lc", "command -v \(tool.rawValue)"])
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func brewURL() -> URL? {
        for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    /// Determine how yt-dlp was installed by asking the package managers, rather
    /// than guessing from the path — a Homebrew install and a manual install can
    /// both live in /usr/local/bin.
    static func installMethod(of toolURL: URL, tool: MediaTool) -> InstallMethod {
        if let brew = brewURL(),
           run(brew, ["list", "--versions", tool.rawValue]).succeeded {
            return .homebrew
        }

        let pipShow = run(URL(fileURLWithPath: "/usr/bin/env"),
                          ["python3", "-m", "pip", "show", tool.rawValue])
        if pipShow.succeeded, pipShow.output.contains("Name:") {
            return .pip
        }

        // yt-dlp built as a single binary knows it can update itself.
        if tool == .ytDlp {
            let probe = run(toolURL, ["--version"])
            if probe.succeeded { return .standalone }
        }

        return .unknown
    }

    /// Run a command to completion and capture combined output.
    ///
    /// Reads both pipes concurrently before waiting: a child that fills the pipe
    /// buffer blocks forever if we wait first and read afterwards.
    @discardableResult
    static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil) -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: "Could not launch \(executable.path): \(error.localizedDescription)")
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var collected = Data()

        for handle in [outPipe.fileHandleForReading, errPipe.fileHandleForReading] {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let data = handle.readDataToEndOfFile()
                lock.lock()
                collected.append(data)
                lock.unlock()
                group.leave()
            }
        }

        process.waitUntilExit()
        group.wait()

        return CommandResult(
            status: process.terminationStatus,
            output: String(data: collected, encoding: .utf8) ?? ""
        )
    }
}
