import SwiftUI

/// 调试面板：实时显示屏幕几何与面板状态。
///
/// 这是 M0 的核心验收工具——调试面板输出的刘海矩形必须与 `PLAN.md` §3 的实测值一致。
struct DebugPanelView: View {

    let textProvider: () -> String

    @State private var text: String = ""

    private let ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }

            Divider()

            HStack {
                Text("每秒刷新一次 · 用于核对  PLAN.md §3 实测数据")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 620, minHeight: 460)
        .tint(Kimi.accent)
        .onAppear { text = textProvider() }
        .onReceive(ticker) { _ in text = textProvider() }
    }
}
