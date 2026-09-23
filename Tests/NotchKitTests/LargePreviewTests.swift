import CoreGraphics
import XCTest

@testable import NotchKit

/// 大预览浮层（F4 / ADR-045）的几何与焦点状态机。
/// 含 @MainActor 的 PanelSelection/PanelFocus 用例，整类标主演员。
@MainActor
final class LargePreviewTests: XCTestCase {

    // MARK: - LargePreviewLayout.displaySize

    func testDisplaySizeFitsLandscapeAtMax() {
        // 16:10 恰好等于最大框比例 → 整框占满
        let size = LargePreviewLayout.displaySize(aspect: 640.0 / 400.0)
        XCTAssertEqual(size.width, 640)
        XCTAssertEqual(size.height, 400)
    }

    func testDisplaySizeShrinksForPortraitByHeight() {
        // 竖窗（aspect 0.5）：高度顶到 400，宽度 = 400 × 0.5
        let size = LargePreviewLayout.displaySize(aspect: 0.5)
        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, 400)
    }

    func testDisplaySizeShrinksForSquareByHeight() {
        let size = LargePreviewLayout.displaySize(aspect: 1)
        XCTAssertEqual(size.width, 400)
        XCTAssertEqual(size.height, 400)
    }

    func testDisplaySizeFallsBackOnDegenerateAspect() {
        for bad in [CGFloat(0), -1, .nan, .infinity] {
            let size = LargePreviewLayout.displaySize(aspect: bad)
            XCTAssertEqual(size.width, 640, "aspect \(bad) 应回退默认比例")
            XCTAssertEqual(size.height, 400)
        }
    }

    // MARK: - 面板增高

    func testCardSizeAddsPaddingInfoAndSpacing() {
        let card = LargePreviewLayout.cardSize(image: CGSize(width: 640, height: 400))
        XCTAssertEqual(card.width, 640 + 24, "左右内边距 12×2")
        XCTAssertEqual(card.height, 400 + 34 + 8 + 24, "信息行 34 + 间距 8 + 内边距 12×2")
    }

    func testPanelExtraHeightIncludesGapAndCard() {
        let extra = LargePreviewLayout.panelExtraHeight(cardHeight: 466)
        XCTAssertEqual(extra, 466 + 10, "预览带与卡片之间的间隙 10")
    }

    func testPanelExtraHeightEndToEnd() {
        // 由窗口宽高比一步到面板增高，视图与控制器都消费同一个值
        let extra = LargePreviewLayout.panelExtraHeight(windowAspect: 640.0 / 400.0)
        let expected = LargePreviewLayout.panelExtraHeight(
            cardHeight: LargePreviewLayout.cardSize(image: CGSize(width: 640, height: 400)).height
        )
        XCTAssertEqual(extra, expected, accuracy: 0.001)
    }

    // MARK: - PanelSelection.ensureVisible（F8）

    /// 前四张本来就完整可见 → 不产生任何滚动
    func testEnsureVisibleDoesNothingWithinFirstScreen() {
        let selection = PanelSelection(visibleCount: 4, cardStride: 188)
        selection.ensureVisible(index: 3, totalCount: 10)
        selection.settleImmediately()

        XCTAssertEqual(selection.offset, 0, accuracy: 0.01)
    }

    /// 选中比可视区更靠后的卡 → 滚到它完整可见（右缘对齐）
    func testEnsureVisibleScrollsForward() {
        let selection = PanelSelection(visibleCount: 4, cardStride: 188)
        selection.ensureVisible(index: 6, totalCount: 10)
        selection.settleImmediately()

        // (6+1-4)×188 = 564：第 6 张成为可视区最后一张
        XCTAssertEqual(selection.offset, 188 * 3, accuracy: 0.01)
    }

    /// 滚过头后再选前面的卡 → 滚回去（左缘对齐）
    func testEnsureVisibleScrollsBackward() {
        let selection = PanelSelection(visibleCount: 4, cardStride: 188)
        selection.scroll(by: 188 * 6, totalCount: 10)
        selection.settleImmediately()

        selection.ensureVisible(index: 0, totalCount: 10)
        selection.settleImmediately()

        XCTAssertEqual(selection.offset, 0, accuracy: 0.01)
    }

    /// 已经完整可见 → 保持原位（停在半张卡中间也不被拉走）
    func testEnsureVisibleKeepsFreePositionWhenAlreadyVisible() {
        let selection = PanelSelection(visibleCount: 4, cardStride: 188)
        let midway: CGFloat = 188 * 2 + 60   // 第 2~5 张都完整可见的停位
        selection.scroll(by: midway, totalCount: 10)
        selection.settleImmediately()

        selection.ensureVisible(index: 3, totalCount: 10)
        selection.settleImmediately()

        XCTAssertEqual(selection.offset, midway, accuracy: 0.01, "已可见的卡不应被吸附")
    }

    /// 越界索引夹紧到 maxOffset
    func testEnsureVisibleClampsAtMaxOffset() {
        let selection = PanelSelection(visibleCount: 4, cardStride: 188)
        selection.ensureVisible(index: 99, totalCount: 10)
        selection.settleImmediately()

        XCTAssertEqual(selection.offset, 188 * 6, accuracy: 0.01)
    }

    // MARK: - PanelFocus（F4/F8 状态机）

    @MainActor
    func testSelectShowsPreviewImmediately() {
        let focus = PanelFocus()
        focus.select(42)

        XCTAssertEqual(focus.focusedWindowID, 42)
        XCTAssertTrue(focus.isPreviewVisible, "键盘选中无延迟（F8）")
    }

    @MainActor
    func testHidePreviewKeepsFocus() {
        let focus = PanelFocus()
        focus.select(42)
        focus.hidePreview()

        XCTAssertFalse(focus.isPreviewVisible)
        XCTAssertEqual(focus.focusedWindowID, 42, "焦点保留，←→ 以它为基准继续移动")
    }

    @MainActor
    func testResetClearsEverything() {
        let focus = PanelFocus()
        focus.select(42)
        focus.reset()

        XCTAssertNil(focus.focusedWindowID)
        XCTAssertFalse(focus.isPreviewVisible)
    }

    @MainActor
    func testHoverShowsPreviewAfterDelay() async throws {
        let focus = PanelFocus()
        focus.previewDelay = 0.05
        focus.hover(7)

        XCTAssertFalse(focus.isPreviewVisible, "延迟内不弹")
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(focus.focusedWindowID, 7)
        XCTAssertTrue(focus.isPreviewVisible)
    }

    @MainActor
    func testHoverEndedOnOtherCardDoesNotCancelPendingHover() async throws {
        let focus = PanelFocus()
        focus.previewDelay = 0.05
        focus.hover(7)
        // 离开事件顺序不保证：模拟「另一张卡的离开」晚于 hover(7) 到达，
        // 不能把 7 的计时取消
        focus.hoverEnded(99)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(focus.focusedWindowID, 7, "别人的离开不该取消我的计时")
    }

    @MainActor
    func testHoverThenLeaveCancelsPreview() async throws {
        let focus = PanelFocus()
        focus.previewDelay = 0.05
        focus.hover(7)
        focus.hoverEnded(7)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertNil(focus.focusedWindowID)
        XCTAssertFalse(focus.isPreviewVisible)
    }

    @MainActor
    func testSwitchingHoverRetargetsPreview() async throws {
        let focus = PanelFocus()
        focus.previewDelay = 0.05
        focus.hover(7)
        focus.hover(8)   // 换卡：7 的计时作废
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(focus.focusedWindowID, 8)
    }
}
