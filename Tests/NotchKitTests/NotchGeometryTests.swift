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
}
