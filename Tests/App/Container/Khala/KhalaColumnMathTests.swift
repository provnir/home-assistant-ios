@testable import HomeAssistant
import Testing

struct KhalaColumnMathTests {
    @Test func compactWidthKeepsTheFullWidth() {
        #expect(KhalaColumnMath.maximumWidth(kind: .readable, isRegularWidth: false) == nil)
        #expect(KhalaColumnMath.maximumWidth(kind: .wide, isRegularWidth: false) == nil)
    }

    @Test func regularWidthHoldsAColumn() {
        #expect(KhalaColumnMath.maximumWidth(kind: .readable, isRegularWidth: true) == KhalaColumnMath.readableWidth)
        #expect(KhalaColumnMath.maximumWidth(kind: .wide, isRegularWidth: true) == KhalaColumnMath.wideWidth)
        #expect(KhalaColumnMath.readableWidth < KhalaColumnMath.wideWidth)
    }

    @Test func phoneWidthsKeepTwoCameraTiles() {
        // A phone, the outer display and a Split View half all stay at the two columns the screen always had.
        for width in [0.0, 280, 335, 390, 430] {
            #expect(KhalaColumnMath.tileColumns(available: width, spacing: 12) == 2)
        }
    }

    @Test func wideWidthsFitMoreTiles() {
        // 3 × 200 + 2 × 12 = 624: three fit from there, four from 4 × 200 + 3 × 12 = 836.
        #expect(KhalaColumnMath.tileColumns(available: 623, spacing: 12) == 2)
        #expect(KhalaColumnMath.tileColumns(available: 624, spacing: 12) == 3)
        #expect(KhalaColumnMath.tileColumns(available: 836, spacing: 12) == 4)
    }
}
