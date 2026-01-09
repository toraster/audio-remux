import SwiftUI

/// オフセット調整コントロールビュー
struct OffsetControlView: View {
    @Binding var offsetSeconds: Double
    var onReset: () -> Void

    /// ドラッグ中の一時オフセット
    @State private var dragOffset: Double = 0
    @State private var isDragging: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            // ラベル
            Text("オフセット:")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            // オフセット値表示（ドラッグで調整可能）
            HStack(spacing: 2) {
                Text(String(format: "%+.3f", offsetSeconds + dragOffset))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDragging ? [.accentColor, .accentColor.opacity(0.7)] : [.primary, .primary.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("秒")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isDragging ? Color.accentColor.opacity(0.1) : Color(NSColor.textBackgroundColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isDragging ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        // 上ドラッグ = 増加、下ドラッグ = 減少（0.001秒/ピクセル）
                        dragOffset = -Double(value.translation.height) * 0.001
                    }
                    .onEnded { _ in
                        isDragging = false
                        offsetSeconds += dragOffset
                        dragOffset = 0
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help("ドラッグで調整（上:+、下:-）")

            // 微調整ボタン群
            HStack(spacing: 3) {
                offsetButton("-0.1", value: -0.1)
                offsetButton("-0.01", value: -0.01)
                offsetButton("+0.01", value: +0.01)
                offsetButton("+0.1", value: +0.1)
            }

            // リセットリンク
            Button(action: {
                withAnimation {
                    onReset()
                }
            }) {
                Text("リセット")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.link)
            .disabled(offsetSeconds == 0)
            .opacity(offsetSeconds == 0 ? 0.5 : 1.0)

            Spacer()

            // 説明テキスト
            Text(offsetDescription)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }

    private func offsetButton(_ label: String, value: Double) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                offsetSeconds += value
            }
        }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.accentColor.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

    /// オフセットの説明文
    private var offsetDescription: String {
        let offset = offsetSeconds
        if offset > 0 {
            return "音声を \(String(format: "%.3f", offset)) 秒遅らせる"
        } else if offset < 0 {
            return "音声の先頭 \(String(format: "%.3f", -offset)) 秒をカット"
        } else {
            return "オフセットなし"
        }
    }
}

#Preview {
    OffsetControlView(
        offsetSeconds: .constant(0.0),
        onReset: {}
    )
    .padding()
    .frame(width: 700)
}
