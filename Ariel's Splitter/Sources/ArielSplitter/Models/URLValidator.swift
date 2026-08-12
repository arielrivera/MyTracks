import Foundation

/// Basic sanity checking for the link box.
///
/// Deliberately permissive: it rejects what is obviously not a link so the
/// Download button cannot be pressed on nonsense, but it does not try to decide
/// whether a site is supported — that is yt-dlp's job, and guessing here would
/// reject valid links from the thousands of sites it handles.
enum URLValidator {

    enum Result: Equatable {
        case empty
        case valid(URL)
        case invalid(reason: String)

        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }

        /// A message worth showing. Nil while empty, since an untouched box
        /// should not be scolding the user.
        var message: String? {
            if case .invalid(let reason) = self { return reason }
            return nil
        }
    }

    static func validate(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        // A pasted link never contains spaces; catching this early gives a much
        // clearer message than a failed URL parse would.
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return .invalid(reason: "A link cannot contain spaces.")
        }

        // People habitually paste "youtube.com/watch?v=..." without a scheme.
        // Treat that as https rather than rejecting it.
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard let url = URL(string: candidate) else {
            return .invalid(reason: "That doesn't look like a valid link.")
        }

        guard let scheme = url.scheme?.lowercased() else {
            return .invalid(reason: "That doesn't look like a valid link.")
        }

        guard scheme == "http" || scheme == "https" else {
            return .invalid(reason: "Only http and https links are supported.")
        }

        guard let host = url.host, !host.isEmpty else {
            return .invalid(reason: "That link is missing a website address.")
        }

        // A bare word like "hello" becomes "https://hello", which parses fine but
        // is not a site. Requiring a dot rejects it, while still allowing the
        // punycode, subdomains and ports that real links use.
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return .invalid(reason: "That doesn't look like a website address.")
        }

        return .valid(url)
    }
}
