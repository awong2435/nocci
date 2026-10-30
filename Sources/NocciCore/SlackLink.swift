import Foundation

/// Links to Slack messages from Slack notifications. A notification carries "<channel ID>_<message timestamp>"
/// but not which workspace it's from, so the user supplies the workspace's team ID once (Settings). The Slack
/// app ignores https message links handed to it, so this builds its own `slack://` link.
public enum SlackLink {
    public static let bundleID = "com.tinyspeck.slackmacgap"

    /// slack://channel?team=<team>&id=<channel>, Slack's documented link: opens the conversation, not the exact
    /// message (an undocumented `message` parameter left Slack loading forever). Nil if the team ID or
    /// notification ID is malformed.
    public static func appURL(notificationID: String, teamID: String) -> URL? {
        guard let team = normalizedTeamID(teamID) else { return nil }
        let parts = notificationID.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2, isSlackID(parts[0]),
              parts[1].contains("."),
              parts[1].allSatisfy({ ($0.isNumber && $0.isASCII) || $0 == "." }) else { return nil }
        var link = URLComponents()
        link.scheme = "slack"
        link.host = "channel"
        link.queryItems = [
            URLQueryItem(name: "team", value: team),
            URLQueryItem(name: "id", value: parts[0]),
        ]
        return link.url
    }

    /// "T01ABCDEF" (or pasted with spaces or as a /client/T01ABCDEF/ URL) -> "T01ABCDEF". Team IDs start with
    /// T (E for Enterprise Grid). Nil if it doesn't look like one.
    public static func normalizedTeamID(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.split(separator: "/").map(String.init).first { $0.first == "T" || $0.first == "E" } ?? trimmed
        let id = candidate.uppercased()
        guard (id.first == "T" || id.first == "E"), (7...14).contains(id.count), isSlackID(id) else { return nil }
        return id
    }

    private static func isSlackID(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { ($0.isUppercase || $0.isNumber) && $0.isASCII }
    }
}
