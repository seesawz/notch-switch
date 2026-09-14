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

/// 滚动的逐帧跟随与吸附（PLAN.md §6.5）。
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

    func testSnapRoundsToNearestCardBoundary() {
        var follow = ScrollFollow()
        follow.addInput(188 * 2 + 60, maxOffset: 2000)   // 停在 2.3 张的位置
        while follow.advance() {}

        let didSnap = follow.snap(to: 188, maxOffset: 2000)

        XCTAssertTrue(didSnap)
        XCTAssertEqual(follow.target, 188 * 2, "应吸附到最近的第 2 张边界")
    }

    func testSnapDoesNothingWhenAlreadyAligned() {
        var follow = ScrollFollow()
        follow.addInput(188, maxOffset: 2000)
        while follow.advance() {}

        XCTAssertFalse(follow.snap(to: 188, maxOffset: 2000))
    }

    func testSnapRespectsMaximumOffset() {
        var follow = ScrollFollow()
        follow.addInput(1000, maxOffset: 188 * 3)
        while follow.advance() {}

        _ = follow.snap(to: 188, maxOffset: 188 * 3)
        XCTAssertEqual(follow.target, 188 * 3, "吸附不能越过末尾")
    }

    func testAnchorIndex() {
        var follow = ScrollFollow()
        follow.addInput(188 * 2, maxOffset: 2000)
        while follow.advance() {}

        XCTAssertEqual(follow.anchorIndex(stride: 188), 2)
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
}

/// 可视区滚动（PLAN.md §6.5）
@MainActor
final class PanelSelectionTests: XCTestCase {

    private func makeSelection() -> PanelSelection {
        let selection = PanelSelection(visibleCount: 4, cardStride: 188)
        selection.settleDelay = 0   // 测试里同步收敛，不等真实时间
        return selection
    }

    func testNoOverflowMeansNoMovement() {
        let selection = makeSelection()
        selection.scroll(by: 400, totalCount: 3)

        XCTAssertEqual(selection.maxOffset, 0)
        XCTAssertEqual(selection.offset, 0)
    }

    func testScrollMovesAndSnapsToCardBoundary() {
        let selection = makeSelection()
        selection.scroll(by: 188 * 2 + 60, totalCount: 10)
        selection.settleImmediately()

        XCTAssertEqual(selection.offset, 188 * 2, accuracy: 0.01, "松手后应对齐到第 2 张")
        XCTAssertEqual(selection.firstVisibleIndex, 2)
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
