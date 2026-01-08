import SwiftUI

/// エクスポート設定ビュー
struct ExportSettingsView: View {
    @Binding var settings: ExportSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ヘッダー
            HStack(spacing: 8) {
                Image(systemName: "gear.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("出力設定")
                    .font(.system(size: 18, weight: .bold))
            }

            // 音声コーデック選択
            VStack(alignment: .leading, spacing: 12) {
                Text("音声コーデック")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Picker("コーデック", selection: $settings.audioCodec) {
                    ForEach(AudioCodec.allCases) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                )

                Text(settings.audioCodec.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            // 区切り線
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)

            // オフセット設定
            VStack(alignment: .leading, spacing: 12) {
                Text("音声オフセット")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                // オフセット値表示（大きく中央に）
                HStack(spacing: 4) {
                    Spacer()
                    Text(String(format: "%+.3f", settings.offsetSeconds))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .primary.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("秒")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(NSColor.textBackgroundColor),
                                    Color(NSColor.textBackgroundColor).opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                )

                // 微調整ボタン（横並び）
                HStack(spacing: 6) {
                    offsetButton("-0.1", value: -0.1)
                    offsetButton("-0.01", value: -0.01)
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
                            .font(.system(size: 11, weight: .semibold))
                        Text("リセット")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                // 説明文
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text(offsetDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }

    private func offsetButton(_ label: String, value: Double) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                settings.offsetSeconds += value
            }
        }) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
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
