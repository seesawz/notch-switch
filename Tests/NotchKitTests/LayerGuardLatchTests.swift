import XCTest
@testable import NotchKit

/// 全屏闩锁决策（`LayerGuard.latchTransition`）。
///
/// 背景：稳态全屏下 AX/形状检测都会漏判（实测，见 LayerGuard 类头注释），
/// 只有 Space 切换瞬间的检测可靠。闩锁规则的单测逐条钉住：
/// 看门狗的 miss 永不解闩；space 变化的 miss 在宽限期内不解闩；
/// 超过宽限期的 space 变化 miss/命中都安排复核。
final class LayerGuardLatchTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_000_000)
    private let grace: TimeInterval = 2.0

    /// setAtAgo = 闩置位于几秒前；nowAgo = 现在距置位又过了几秒（age = nowAgo）
    private func decide(
        latched: Bool,
        setAtAgo: TimeInterval?,
        nowAgo: TimeInterval = 0,
        detected: Bool,
        isSpaceChange: Bool
    ) -> (latched: Bool, action: LayerGuard.LatchAction) {
        let setAt = setAtAgo.map { epoch.addingTimeInterval(-$0) } ?? epoch
        let now = setAt.addingTimeInterval(nowAgo)
        return LayerGuard.latchTransition(
            wasLatched: latched,
            latchSetAt: setAt,
            now: now,
            detected: detected,
            isSpaceChange: isSpaceChange,
            echoGraceInterval: grace
        )
    }

    /// 检测命中（任意评估）→ 置闩
    func testEnterLatches() {
        let r = decide(latched: false, setAtAgo: nil, detected: true, isSpaceChange: true)
        XCTAssertTrue(r.latched)
        XCTAssertEqual(r.action, .cancelVerify)
    }

    /// ★ 核心回归：全屏稳态下看门狗的 miss **不解闩**（旧 bug 的根源）
    func testSteadyWatchdogMissKeepsLatch() {
        let r = decide(latched: true, setAtAgo: 30, detected: false, isSpaceChange: false)
        XCTAssertTrue(r.latched)
        XCTAssertEqual(r.action, .keep)
    }

    /// 进入动画的第二发 space 通知（宽限期内 miss）→ 不解闩、取消复核
    func testEnterEchoMissWithinGraceKeepsLatch() {
        let r = decide(latched: true, setAtAgo: 1.2, nowAgo: 1.2, detected: false, isSpaceChange: true)
        XCTAssertTrue(r.latched)
        XCTAssertEqual(r.action, .cancelVerify)
    }

    /// 全屏稳态下发生 space 变化且 miss（宽限期外）→ 安排复核
    func testSpaceChangeMissAfterGraceSchedulesVerify() {
        let r = decide(latched: true, setAtAgo: 30, nowAgo: 29.5, detected: false, isSpaceChange: true)
        XCTAssertTrue(r.latched)
        XCTAssertEqual(r.action, .scheduleVerify)
    }

    /// 全屏稳态下 space 变化且检测仍为真（疑似退出动画）→ 安排复核
    func testSpaceChangeHitAfterGraceSchedulesVerify() {
        let r = decide(latched: true, setAtAgo: 30, nowAgo: 29.5, detected: true, isSpaceChange: true)
        XCTAssertTrue(r.latched)
        XCTAssertEqual(r.action, .scheduleVerify)
    }

    /// 正常桌面下未闩 + miss → 保持未闩
    func testNormalDesktopStaysUnlatched() {
        let r = decide(latched: false, setAtAgo: nil, detected: false, isSpaceChange: true)
        XCTAssertFalse(r.latched)
        XCTAssertEqual(r.action, .keep)
    }

    /// 置闩后 2s 内快速进出全屏：miss 被宽限，闩保持（已知边界：需等下次 space 变化解闩）
    func testQuickEnterExitWithinGraceKeepsLatch() {
        let r = decide(latched: true, setAtAgo: 1.0, nowAgo: 1.0, detected: false, isSpaceChange: true)
        XCTAssertTrue(r.latched)
        XCTAssertEqual(r.action, .cancelVerify)
    }

    /// 全屏稳态下的非 space 命中（如复核刚好处在动画尾巴上）→ 保持闩、取消复核
    func testSteadyHitKeepsLatchAndCancelsVerify() {
        let r = decide(latched: true, setAtAgo: 30, detected: true, isSpaceChange: false)
        XCTAssertTrue(r.latched)
        XCTAssertEqual(r.action, .cancelVerify)
    }
}
