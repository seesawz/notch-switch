import Darwin

/// 进程内存占用的唯一读数口。
///
/// 为什么用 `phys_footprint` 而不是 RSS：RSS 包含大量与其他进程**共享**的
/// 框架只读页（SwiftUI / AppKit / ScreenCaptureKit 的代码与资源），会虚高
/// （本机实测 RSS ≈ 80MB、footprint ≈ 26MB）；活动监视器「内存」列、
/// Jetsam 决策用的都是 footprint 口径。优化内存就该盯它。
public enum MemoryInfo {

    /// 当前进程的物理占用（字节）。读不到（task_info 失败）返回 nil。
    public static func physicalFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    /// 当前占用，格式化成「XX.X MB」。读不到返回「未知」。
    public static func physicalFootprintDescription() -> String {
        guard let bytes = physicalFootprintBytes() else { return "未知" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
