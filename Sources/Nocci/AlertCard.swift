import AppKit
import SwiftUI
import NocciCore

/// One notification with its full text. Drawn inside the island shape, which supplies the black background.
struct AlertCard: View {
    let item: NotificationItem
    /// Height of the notch, or 0 on screens without one. Content starts below it.
    let notchHeight: CGFloat
    /// Wraps the text in a scroll view when it's taller than the panel allows.
    let scrolls: Bool
    @Environment(\.nocciFontScale) private var scale
    @Environment(\.swipeTracker) private var swipeTracker
    @Environment(\.notificationActions) private var actions

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content
            }
        }
        .padding(.top, notchHeight + 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = AppInfo.icon(for: item.appBundleID) {
                    Image(nsImage: icon).resizable().frame(width: NocciType.iconSize(scale), height: NocciType.iconSize(scale))
                }
                Text(item.appName)
                Spacer()
                // On hover the time gives way to a × that clears this notification, in line with the header so
                // it doesn't sit on the icon.
                ZStack(alignment: .trailing) {
                    Text(item.date.formatted(date: .omitted, time: .shortened))
                        .opacity(isHovered ? 0 : 1)
                    if isHovered {
                        Button { actions.dismiss([item.id]) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8 * scale, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18 * scale, height: 18 * scale)
                                .background(Color(white: 0.3), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Clear")
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                .animation(.easeOut(duration: 0.12), value: isHovered)
            }
            .font(NocciType.meta(scale))
            .foregroundStyle(.white.opacity(0.6))

            Text(item.title)
                .font(NocciType.title(scale))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(NocciType.subtitle(scale))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !item.body.isEmpty {
                Text(item.body)
                    .font(NocciType.body(scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isHovered: Bool {
        swipeTracker?.hoveredID == item.id
    }

    /// Height the card needs at `width` to show everything without scrolling.
    @MainActor
    static func naturalHeight(of item: NotificationItem, width: CGFloat, notchHeight: CGFloat, fontScale: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: AlertCard(item: item, notchHeight: notchHeight, scrolls: false)
            .environment(\.nocciFontScale, fontScale)
            .frame(width: width))
        return probe.fittingSize.height
    }
}
