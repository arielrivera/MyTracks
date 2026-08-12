import Foundation
import os.log

private func updaterLog(_ message: String) {
    os_log("%{public}@", log: .default, type: .debug, "[ArielSplitter Updater] \(message)")
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(current: String, latest: String)
    case updating
    case updated(from: String, to: String)
    case failed(String)

    var isBusy: Bool { self == .checking || self == .updating }
}

/// Checks for and applies yt-dlp updates using whichever installer owns it.
///
/// Sites change their players regularly and break extraction; the practical fix
/// is a newer yt-dlp. Because Homebrew installs yt-dlp as a Python wheel, its
/// built-in `-U` refuses to act and prints "use pip to update" — so the update
/// must be routed to the owning package manager or it silently does nothing.
struct ToolUpdater {

    struct VersionCheck {
        let current: String
        let latest: String?
        var isOutdated: Bool {
            guard let latest else { return false }
            return latest != current
        }
    }

    /// Ask yt-dlp to compare itself against its release channel.
    ///
    /// For Homebrew and pip installs this only reports; it cannot self-update.
    /// For a standalone binary `-U` would also apply the update, so this is only
    /// ever called from an explicit user action.
    static func checkVersion(ytDlp: URL) -> VersionCheck? {
        let result = MediaToolLocator.run(ytDlp, ["-U"])
        let text = result.output

        func value(after label: String) -> String? {
            for line in text.components(separatedBy: .newlines) where line.contains(label) {
                // e.g. "Current version: stable@2026.06.09 from yt-dlp/yt-dlp"
                guard let range = line.range(of: label) else { continue }
                let remainder = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                let token = remainder.components(separatedBy: " ").first ?? remainder
                let version = token.contains("@") ? token.components(separatedBy: "@").last! : token
                if !version.isEmpty { return version }
            }
            return nil
        }

        guard let current = value(after: "Current version:")
            ?? installedVersionFallback(ytDlp: ytDlp) else { return nil }

        return VersionCheck(current: current, latest: value(after: "Latest version:"))
    }

    private static func installedVersionFallback(ytDlp: URL) -> String? {
        let result = MediaToolLocator.run(ytDlp, ["--version"])
        guard result.succeeded else { return nil }
        let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    /// Outcome of an update attempt, carrying the installer's own output so the
    /// UI can show what actually happened rather than a generic message.
    enum UpdateOutcome: Equatable {
        case success(String)
        case failure(String)
    }

    /// Apply an update via the installer that owns this copy of yt-dlp.
    static func update(ytDlp: URL) -> UpdateOutcome {
        let method = MediaToolLocator.installMethod(of: ytDlp, tool: .ytDlp)
        updaterLog("Updating yt-dlp installed via \(method.label)")

        switch method {
        case .homebrew:
            guard let brew = MediaToolLocator.brewURL() else {
                return .failure("Homebrew owns yt-dlp, but the brew command could not be found.")
            }
            // `brew upgrade` alone will not see a release that the local formula
            // index predates, so refresh it first.
            let refresh = MediaToolLocator.run(brew, ["update", "--quiet"])
            if !refresh.succeeded {
                updaterLog("brew update failed, attempting upgrade anyway: \(refresh.output)")
            }
            let upgrade = MediaToolLocator.run(brew, ["upgrade", "yt-dlp"])
            // Homebrew exits non-zero when the formula is already current.
            if upgrade.succeeded || upgrade.output.lowercased().contains("already installed") {
                return .success(upgrade.output.isEmpty ? "yt-dlp is up to date." : upgrade.output)
            }
            return .failure(upgrade.output)

        case .pip:
            let result = MediaToolLocator.run(
                URL(fileURLWithPath: "/usr/bin/env"),
                ["python3", "-m", "pip", "install", "--upgrade", "yt-dlp"]
            )
            return result.succeeded ? .success(result.output) : .failure(result.output)

        case .standalone:
            let result = MediaToolLocator.run(ytDlp, ["-U"])
            return result.succeeded ? .success(result.output) : .failure(result.output)

        case .unknown:
            return .failure("""
            Could not tell how yt-dlp was installed, so it was left alone.

            Update it the same way you installed it, for example:
              brew upgrade yt-dlp
              python3 -m pip install --upgrade yt-dlp
            """)
        }
    }

    /// The command the user would run themselves — shown in the UI so the
    /// automated path is never a black box.
    static func updateCommand(for ytDlp: URL) -> String {
        switch MediaToolLocator.installMethod(of: ytDlp, tool: .ytDlp) {
        case .homebrew: return "brew upgrade yt-dlp"
        case .pip: return "python3 -m pip install --upgrade yt-dlp"
        case .standalone: return "yt-dlp -U"
        case .unknown: return "brew upgrade yt-dlp"
        }
    }
}
