import Foundation

/// Links to Slack messages from Slack notifications. A notification carries "<channel ID>_<message timestamp>"
/// but not the workspace, so the user supplies the workspace address once (Settings).
public enum SlackLink {
    public static let bundleID = "com.tinyspeck.slackmacgap"

    /// The message's link, like Slack's Copy link: https://<workspace>/archives/<channel>/p<timestamp without
    /// the dot>. Nil if the workspace is empty or the ID isn't in Slack's format.
    public static func messageURL(notificationID: String, workspace: String) -> URL? {
        guard let host = normalizedWorkspace(workspace) else { return nil }
        let parts = notificationID.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty,
              parts[0].allSatisfy({ ($0.isUppercase || $0.isNumber) && $0.isASCII }),
              parts[1].contains("."),
              parts[1].allSatisfy({ ($0.isNumber && $0.isASCII) || $0 == "." }) else { return nil }
        let timestamp = parts[1].replacingOccurrences(of: ".", with: "")
        return URL(string: "https://\(host)/archives/\(parts[0])/p\(timestamp)")
    }

    /// "https://team.slack.com/" or "team.slack.com" -> "team.slack.com". Only Slack hosts are accepted.
    public static func normalizedWorkspace(_ text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        host = String(host.prefix { $0 != "/" })
        guard host.hasSuffix(".slack.com"), host.count > ".slack.com".count,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return host
    }
}
