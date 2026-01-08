import SwiftUI

/// エクスポート設定ビュー
struct ExportSettingsView: View {
    @Binding var settings: ExportSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("出力設定")
                .font(.headline)

            // 音声コーデック選択
            VStack(alignment: .leading, spacing: 8) {
                Text("音声コーデック")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("コーデック", selection: $settings.audioCodec) {
                    ForEach(AudioCodec.allCases) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Text(settings.audioCodec.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // オフセット設定
            VStack(alignment: .leading, spacing: 8) {
                Text("音声オフセット")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // オフセット値表示（大きく中央に）
                HStack {
                    Text(String(format: "%+.3f", settings.offsetSeconds))
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                    Text("秒")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )

                // 微調整ボタン（横並び）
                HStack(spacing: 4) {
                    Button("-0.1") { settings.offsetSeconds -= 0.1 }
                    Button("-0.01") { settings.offsetSeconds -= 0.01 }
                    Button("+0.01") { settings.offsetSeconds += 0.01 }
                    Button("+0.1") { settings.offsetSeconds += 0.1 }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("リセット") { settings.offsetSeconds = 0 }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Text(offsetDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
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
