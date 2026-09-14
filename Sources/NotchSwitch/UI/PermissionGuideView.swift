import NotchKit
import SwiftUI

/// 权限引导窗口。
struct PermissionGuideView: View {

    @ObservedObject var permissions: PermissionsModel
    /// 重启 App（授权后需要重启让 AX 信任状态生效）
    var onRelaunch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let warning = environmentWarning {
                warningBanner(warning)
            }

            permissionRow(
                title: "辅助功能",
                detail: "枚举窗口、记录最近使用顺序、把窗口切到前台。缺失时核心功能不可用。",
                granted: permissions.accessibilityGranted,
                request: { permissions.requestAccessibility() },
                openSettings: { permissions.openAccessibilitySettings() }
            )

            Divider().padding(.vertical, 12)

            permissionRow(
                title: "屏幕录制",
                detail: "捕获窗口缩略图与标题。缺失时降级为应用图标 + 应用名。",
                granted: permissions.screenRecordingGranted,
                request: { permissions.requestScreenRecording() },
                openSettings: { permissions.openScreenRecordingSettings() }
            )

            if permissions.needsRelaunch {
                Text("已授权：需要重启 NotchSwitch 才会完全生效。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.top, 12)
            }

            Divider().padding(.vertical, 12)

            footer
        }
        .padding(20)
        .frame(width: 480)
    }

    // MARK: - 分区

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NotchSwitch 需要两项系统权限")
                .font(.system(size: 15, weight: .semibold))
            Text("两项都拿到之后，本窗口会自动显示为「已授权」。授权状态每 2 秒自动重新检测，不需要手动刷新。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 16)
    }

    /// 运行位置警告：TCC 与路径绑定，位置不对会导致「开关开着但仍未授权」
    private var environmentWarning: String? {
        guard permissions.isAppBundle else {
            return "当前不是以 .app 包运行（\(permissions.bundlePath)）。这种方式下系统不会正确记住授权，请改用 build/NotchSwitch.app 运行。"
        }
        guard !permissions.isInApplicationsFolder else { return nil }
        return "当前运行位置：\(permissions.bundlePath)\n建议把 NotchSwitch.app 拖到「应用程序」文件夹后再授权——系统设置里更容易找到它，也不会因重新构建而失配。"
    }

    private func warningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.bottom, 14)
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(granted ? Color.green : Color.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(granted ? "已授权" : "未授权")
                    .font(.system(size: 11))
                    .foregroundStyle(granted ? .green : .secondary)

                Spacer()

                if !granted {
                    Button("申请授权", action: request)
                    Button("打开系统设置", action: openSettings)
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("授权后如果一直显示「未授权」：系统设置里把 NotchSwitch 删掉（选中按 − 号），再重新授权即可。原因通常是应用签名变了，旧记录对不上号。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()
                Button("重启 NotchSwitch", action: onRelaunch)
                    .disabled(!permissions.needsRelaunch)
            }
        }
    }
}
