import SwiftUI

/// A one-line timeline row (time, dot, text with an optional muted tail), as in the mockups' "Recent" and the
/// camera's "Now · Watching" rows, drawn on `KhalaTimelineRow` so the line runs through.
struct KhalaPlainTimelineRow: View {
    let time: String
    let text: String
    let detail: String?
    let dot: KhalaTimelineDot.Style
    let lineAbove: Color?
    let lineBelow: Color?
    var isNow = false

    var body: some View {
        KhalaTimelineRow(
            time: time,
            isNow: isNow,
            dot: dot,
            dotCenter: 11,
            lineAbove: lineAbove,
            lineBelow: lineBelow
        ) {
            HStack(spacing: 0) {
                Text(text)
                    .font(isNow ? KhalaTheme.cardTitle : KhalaTheme.body)
                    .foregroundStyle(KhalaTheme.ink)
                if let detail {
                    Text(verbatim: " · \(detail)")
                        .font(KhalaTheme.body)
                        .foregroundStyle(KhalaTheme.muted)
                }
            }
            .lineLimit(1)
            .frame(height: 22)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        KhalaPlainTimelineRow(time: "19:40", text: "Arrived home", detail: "yesterday", dot: .past(.car),
                              lineAbove: nil, lineBelow: KhalaTheme.line)
        KhalaPlainTimelineRow(time: "Now", text: "Watching", detail: "all clear", dot: .now,
                              lineAbove: KhalaTheme.line, lineBelow: nil, isNow: true)
    }
    .padding()
}
