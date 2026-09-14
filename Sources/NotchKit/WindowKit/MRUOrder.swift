import CoreGraphics

/// 最近使用顺序（MRU）的纯逻辑部分。
///
/// 刻意抽成不依赖 AppKit / AX 的值类型，这样排序规则可以被单元测试直接覆盖
/// （PLAN.md §4.3：macOS 没有公开 MRU API，只能自建，所以这段逻辑必须可靠）。
public struct MRUOrder {

    /// index 0 = 最近使用
    private(set) var order: [CGWindowID] = []

    public init() {}

    /// 某个窗口刚被聚焦 → 提到最前
    public mutating func touch(_ windowID: CGWindowID) {
        order.removeAll { $0 == windowID }
        order.insert(windowID, at: 0)
    }

    public mutating func remove(_ windowID: CGWindowID) {
        order.removeAll { $0 == windowID }
    }

    /// 清掉已经不存在的窗口，避免列表无限增长
    public mutating func prune(keeping valid: Set<CGWindowID>) {
        order.removeAll { !valid.contains($0) }
    }

    /// 从未见过的窗口（如冷启动时从 CGWindowList 拿到的）按给定顺序并入队尾
    public mutating func seedUnknown(_ windowIDs: [CGWindowID]) {
        let known = Set(order)
        for id in windowIDs where !known.contains(id) {
            order.append(id)
        }
    }

    /// 排名，越小越靠前；未记录过的排到最后
    public func rank(of windowID: CGWindowID) -> Int {
        order.firstIndex(of: windowID) ?? Int.max
    }

    /// 按 MRU 排序（未记录的按 fallback 顺序）
    public func sorted<T>(_ items: [T], id: (T) -> CGWindowID) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                let lr = rank(of: id(lhs.element))
                let rr = rank(of: id(rhs.element))
                if lr != rr { return lr < rr }
                return lhs.offset < rhs.offset   // 都未记录时保持传入顺序
            }
            .map(\.element)
    }
}
