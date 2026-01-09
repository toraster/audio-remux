import SwiftUI

/// エクスポート設定ビュー
struct ExportSettingsView: View {
    @Binding var settings: ExportSettings

    /// ドラッグ中の一時オフセット
    @State private var dragOffset: Double = 0
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ヘッダー
            HStack(spacing: 5) {
                Image(systemName: "gear.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("出力設定")
                    .font(.system(size: 14, weight: .bold))
            }

            // 音声コーデック選択
            VStack(alignment: .leading, spacing: 6) {
                Text("音声コーデック")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Picker("コーデック", selection: $settings.audioCodec) {
                    ForEach(AudioCodec.allCases) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                )

                Text(settings.audioCodec.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 2)
            }

            // 区切り線
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)

            // オフセット設定
            VStack(alignment: .leading, spacing: 6) {
                Text("音声オフセット")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                // オフセット値表示（大きく中央に、ドラッグで調整可能）
                HStack(spacing: 3) {
                    Spacer()
                    Text(String(format: "%+.3f", settings.offsetSeconds + dragOffset))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isDragging ? [.accentColor, .accentColor.opacity(0.7)] : [.primary, .primary.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("秒")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    isDragging ? Color.accentColor.opacity(0.1) : Color(NSColor.textBackgroundColor),
                                    isDragging ? Color.accentColor.opacity(0.05) : Color(NSColor.textBackgroundColor).opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isDragging ? Color.accentColor.opacity(0.5) : Color.accentColor.opacity(0.2), lineWidth: isDragging ? 2 : 1)
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
                            settings.offsetSeconds += dragOffset
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

                // 微調整ボタン（横並び）
                HStack(spacing: 4) {
                    offsetButton("-0.1", value: -0.1)
                    offsetButton("-0.01", value: -0.01)
                    offsetButton("-0.001", value: -0.001)
                    offsetButton("+0.001", value: +0.001)
                    offsetButton("+0.01", value: +0.01)
                    offsetButton("+0.1", value: +0.1)
                }

                Button(action: {
                    withAnimation {
                        settings.offsetSeconds = 0
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("リセット")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                // 説明文
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text(offsetDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    private func offsetButton(_ label: String, value: Double) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                settings.offsetSeconds += value
            }
        }) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// オフセットの説明文
    private var offsetDescription: String {
        let offset = settings.offsetSeconds
        if offset > 0 {
            return "音声を \(String(format: "%.3f", offset)) 秒遅らせます"
        } else if offset < 0 {
            return "音声の先頭 \(String(format: "%.3f", -offset)) 秒をカットします"
        } else {
            return "オフセットなし（そのまま差し替え）"
        }
    }
}

#Preview {
    ExportSettingsView(settings: .constant(ExportSettings()))
        .padding()
        .frame(width: 500)
}
