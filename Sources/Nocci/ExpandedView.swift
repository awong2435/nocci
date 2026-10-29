import SwiftUI

/// The open island: each turned-on plugin's section, top to bottom in the order chosen in Settings.
struct ExpandedView: View {
    let plugins: [any NocciPlugin]
    /// Height of the notch, or 0 on screens without one. Content starts below it.
    let notchHeight: CGFloat
    /// Wraps the sections in a scroll view when they're taller than the panel allows.
    let scrolls: Bool
    @Environment(\.nocciFontScale) private var scale

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content
            }
        }
        .padding(.top, notchHeight + 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if plugins.isEmpty {
                Text("Nothing to show. Turn on plugins in Settings.")
                    .font(NocciType.body(scale))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            }
            ForEach(plugins, id: \.id) { plugin in
                plugin.makeSection()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Height the sections need at `width` to show everything without scrolling.
    @MainActor
    static func naturalHeight(of plugins: [any NocciPlugin], width: CGFloat, notchHeight: CGFloat, fontScale: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: ExpandedView(plugins: plugins, notchHeight: notchHeight, scrolls: false)
            .environment(\.nocciFontScale, fontScale)
            .frame(width: width))
        return probe.fittingSize.height
    }
}
