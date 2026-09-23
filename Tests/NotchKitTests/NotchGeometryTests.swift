import CoreGraphics
import XCTest

@testable import NotchKit

/// 用**本机实测数据**做断言（PLAN.md §3）。
/// 刘海尺寸随机型与缩放模式变化，所以这些测试同时也在守住「不可硬编码」这条约束。
final class NotchGeometryTests: XCTestCase {

    // MARK: - 有刘海：MacBook Pro 14" (M3 Pro)，缩放到 1728×1117

    private let notchedScreenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let measuredLeftArea = CGRect(x: 0, y: 1085, width: 771.5, height: 32)
    private let measuredRightArea = CGRect(x: 956.5, y: 1085, width: 771.5, height: 32)

    func testNotchedDisplayMatchesMeasuredNotchFrame() throws {
        let notch = try XCTUnwrap(
            NotchGeometry.notchFrame(
                screenFrame: notchedScreenFrame,
                safeAreaTop: 32,
                auxiliaryLeft: measuredLeftArea,
                auxiliaryRight: measuredRightArea
            )
        )

        XCTAssertEqual(notch.minX, 771.5, accuracy: 0.001)
        XCTAssertEqual(notch.minY, 1085, accuracy: 0.001)
        XCTAssertEqual(notch.width, 185, accuracy: 0.001)
        XCTAssertEqual(notch.height, 32, accuracy: 0.001)
    }

    func testNotchFrameIsHorizontallyCentered() throws {
        let notch = try XCTUnwrap(
            NotchGeometry.notchFrame(
                screenFrame: notchedScreenFrame,
                safeAreaTop: 32,
                auxiliaryLeft: measuredLeftArea,
                auxiliaryRight: measuredRightArea
            )
        )
        XCTAssertEqual(notch.midX, notchedScreenFrame.midX, accuracy: 0.001)
        XCTAssertEqual(notch.maxY, notchedScreenFrame.maxY, accuracy: 0.001, "刘海必须贴住屏幕物理上沿")
    }

    // MARK: - 无刘海

    func testDisplayWithoutAuxiliaryAreasHasNoNotch() {
        let notch = NotchGeometry.notchFrame(
            screenFrame: CGRect(x: 1728, y: 37, width: 1920, height: 1080),
            safeAreaTop: 0,
            auxiliaryLeft: nil,
            auxiliaryRight: nil
        )
        XCTAssertNil(notch, "auxiliaryTopLeftArea == nil 就是无刘海的可靠判据")
    }

    func testZeroSafeAreaTopHasNoNotch() {
        let notch = NotchGeometry.notchFrame(
            screenFrame: notchedScreenFrame,
            safeAreaTop: 0,
            auxiliaryLeft: measuredLeftArea,
            auxiliaryRight: measuredRightArea
        )
        XCTAssertNil(notch)
    }

    /// 左右辅助区宽度之和超过屏宽属于异常数据，不能算出负宽度矩形
    func testInvalidAuxiliaryWidthsReturnNil() {
        let notch = NotchGeometry.notchFrame(
            screenFrame: notchedScreenFrame,
            safeAreaTop: 32,
            auxiliaryLeft: CGRect(x: 0, y: 1085, width: 1000, height: 32),
            auxiliaryRight: CGRect(x: 1000, y: 1085, width: 1000, height: 32)
        )
        XCTAssertNil(notch)
    }

    // MARK: - 菜单栏高度

    func testMenubarHeightMatchesMeasuredValue() {
        XCTAssertEqual(
            NotchGeometry.menubarHeight(
                screenFrame: notchedScreenFrame,
                visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1084)
            ),
            33,
            accuracy: 0.001
        )
    }

    func testMenubarHeightIsNeverNegative() {
        XCTAssertEqual(
            NotchGeometry.menubarHeight(screenFrame: notchedScreenFrame, visibleFrame: notchedScreenFrame),
            0
        )
    }

    // MARK: - 卡片行 leading 内边距（右缘露头 / R17 / ADR-044）

    /// 标准展开宽 772、4 张可见、步距 188、露头 12：
    /// padding = 772 − 4×188 − 12 = 8，第 5 张卡左缘落在 760，右缘露出 12pt
    func testLeadingPaddingStandardExpandedWidth() {
        XCTAssertEqual(
            NotchGeometry.cardRowLeadingPadding(expandedWidth: 772, cardStride: 188, visibleCount: 4, peekWidth: 12),
            8,
            accuracy: 0.001
        )
    }

    /// 几何不变式：padding + 可视宽 + peek = 展开宽度（第 5 张卡恰好露出 peek）
    func testPeekFitsExactlyAtRest() {
        let (w, s, n, peek) = (CGFloat(772), CGFloat(188), 4, CGFloat(12))
        let padding = NotchGeometry.cardRowLeadingPadding(expandedWidth: w, cardStride: s, visibleCount: n, peekWidth: peek)
        // 第 visibleCount+1 张卡左缘在 padding + n×stride；它到右缘的距离应恰为 peek
        XCTAssertEqual(w - (padding + CGFloat(n) * s), peek, accuracy: 0.001)
    }

    /// 窄屏上展开宽度不足可视区时夹到 0，不凑出负边距
    func testLeadingPaddingClampsToZeroOnNarrowScreens() {
        XCTAssertEqual(
            NotchGeometry.cardRowLeadingPadding(expandedWidth: 700, cardStride: 188, visibleCount: 4, peekWidth: 12),
            0
        )
        XCTAssertEqual(
            NotchGeometry.cardRowLeadingPadding(expandedWidth: 760, cardStride: 188, visibleCount: 4, peekWidth: 12),
            0
        )
    }
}
