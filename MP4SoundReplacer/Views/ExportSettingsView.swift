import SwiftUI

/// エクスポート設定ビュー
struct ExportSettingsView: View {
    @Binding var settings: ExportSettings

    /// オフセット値のテキストバインディング
    private var offsetBinding: Binding<String> {
        Binding(
            get: { String(format: "%.3f", settings.offsetSeconds) },
            set: { newValue in
                if let value = Double(newValue) {
                    settings.offsetSeconds = value
                }
            }
        )
    }

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

                HStack {
                    TextField("0.000", text: offsetBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)

                    Text("秒")

                    Spacer()

                    // 微調整ボタン
                    HStack(spacing: 4) {
                        Button("-0.1") {
                            settings.offsetSeconds -= 0.1
                        }
                        .buttonStyle(.bordered)

                        Button("-0.01") {
                            settings.offsetSeconds -= 0.01
                        }
                        .buttonStyle(.bordered)

                        Button("+0.01") {
                            settings.offsetSeconds += 0.01
                        }
                        .buttonStyle(.bordered)

                        Button("+0.1") {
                            settings.offsetSeconds += 0.1
                        }
                        .buttonStyle(.bordered)

                        Button("リセット") {
                            settings.offsetSeconds = 0
                        }
                        .buttonStyle(.bordered)
                    }
                }

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
