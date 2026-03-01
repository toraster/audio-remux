import SwiftUI

/// エクスポート設定ビュー
struct ExportSettingsView: View {
    @Binding var settings: ExportSettings

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

            // 出力フォーマット選択
            VStack(alignment: .leading, spacing: 6) {
                Text("出力フォーマット")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Picker("フォーマット", selection: $settings.outputContainer) {
                    ForEach(OutputContainer.allCases) { container in
                        Text(container.displayName).tag(container)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.outputContainer) { _ in
                    settings.adjustCodecForContainer()
                }

                Text(settings.outputContainer.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 2)
            }

            // 音声コーデック選択
            VStack(alignment: .leading, spacing: 6) {
                Text("音声コーデック")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Picker("コーデック", selection: $settings.audioCodec) {
                    ForEach(settings.outputContainer.supportedAudioCodecs) { codec in
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

            // ビットレート選択（AAC選択時のみ表示）
            if settings.audioCodec.requiresBitrate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ビットレート")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Picker("ビットレート", selection: $settings.audioBitrate) {
                        ForEach(AudioBitrate.allCases) { bitrate in
                            Text(bitrate.displayName).tag(bitrate)
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
                }
            }

            // ファイル名サフィックス設定
            VStack(alignment: .leading, spacing: 6) {
                Text("ファイル名サフィックス")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("_replaced", text: $settings.outputSuffix)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                    )

                Text("出力例: input\(settings.effectiveSuffix).\(settings.outputContainer.fileExtension)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
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
}

#Preview {
    ExportSettingsView(settings: .constant(ExportSettings()))
        .padding()
        .frame(width: 500)
}
