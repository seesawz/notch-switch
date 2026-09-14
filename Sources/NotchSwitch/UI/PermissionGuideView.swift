import NotchKit
import SwiftUI

/// 权限引导窗口（Kimi 风格：卡片式分区 + 状态胶囊 + 品牌色点缀）。
struct PermissionGuideView: View {

    @ObservedObject var permissions: PermissionsModel
    /// 重启 App（授权后需要重启让 AX 信任状态生效）
    var onRelaunch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let warning = environmentWarning {
                banner(warning, icon: "exclamationmark.triangle.fill", color: .orange)
                    .padding(.bottom, 14)
            }

            VStack(spacing: 10) {
                permissionRow(
                    icon: "accessibility",
                    title: "辅助功能",
                    detail: "枚举窗口、记录最近使用顺序、把窗口切到前台。缺失时核心功能不可用。",
                    granted: permissions.accessibilityGranted,
                    request: { permissions.requestAccessibility() },
                    openSettings: { permissions.openAccessibilitySettings() }
                )

                permissionRow(
                    icon: "video",
                    title: "屏幕录制",
                    detail: "捕获窗口缩略图与标题。缺失时降级为应用图标 + 应用名。",
                    granted: permissions.screenRecordingGranted,
                    request: { permissions.requestScreenRecording() },
                    openSettings: { permissions.openScreenRecordingSettings() }
                )
            }

            if permissions.needsRelaunch {
                banner("已授权：需要重启 NotchSwitch 才会完全生效。",
                       icon: "arrow.triangle.2.circlepath",
                       color: .orange)
                    .padding(.top, 12)
            }

            footer
        }
        .padding(24)
        .frame(width: 480)
        .tint(Kimi.accent)
    }

    // MARK: - 分区

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("NotchSwitch 需要两项系统权限")
                .font(.system(size: 16, weight: .bold))
            Text("两项都拿到之后，本窗口会自动显示为「已授权」。授权状态每 2 秒自动重新检测，不需要手动刷新。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 18)
    }

    /// 运行位置警告：TCC 与路径绑定，位置不对会导致「开关开着但仍未授权」
    private var environmentWarning: String? {
        guard permissions.isAppBundle else {
            return "当前不是以 .app 包运行（\(permissions.bundlePath)）。这种方式下系统不会正确记住授权，请改用 build/NotchSwitch.app 运行。"
        }
        guard !permissions.isInApplicationsFolder else { return nil }
        return "当前运行位置：\(permissions.bundlePath)\n建议把 NotchSwitch.app 拖到「应用程序」文件夹后再授权——系统设置里更容易找到它，也不会因重新构建而失配。"
    }

    /// 橙色提示条（运行位置警告 / 需要重启）
    private func banner(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusPill(granted: Bool) -> some View {
        Text(granted ? "已授权" : "未授权")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(granted ? Color.green : Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill((granted ? Color.green : Color.orange).opacity(0.12)))
    }

    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        granted: Bool,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // 图标底：已授权 = 绿色淡底 + 对勾；未授权 = 品牌渐变
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(granted
                        ? AnyShapeStyle(Color.green.opacity(0.15))
                        : AnyShapeStyle(Kimi.accentGradient))
                Image(systemName: granted ? "checkmark" : icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(granted ? AnyShapeStyle(.green) : AnyShapeStyle(.white))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    statusPill(granted: granted)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if !granted {
                VStack(alignment: .trailing, spacing: 6) {
                    Button("申请授权", action: request)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("打开系统设置", action: openSettings)
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("授权后如果一直显示「未授权」：系统设置里把 NotchSwitch 删掉（选中按 − 号），再重新授权即可。原因通常是应用签名变了，旧记录对不上号。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()
                Button("重启 NotchSwitch", action: onRelaunch)
                    .buttonStyle(.borderedProminent)
                    .disabled(!permissions.needsRelaunch)
            }
        }
    }
}
