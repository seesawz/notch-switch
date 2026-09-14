import CoreGraphics
import XCTest

@testable import NotchKit

/// MRU 排序逻辑。macOS 没有公开的窗口最近使用顺序 API（PLAN.md §4.3），
/// 这套规则完全是我们自己维护的，所以必须被测试守住。
final class MRUOrderTests: XCTestCase {

    func testTouchMovesWindowToFront() {
        var mru = MRUOrder()
        mru.seedUnknown([1, 2, 3])

        mru.touch(3)

        XCTAssertEqual(mru.order, [3, 1, 2])
    }

    func testTouchIsIdempotent() {
        var mru = MRUOrder()
        mru.seedUnknown([1, 2, 3])

        mru.touch(2)
        mru.touch(2)

        XCTAssertEqual(mru.order, [2, 1, 3], "重复聚焦同一个窗口不应该产生重复项")
    }

    func testPruneRemovesClosedWindows() {
        var mru = MRUOrder()
        mru.seedUnknown([1, 2, 3, 4])

        mru.prune(keeping: [1, 3])

        XCTAssertEqual(mru.order, [1, 3])
    }

    func testSeedUnknownAppendsWithoutDuplicating() {
        var mru = MRUOrder()
        mru.seedUnknown([1, 2])
        mru.seedUnknown([2, 3])

        XCTAssertEqual(mru.order, [1, 2, 3])
    }

    func testRankIsZeroForMostRecent() {
        var mru = MRUOrder()
        mru.seedUnknown([1, 2, 3])
        mru.touch(2)

        XCTAssertEqual(mru.rank(of: 2), 0)
        XCTAssertEqual(mru.rank(of: 1), 1)
        XCTAssertEqual(mru.rank(of: 999), Int.max, "没记录过的窗口排最后")
    }

    func testSortedFollowsMRUAndKeepsOriginalOrderForUnknown() {
        var mru = MRUOrder()
        mru.seedUnknown([10])
        mru.touch(10)

        // 20、30 没被记录，应保持传入顺序排在后面
        let sorted = mru.sorted([20, 30, 10], id: { $0 })

        XCTAssertEqual(sorted, [10, 20, 30])
    }
}

/// 滚动的逐帧跟随（PLAN.md §6.5）。
///
/// 这段数学决定「丝滑」与否：整数步进是瞬移，指数逼近才有惯性收尾。
final class ScrollFollowTests: XCTestCase {

    func testAddInputClampsIntoValidRange() {
        var follow = ScrollFollow()

        follow.addInput(-100, maxOffset: 500)
        XCTAssertEqual(follow.target, 0, "不能滚到负数")

        follow.addInput(9999, maxOffset: 500)
        XCTAssertEqual(follow.target, 500, "不能超过最大位移")
    }

    func testAdvanceConvergesAndReportsSettled() {
        var follow = ScrollFollow()
        follow.addInput(188, maxOffset: 1000)

        var frames = 0
        while follow.advance() {
            frames += 1
            XCTAssertLessThan(frames, 200, "应该在有限帧内收敛")
        }

        XCTAssertEqual(follow.offset, 188, accuracy: 0.001)
        XCTAssertGreaterThan(frames, 1, "必须是多帧逼近，而不是一帧跳到（否则就是瞬移）")
    }

    /// 停在半张卡中间也**不能**被拉回边界——松手瞬间再拽一下会破坏跟手感
    func testOffsetStaysWhereItLandsWithoutSnapping() {
        var follow = ScrollFollow()
        let midway: CGFloat = 188 * 2 + 60
        follow.addInput(midway, maxOffset: 2000)
        while follow.advance() {}

        XCTAssertEqual(follow.offset, midway, accuracy: 0.001)
        XCTAssertEqual(follow.target, midway, accuracy: 0.001)
    }

    func testOffsetApproachesTargetMonotonically() {
        var follow = ScrollFollow()
        follow.addInput(188, maxOffset: 1000)

        var previous = follow.offset
        for _ in 0..<10 {
            _ = follow.advance()
            XCTAssertGreaterThanOrEqual(follow.offset, previous, "应单调逼近目标，不来回抖")
            previous = follow.offset
        }
    }

    func testAnchorIndexRoundsToNearestCard() {
        var follow = ScrollFollow()
        follow.addInput(188 * 2 + 60, maxOffset: 2000)   // 停在 2.3 张的位置
        while follow.advance() {}

        XCTAssertEqual(follow.anchorIndex(stride: 188), 2, "2.3 张应算作第 2 张可见")
    }

    func testAnchorIndexHandlesZeroStride() {
        let follow = ScrollFollow()
        XCTAssertEqual(follow.anchorIndex(stride: 0), 0, "不能除零")
    }
}

/// 动画档位（PLAN.md §6.3 / ADR-025）
final class PanelTransitionTests: XCTestCase {

    /// 点击卡片后的收起必须比鼠标移开更快——用户已经做完决定了，面板要迅速让开。
    /// 这条是产品决策，不能靠以后随手调参数时无意破坏。
    func testActionCollapseIsFasterThanHoverCollapse() {
        XCTAssertLessThan(
            PanelTransition.collapseAction.duration,
            PanelTransition.collapseHover.duration
        )
    }

    /// 收起一律不能比展开慢，否则会显得黏
    func testCollapseIsNotSlowerThanExpand() {
        XCTAssertLessThanOrEqual(PanelTransition.collapseAction.duration, PanelTransition.expand.duration)
        XCTAssertLessThanOrEqual(PanelTransition.collapseHover.duration, PanelTransition.expand.duration)
    }

    func testImmediateHasNoDurationAndSkipsContentAnimation() {
        XCTAssertEqual(PanelTransition.immediate.duration, 0)
        XCTAssertFalse(PanelTransition.immediate.animatesContent)
        XCTAssertTrue(PanelTransition.collapseAction.animatesContent)
    }
}

/// 玻璃材质决策（ADR-034）。
///
/// 这条规则的含义是「材质必须跟着系统设置走」，最怕被后人为了方便改回硬编码，
/// 所以逐条钉住。
final class GlassMaterialPolicyTests: XCTestCase {

    /// 「减弱透明度」是无障碍要求，优先级高于一切——包括我们自己的调试开关。
    /// Apple 对该选项的要求：window 背景「should not be semi-transparent; they should be opaque」。
    func testReduceTransparencyForcesOpaque() {
        XCTAssertEqual(
            GlassMaterialPolicy.resolve(reduceTransparency: true, supportsLiquidGlass: true, blurOverride: false),
            .opaque
        )
        XCTAssertEqual(
            GlassMaterialPolicy.resolve(reduceTransparency: true, supportsLiquidGlass: false, blurOverride: false),
            .opaque
        )
        XCTAssertEqual(
            GlassMaterialPolicy.resolve(reduceTransparency: true, supportsLiquidGlass: true, blurOverride: true),
            .opaque,
            "调试开关也不能越过无障碍要求"
        )
    }

    func testLiquidGlassWhenSupportedAndTransparencyAllowed() {
        XCTAssertEqual(
            GlassMaterialPolicy.resolve(reduceTransparency: false, supportsLiquidGlass: true, blurOverride: false),
            .liquidGlass
        )
    }

    /// macOS 26 以下没有 NSGlassEffectView，必须回退毛玻璃
    func testFallsBackToVibrancyBelowMacOS26() {
        XCTAssertEqual(
            GlassMaterialPolicy.resolve(reduceTransparency: false, supportsLiquidGlass: false, blurOverride: false),
            .vibrancy
        )
    }

    /// 系统 Liquid Glass 的「透明 / 着色」没有公开读取 API，读不到就固定取最透明的一档。
    /// 钉住它，避免以后有人「顺手」改回 `.regular` 而没人知道为什么。
    @available(macOS 26.0, *)
    func testLiquidGlassUsesMostTransparentStyle() {
        XCTAssertEqual(
            GlassStylePolicy.liquidStyle,
            .clear,
            "读不到系统设置时按最透明来（ADR-035）"
        )
    }

    func testBlurOverrideBeatsLiquidGlass() {
        XCTAssertEqual(
            GlassMaterialPolicy.resolve(reduceTransparency: false, supportsLiquidGlass: true, blurOverride: true),
            .vibrancy,
            "A/B 对照用：强制走经典毛玻璃"
        )
    }
}

/// 滚动输入的归一化（PLAN.md §6.5）
final class ScrollDeltaTests: XCTestCase {

    /// 三种输入都要能翻卡：取绝对值大的轴
    func testDominantPicksAxisWithLargerMagnitude() {
        // 普通滚轮 / 双指上下滑
        XCTAssertEqual(ScrollDelta.dominant(deltaX: 0, deltaY: 80), 80)
        XCTAssertEqual(ScrollDelta.dominant(deltaX: 3, deltaY: -80), -80, "垂直明显占优时忽略水平抖动")

        // 双指左右滑 / Shift 转轴（此时只有水平轴有值）
        XCTAssertEqual(ScrollDelta.dominant(deltaX: 120, deltaY: 0), 120)
        XCTAssertEqual(ScrollDelta.dominant(deltaX: -120, deltaY: 0), -120)

        XCTAssertEqual(ScrollDelta.dominant(deltaX: 0, deltaY: 0), 0)
    }

    /// 触控板必须 1:1 跟手，任何缩放都会破坏「丝滑」
    func testPreciseDeltasArePassedThroughUnchanged() {
        XCTAssertEqual(ScrollDelta.contentOffset(for: 2.5, hasPreciseDeltas: true), 2.5)
        XCTAssertEqual(ScrollDelta.contentOffset(for: -37, hasPreciseDeltas: true), -37)
    }

    /// 机械滚轮的 delta 是**行数**不是像素，必须乘行高换算，
    /// 否则一格只走零点几个点，表现为「滚轮几乎没反应」
    func testMouseWheelDeltasAreConvertedFromLines() {
        XCTAssertEqual(
            ScrollDelta.contentOffset(for: 1, hasPreciseDeltas: false),
            ScrollDelta.pointsPerLine,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScrollDelta.contentOffset(for: -1, hasPreciseDeltas: false),
            -ScrollDelta.pointsPerLine,
            accuracy: 0.001
        )
    }

    /// 不同鼠标一格上报的行数不同（1 / 3 / 10 都有），必须封顶
    func testMouseWheelStepIsCapped() {
        XCTAssertEqual(
            ScrollDelta.contentOffset(for: 10, hasPreciseDeltas: false),
            ScrollDelta.maxWheelStep,
            accuracy: 0.001,
            "一格上报 10 行时不能一下跳掉两张卡"
        )
        XCTAssertEqual(
            ScrollDelta.contentOffset(for: -99, hasPreciseDeltas: false),
            -ScrollDelta.maxWheelStep,
            accuracy: 0.001
        )
    }

    func testZeroDeltaProducesNoMovement() {
        XCTAssertEqual(ScrollDelta.contentOffset(for: 0, hasPreciseDeltas: false), 0)
        XCTAssertEqual(ScrollDelta.contentOffset(for: 0, hasPreciseDeltas: true), 0)
    }

    /// 方向语义（ADR-024）：NSEvent 约定「+ = 回退」，预览带取反后
    /// 「下滚 / 左滑 = 前进（露出后面的卡片）」。系统已按「自然滚动」设置
    /// 翻转过符号，所以取反即自动跟随系统设置。
    func testStripOffsetInvertsNSEventSign() {
        // 机械滚轮向下滚一格 = deltaY -1 行 → 预览带前进（正位移）
        XCTAssertEqual(
            ScrollDelta.stripOffset(deltaX: 0, deltaY: -1, hasPreciseDeltas: false),
            ScrollDelta.pointsPerLine,
            accuracy: 0.001
        )
        // 触控板双指上滑（自然滚动下 = 内容上移 = 前进）→ 正位移，且 1:1
        XCTAssertEqual(ScrollDelta.stripOffset(deltaX: 0, deltaY: -10, hasPreciseDeltas: true), 10, accuracy: 0.001)
        // 双指左滑（露出右边 = 前进）= 水平负 delta → 正位移
        XCTAssertEqual(ScrollDelta.stripOffset(deltaX: -120, deltaY: 0, hasPreciseDeltas: true), 120, accuracy: 0.001)
        // 反向：上滚 / 右滑 → 负位移
        XCTAssertEqual(ScrollDelta.stripOffset(deltaX: 0, deltaY: 5, hasPreciseDeltas: true), -5, accuracy: 0.001)
        // 全零不动
        XCTAssertEqual(ScrollDelta.stripOffset(deltaX: 0, deltaY: 0, hasPreciseDeltas: true), 0)
    }
}

/// 可视区滚动（PLAN.md §6.5）
@MainActor
final class PanelSelectionTests: XCTestCase {

    private func makeSelection() -> PanelSelection {
        PanelSelection(visibleCount: 4, cardStride: 188)
    }

    func testNoOverflowMeansNoMovement() {
        let selection = makeSelection()
        selection.scroll(by: 400, totalCount: 3)

        XCTAssertEqual(selection.maxOffset, 0)
        XCTAssertEqual(selection.offset, 0)
    }

    /// 不做吸附：滚到哪里就停在哪里，允许停在半张卡中间
    func testScrollStopsExactlyWhereItLands() {
        let selection = makeSelection()
        let midway: CGFloat = 188 * 2 + 60
        selection.scroll(by: midway, totalCount: 10)
        selection.settleImmediately()

        XCTAssertEqual(selection.offset, midway, accuracy: 0.01, "不能被吸附拉回卡片边界")
        XCTAssertEqual(selection.firstVisibleIndex, 2, "2.3 张处可见区从第 2 张开始")
        XCTAssertEqual(selection.visibleRange, 2..<6)
    }

    func testScrollClampsAtBothEnds() {
        let selection = makeSelection()

        selection.scroll(by: -500, totalCount: 10)
        selection.settleImmediately()
        XCTAssertEqual(selection.offset, 0, "不能滚到负数")

        selection.scroll(by: 99999, totalCount: 10)
        selection.settleImmediately()
        XCTAssertEqual(selection.offset, 188 * 6, accuracy: 0.01, "最多滚到 totalCount - visibleCount")
        XCTAssertEqual(selection.firstVisibleIndex, 6)
    }

    func testStepMovesExactlyOneCard() {
        let selection = makeSelection()
        selection.step(1, totalCount: 10)
        selection.settleImmediately()

        XCTAssertEqual(selection.offset, 188, accuracy: 0.01)
        XCTAssertEqual(selection.firstVisibleIndex, 1)
    }

    func testUpdateClampsAfterWindowsDisappear() {
        let selection = makeSelection()
        selection.scroll(by: 188 * 6, totalCount: 10)
        selection.settleImmediately()
        XCTAssertEqual(selection.firstVisibleIndex, 6)

        selection.update(totalCount: 4)

        XCTAssertEqual(selection.maxOffset, 0)
        XCTAssertEqual(selection.offset, 0)
    }

    func testResetReturnsToStart() {
        let selection = makeSelection()
        selection.scroll(by: 188 * 3, totalCount: 10)
        selection.settleImmediately()

        selection.reset()

        XCTAssertEqual(selection.offset, 0)
        XCTAssertEqual(selection.firstVisibleIndex, 0)
    }
}
