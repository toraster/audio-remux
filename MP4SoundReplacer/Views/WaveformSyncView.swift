import SwiftUI

/// 波形同期調整ビュー
struct WaveformSyncView: View {
    @ObservedObject var syncViewModel: SyncAnalyzerViewModel
    @Binding var offsetSeconds: Double
    let videoURL: URL?
    let audioURL: URL?
    let onOffsetChanged: (Double) -> Void

    @State private var isExpanded = true

    /// ズームレベル（1.0 = 全体表示、100.0 = 最大ズーム）
    @State private var zoomLevel: Double = 1.0

    /// 表示開始位置（秒）
    @State private var scrollPosition: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            headerView

            if isExpanded {
                // ズームコントロール
                zoomControlSection

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

    // MARK: - Zoom Control Section

    private var zoomControlSection: some View {
        HStack(spacing: 12) {
            // ズームスライダー
            HStack(spacing: 4) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Slider(value: $zoomLevel, in: 1...100) { _ in }
                    .frame(width: 150)

                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Text("\(Int(zoomLevel))x")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .leading)

            Spacer()

            // スクロール位置（ズーム中のみ表示）
            if zoomLevel > 1 {
                HStack(spacing: 4) {
                    Button(action: { scrollPosition = max(0, scrollPosition - scrollStep) }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(scrollPosition <= 0)

                    Text(formatTime(scrollPosition))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60)

                    Button(action: { scrollPosition = min(maxScrollPosition, scrollPosition + scrollStep) }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(scrollPosition >= maxScrollPosition)
                }
            }

            // リセットボタン
            Button("リセット") {
                zoomLevel = 1.0
                scrollPosition = 0
            }
            .buttonStyle(.bordered)
            .disabled(zoomLevel == 1.0 && scrollPosition == 0)
        }
    }

    private var scrollStep: Double {
        let visibleDuration = maxDuration / zoomLevel
        return visibleDuration * 0.25
    }

    private var maxScrollPosition: Double {
        let visibleDuration = maxDuration / zoomLevel
        return max(0, maxDuration - visibleDuration)
    }

    private var maxDuration: Double {
        max(
            syncViewModel.videoWaveform?.duration ?? 0,
            syncViewModel.audioWaveform?.duration ?? 0,
            1.0
        )
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        VStack(spacing: 8) {
            // 元動画の音声波形
            ZoomableWaveformView(
                waveform: syncViewModel.videoWaveform,
                color: .blue,
                label: "元動画の音声",
                duration: syncViewModel.videoWaveform?.duration ?? maxDuration,
                zoomLevel: $zoomLevel,
                scrollPosition: $scrollPosition,
                isDraggable: false,
                offsetSeconds: .constant(0)
            )

            // 置換音声波形（ドラッグ可能）
            ZoomableWaveformView(
                waveform: syncViewModel.audioWaveform,
                color: .green,
                label: "置換音声（ドラッグで調整可能）",
                duration: syncViewModel.audioWaveform?.duration ?? maxDuration,
                zoomLevel: $zoomLevel,
                scrollPosition: $scrollPosition,
                isDraggable: true,
                offsetSeconds: $offsetSeconds
            )
            .onChange(of: offsetSeconds) { newValue in
                onOffsetChanged(newValue)
            }
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

            // 操作ヒント
            if syncViewModel.videoWaveform != nil && syncViewModel.audioWaveform != nil {
                Text("ヒント: マウスホイールでズーム、緑の波形をドラッグしてオフセット調整")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        if minutes > 0 {
            return String(format: "%d:%05.2f", minutes, seconds)
        } else {
            return String(format: "%.2fs", seconds)
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
