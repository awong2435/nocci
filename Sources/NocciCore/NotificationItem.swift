import Foundation

/// One notification as shown by Nocci. Held in memory only; never persisted.
public struct NotificationItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let appBundleID: String
    public let appName: String
    public let title: String
    public let subtitle: String?
    public let body: String
    public let date: Date
    /// Where clicking should go, when known: the link the app attached (Calendar, Messages), or one built from
    /// the notification's ID (Slack). Nil means just open the app. Memory only.
    public let actionURL: URL?

    public init(
        id: String,
        appBundleID: String,
        appName: String,
        title: String,
        subtitle: String? = nil,
        body: String,
        date: Date,
        actionURL: URL? = nil
    ) {
        self.id = id
        self.appBundleID = appBundleID
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.date = date
        self.actionURL = actionURL
    }
}
