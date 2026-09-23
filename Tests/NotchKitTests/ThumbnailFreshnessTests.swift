import XCTest
@testable import NotchKit

/// 缩略图新鲜度决策（`ThumbnailStore.needsCapture`，ADR-043）。
///
/// 规则：没抓过 → 抓；抓过但超过 `staleInterval` → 重抓
/// （否则卡片永远停在旧帧）；刚抓过 → 不抓（面板快速开关不反复抓）。
final class ThumbnailFreshnessTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func decide(hasImage: Bool, age: TimeInterval?, stale: TimeInterval) -> Bool {
        ThumbnailStore.needsCapture(
            hasImage: hasImage,
            capturedAt: age.map { now.addingTimeInterval(-$0) },
            now: now,
            staleInterval: stale
        )
    }

    /// 没抓过 → 必须抓
    func testMissingImageCaptures() {
        XCTAssertTrue(decide(hasImage: false, age: nil, stale: 10))
    }

    /// 新鲜缓存 → 不抓
    func testFreshImageSkipsCapture() {
        XCTAssertFalse(decide(hasImage: true, age: 3, stale: 10))
    }

    /// 过期缓存 → 重抓（核心回归：旧逻辑下缓存图永不更新）
    func testStaleImageRecaptures() {
        XCTAssertTrue(decide(hasImage: true, age: 30, stale: 10))
    }

    /// 恰好到期的边界
    func testBoundaryIsStale() {
        XCTAssertTrue(decide(hasImage: true, age: 10, stale: 10))
        XCTAssertFalse(decide(hasImage: true, age: 9.999, stale: 10))
    }

    /// 有图但没有时间记录（理论上不应出现）→ 按需重抓兜底
    func testMissingTimestampCaptures() {
        XCTAssertTrue(decide(hasImage: true, age: nil, stale: 10))
    }

    /// TTL = 0 → 全量重抓
    func testZeroIntervalAlwaysRecaptures() {
        XCTAssertTrue(decide(hasImage: true, age: 0, stale: 0))
    }
}
