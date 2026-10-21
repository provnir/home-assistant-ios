import SwiftUI

/// One timeline row: a 44 pt time column, the dot on the vertical line, then the row's content. Each row draws
/// its own stretch of the line (above and below its dot) so the line stays continuous whatever the rows' heights:
/// ink while it runs through the past (below Now: timelines are newest on top), the light line above Now
/// (`KhalaTimelineLine`).
struct KhalaTimelineRow<Content: View>: View {
    let time: String
    let isNow: Bool
    let dot: KhalaTimelineDot.Style
    /// Distance from the row's top to the dot's centre; the time label is aligned on it.
    let dotCenter: CGFloat
    /// Line colour above and below the dot; nil draws no line there.
    let lineAbove: Color?
    let lineBelow: Color?
    @ViewBuilder let content: () -> Content

    var body: some View {
        let lineX = KhalaTheme.timeColumn + KhalaTheme.dotColumn / 2 - KhalaTheme.lineWidth / 2
        HStack(alignment: .top, spacing: 0) {
            Text(time)
                .font(isNow ? KhalaTheme.timeNow : KhalaTheme.time)
                .foregroundStyle(isNow ? KhalaTheme.ink : KhalaTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: KhalaTheme.timeColumn, height: 18, alignment: .leading)
                .padding(.top, max(0, dotCenter - 9))
            Color.clear
                .frame(width: KhalaTheme.dotColumn, height: 1)
            content()
                .padding(.leading, KhalaTheme.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, KhalaTheme.rowGap)
        .background(alignment: .topLeading) {
            VStack(spacing: 0) {
                (lineAbove ?? Color.clear)
                    .frame(width: KhalaTheme.lineWidth, height: dotCenter)
                (lineBelow ?? Color.clear)
                    .frame(width: KhalaTheme.lineWidth)
                    .frame(maxHeight: .infinity)
            }
            .padding(.leading, lineX)
        }
        .overlay(alignment: .topLeading) {
            let size = dot == .now ? KhalaTimelineDot.nowSize : KhalaTimelineDot.size
            KhalaTimelineDot(style: dot)
                .padding(.leading, KhalaTheme.timeColumn + KhalaTheme.dotColumn / 2 - size / 2)
                .padding(.top, dotCenter - size / 2)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 0) {
        KhalaTimelineRow(
            time: "06:48",
            isNow: false,
            dot: .past(.sun),
            dotCenter: 11,
            lineAbove: nil,
            lineBelow: KhalaTheme.ink
        ) {
            Text(KhalaText.sunrise).font(KhalaTheme.body).foregroundStyle(KhalaTheme.muted).frame(height: 22)
        }
        KhalaTimelineRow(
            time: KhalaText.now,
            isNow: true,
            dot: .now,
            dotCenter: 24,
            lineAbove: KhalaTheme.ink,
            lineBelow: KhalaTheme.line
        ) {
            Text("Card").frame(maxWidth: .infinity, minHeight: 120).background(KhalaTheme.card)
        }
        KhalaTimelineRow(
            time: "18:02",
            isNow: false,
            dot: .upcoming(.sun),
            dotCenter: 11,
            lineAbove: KhalaTheme.line,
            lineBelow: KhalaTheme.line
        ) {
            Text(KhalaText.sunset).font(KhalaTheme.body).foregroundStyle(KhalaTheme.muted).frame(height: 22)
        }
    }
    .padding(.horizontal, KhalaTheme.gutter)
    .background(KhalaGround())
}
