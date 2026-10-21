import SwiftUI

/// A vertical scroll view that opens on its timeline's Now row (Nir, build 24.1: "'Now' should always be where the
/// view starts, even when future events mean scrolling will go both ways"). Timelines are newest on top
/// (`KhalaTimelineOrder`), so what's coming sits above Now, reachable by scrolling up, and the past runs on below.
///
/// When it scrolls:
/// - on appear, and whenever the rows above Now change while the reader hasn't scrolled (the automations' fire
///   times arrive a moment after the states; an upcoming row turns past) — so Now stays put under the chrome;
/// - when `request` changes (the shell bumps it when the screen's title or its drawer destination is tapped again).
/// Once the reader has scrolled, live updates never move the view. With nothing above Now the list simply starts
/// at its top. The content marks its Now row with `KhalaNowMarker` (placed right before it, zero height).
struct KhalaNowScrollView<Content: View>: View {
    /// The ids of the rows above Now, top to bottom (`KhalaTimeline.idsAboveNow`).
    let idsAboveNow: [String]
    /// Bumped to scroll back to Now.
    let request: Int
    @ViewBuilder let content: () -> Content

    static var nowId: String { "khala.scroll.now" }
    private static var topId: String { "khala.scroll.top" }
    private static var space: String { "khala.scroll" }

    /// The content's top in the scroll view: it moves only when the content scrolls, not when rows are inserted.
    @State private var contentTop: CGFloat = 0
    /// Where the content's top rested after the last scroll this view made.
    @State private var anchoredTop: CGFloat = 0
    /// Until then, content-top changes are this view's own (animated) scroll, not the reader's.
    @State private var settlesAt = Date.distantPast
    @State private var readerScrolled = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topId)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: KhalaContentTopKey.self,
                                    value: geometry.frame(in: .named(Self.space)).minY
                                )
                            }
                        )
                    content()
                }
            }
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(KhalaContentTopKey.self) { top in
                contentTop = top
                if Date() < settlesAt {
                    anchoredTop = top
                } else if abs(top - anchoredTop) > 1 {
                    readerScrolled = true
                }
            }
            .onAppear { anchor(proxy, animated: false) }
            .onChange(of: request) { _ in anchor(proxy, animated: true) }
            .onChange(of: idsAboveNow) { _ in
                guard !readerScrolled else { return }
                anchor(proxy, animated: false)
            }
        }
    }

    private func anchor(_ proxy: ScrollViewProxy, animated: Bool) {
        readerScrolled = false
        anchoredTop = contentTop
        settlesAt = Date().addingTimeInterval(animated ? 0.8 : 0.3)
        let target = idsAboveNow.isEmpty ? Self.topId : Self.nowId
        // After this frame's layout, so the rows just inserted are measured.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .top) }
            } else {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }
}

/// Placed right before a timeline's Now row: zero height in the layout, but its frame reaches `inset` points above
/// the row, so scrolling it to the top leaves the row just under the floating chrome (menu/search buttons).
struct KhalaNowMarker: View {
    let inset: CGFloat

    var body: some View {
        Color.clear
            .frame(height: inset)
            .id(KhalaNowScrollView<EmptyView>.nowId)
            .padding(.top, -inset)
            .accessibilityHidden(true)
    }
}

private struct KhalaContentTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    KhalaNowScrollView(idsAboveNow: ["a", "b"], request: 0) {
        VStack(alignment: .leading, spacing: 0) {
            Text("Title").font(KhalaTheme.largeTitle).padding(.top, 57)
            ForEach(0 ..< 12) { index in
                Text("Upcoming \(12 - index)").frame(height: 60)
            }
            KhalaNowMarker(inset: 57)
            Text("Now").font(KhalaTheme.cardTitle).frame(height: 120)
            ForEach(0 ..< 12) { index in
                Text("Past \(index + 1)").frame(height: 60)
            }
        }
        .padding(.horizontal, KhalaTheme.gutter)
    }
    .background(KhalaGround())
}
