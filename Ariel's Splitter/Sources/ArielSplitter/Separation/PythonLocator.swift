import Foundation
import os.log

private func pythonLog(_ message: String) {
    os_log("%{public}@", log: .default, type: .debug, "[ArielSplitter Python] \(message)")
}

/// Finds a Python interpreter that can actually run separate.py.
///
/// `/usr/bin/env python3` is not good enough: a GUI app inherits a minimal PATH,
/// so it resolves to whichever bare system interpreter comes first — typically
/// one with no numpy, torch or demucs installed. The separation then dies with
/// ModuleNotFoundError even though the packages are installed in a virtualenv.
///
/// So rather than trusting a name, each candidate is probed for the modules the
/// script imports, and the first complete one wins.
enum PythonLocator {

    /// Modules separate.py imports at top level. psutil is deliberately absent:
    /// the script guards it and only loses the CPU/memory readout without it.
    static let requiredModules = ["numpy", "torch", "demucs", "soundfile", "librosa"]

    struct Interpreter {
        let url: URL
        let missingModules: [String]
        var isComplete: Bool { missingModules.isEmpty }
    }

    private static let defaultsKey = "pythonInterpreterPath"

    static var overridePath: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
            cached = nil
        }
    }

    private static var cached: Interpreter?
    private static let cacheLock = NSLock()

    /// Candidate interpreters, best first.
    ///
    /// - Parameter scriptURL: location of separate.py, used to find a virtualenv
    ///   sitting alongside the project rather than hard-coding one.
    static func candidates(scriptURL: URL?) -> [URL] {
        var paths: [String] = []

        if let override = overridePath { paths.append(override) }

        // An already-activated environment wins over discovery.
        if let virtualEnv = ProcessInfo.processInfo.environment["VIRTUAL_ENV"] {
            paths.append("\(virtualEnv)/bin/python3")
        }

        // Walk up from the script looking for a venv checked in beside the project.
        if let scriptURL {
            var directory = scriptURL.deletingLastPathComponent()
            for _ in 0..<8 {
                for venvName in ["venv", ".venv", "env"] {
                    paths.append(directory.appendingPathComponent("\(venvName)/bin/python3").path)
                }
                let parent = directory.deletingLastPathComponent()
                if parent == directory { break }
                directory = parent
            }
        }

        paths += [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        var seen = Set<String>()
        return paths.compactMap { path in
            guard !seen.contains(path) else { return nil }
            seen.insert(path)
            guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    /// Which required modules a given interpreter is missing.
    ///
    /// Uses importlib.util.find_spec rather than a real import: importing torch
    /// costs seconds, and probing several candidates that way would stall the UI.
    static func missingModules(for interpreter: URL) -> [String] {
        let names = requiredModules.map { "'\($0)'" }.joined(separator: ", ")
        let probe = """
        import importlib.util
        print(','.join(n for n in [\(names)] if importlib.util.find_spec(n) is None))
        """
        let result = MediaToolLocator.run(interpreter, ["-c", probe])
        guard result.succeeded else { return requiredModules }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? [] : output.components(separatedBy: ",")
    }

    /// The best available interpreter, cached after the first successful probe.
    static func locate(scriptURL: URL?) -> Interpreter? {
        cacheLock.lock()
        if let cached, FileManager.default.isExecutableFile(atPath: cached.url.path) {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var best: Interpreter?
        for candidate in candidates(scriptURL: scriptURL) {
            let missing = missingModules(for: candidate)
            let interpreter = Interpreter(url: candidate, missingModules: missing)
            pythonLog("Probed \(candidate.path): missing \(missing.isEmpty ? "nothing" : missing.joined(separator: ", "))")

            if interpreter.isComplete {
                cacheLock.lock()
                cached = interpreter
                cacheLock.unlock()
                return interpreter
            }
            // Remember the closest match so the error can name what is missing.
            if best == nil || missing.count < best!.missingModules.count {
                best = interpreter
            }
        }
        return best
    }

    static func clearCache() {
        cacheLock.lock()
        cached = nil
        cacheLock.unlock()
    }
}
