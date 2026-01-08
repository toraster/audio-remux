import SwiftUI

/// 波形同期調整ビュー
struct WaveformSyncView: View {
    @ObservedObject var syncViewModel: SyncAnalyzerViewModel
    @Binding var offsetSeconds: Double
    let videoURL: URL?
    let audioURL: URL?
    let onOffsetChanged: (Double) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            headerView

            if isExpanded {
                // 波形表示エリア
                waveformSection

                Divider()

                // 同期コントロール
                syncControlSection
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("音声同期")
                .font(.headline)

            Spacer()

            // 状態インジケーター
            if syncViewModel.syncState.isProcessing {
                ProgressView()
                    .scaleEffect(0.7)
                Text(syncViewModel.syncState.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: { withAnimation { isExpanded.toggle() } }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        VStack(spacing: 8) {
            // 元動画の音声波形
            WaveformView(
                waveform: syncViewModel.videoWaveform,
                color: .blue,
                label: "元動画の音声"
            )

            // 置換音声波形
            WaveformView(
                waveform: syncViewModel.audioWaveform,
                color: .green,
                label: "置換音声",
                offset: offsetSeconds
            )
        }
    }

    // MARK: - Sync Control Section

    private var syncControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 自動同期ボタン
            HStack {
                Button(action: {
                    Task {
                        guard let videoURL = videoURL, let audioURL = audioURL else { return }

                        // 波形がまだない場合は生成から実行
                        if syncViewModel.videoWaveform == nil || syncViewModel.audioWaveform == nil {
                            await syncViewModel.generateWaveformsAndAnalyze(
                                videoURL: videoURL,
                                audioURL: audioURL
                            )
                        } else {
                            await syncViewModel.analyzeSync()
                        }

                        // 結果をオフセットに適用
                        if let result = syncViewModel.lastResult {
                            offsetSeconds = result.detectedOffset
                            onOffsetChanged(result.detectedOffset)
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "waveform.badge.magnifyingglass")
                        Text("自動同期")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(videoURL == nil || audioURL == nil || syncViewModel.syncState.isProcessing)

                // 波形生成のみ
                Button(action: {
                    Task {
                        guard let videoURL = videoURL, let audioURL = audioURL else { return }
                        await syncViewModel.generateWaveforms(videoURL: videoURL, audioURL: audioURL)
                    }
                }) {
                    HStack {
                        Image(systemName: "waveform")
                        Text("波形を表示")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(videoURL == nil || audioURL == nil || syncViewModel.syncState.isProcessing)

                Spacer()

                // 結果表示
                if let result = syncViewModel.lastResult {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("検出: \(String(format: "%.3f", result.detectedOffset))秒")
                            .font(.caption)
                        Text(result.confidenceLevel.description)
                            .font(.caption2)
                            .foregroundColor(confidenceColor(result.confidenceLevel))
                    }
                }
            }

            // エラー表示
            if case .error(let message) = syncViewModel.syncState {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func confidenceColor(_ level: SyncAnalysisResult.ConfidenceLevel) -> Color {
        switch level {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .red
        }
    }
}

#Preview {
    WaveformSyncView(
        syncViewModel: SyncAnalyzerViewModel(),
        offsetSeconds: .constant(0.0),
        videoURL: nil,
        audioURL: nil,
        onOffsetChanged: { _ in }
    )
    .padding()
    .frame(width: 600)
}
