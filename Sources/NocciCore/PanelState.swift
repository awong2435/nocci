/// The four states of the notch panel (PLAN.md section 1).
public enum PanelState: Equatable, Sendable {
    /// Nothing unread and no alert. The hover hot zone still works.
    case hidden
    /// Unread badge by the notch.
    case counter
    /// A single notification card dropped from the notch.
    case alert(NotificationItem.ID)
    /// The full scrolling list.
    case list
}
