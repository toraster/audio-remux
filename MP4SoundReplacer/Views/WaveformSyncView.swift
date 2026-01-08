import SwiftUI

/// 波形同期調整ビュー
struct WaveformSyncView: View {
    @ObservedObject var syncViewModel: SyncAnalyzerViewModel
    @Binding var offsetSeconds: Double
    let videoURL: URL?
    let audioURL: URL?
    let onOffsetChanged: (Double) -> Void
    let onResetOffset: () -> Void

    @State private var isExpanded = true

    /// ズームレベル（1.0 = 全体表示、100.0 = 最大ズーム）
    @State private var zoomLevel: Double = 1.0

    /// 表示開始位置（秒）
    @State private var scrollPosition: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ヘッダー
            headerView

            if isExpanded {
                // ズームコントロール
                zoomControlSection
                    .padding(.horizontal, 4)

                // 波形表示エリア
                waveformSection
                    .padding(.vertical, 8)

                // 区切り線
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 4)

                // 同期コントロール
                syncControlSection
                    .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("音声同期")
                    .font(.system(size: 18, weight: .bold))
            }

            Spacer()

            // 状態インジケーター
            if syncViewModel.syncState.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(syncViewModel.syncState.statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.08))
                )
            }

            // 展開/折りたたみボタン
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                ZStack {
                    Circle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 30, height: 30)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
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
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

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
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(width: 70)

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
                offsetSeconds: .constant(0),
                maxDuration: maxDuration
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
                offsetSeconds: $offsetSeconds,
                maxDuration: maxDuration
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
            HStack(spacing: 12) {
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
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                        Text("自動同期")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(videoURL == nil || audioURL == nil || syncViewModel.syncState.isProcessing)
                .opacity((videoURL == nil || audioURL == nil || syncViewModel.syncState.isProcessing) ? 0.5 : 1.0)

                // オフセットリセットボタン
                Button(action: {
                    withAnimation {
                        onResetOffset()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("オフセットをリセット")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(offsetSeconds == 0)
                .opacity(offsetSeconds == 0 ? 0.5 : 1.0)

                Spacer()

                // 結果表示
                if let result = syncViewModel.lastResult {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("検出: \(String(format: "%.3f", result.detectedOffset))秒")
                            .font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 4) {
                            Circle()
                                .fill(confidenceColor(result.confidenceLevel))
                                .frame(width: 6, height: 6)
                            Text(result.confidenceLevel.description)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(confidenceColor(result.confidenceLevel))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(confidenceColor(result.confidenceLevel).opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(confidenceColor(result.confidenceLevel).opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }

            // 操作ヒント
            if syncViewModel.videoWaveform != nil && syncViewModel.audioWaveform != nil {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.yellow)
                    Text("マウスホイールでズーム、Shift+ホイールまたは横スワイプでスクロール、緑の波形をドラッグしてオフセット調整")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.08))
                )
            }

            // エラー表示
            if case .error(let message) = syncViewModel.syncState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
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
        onOffsetChanged: { _ in },
        onResetOffset: { }
    )
    .padding()
    .frame(width: 600)
}
