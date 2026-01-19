import SwiftUI

/// 波形同期調整ビュー
struct WaveformSyncView: View {
    @ObservedObject var syncViewModel: SyncAnalyzerViewModel
    @Binding var offsetSeconds: Double
    let videoURL: URL?
    let audioURL: URL?
    let onOffsetChanged: (Double) -> Void
    let onResetOffset: () -> Void

    /// 音声再生サービス
    @StateObject private var playbackService = AudioPlaybackService()

    /// ズームレベル（1.0 = 全体表示、200.0 = 最大ズーム）
    @State private var zoomLevel: Double = 1.0

    /// 表示開始位置（秒）
    @State private var scrollPosition: Double = 0

    /// カーソル位置（秒）
    @State private var cursorPosition: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ヘッダー
            headerView

            // ズームコントロール
            zoomControlSection
                .padding(.horizontal, 2)

            // 波形表示エリア
            waveformSection
                .background(
                    // キーボードナビゲーション（Home/Endキー対応、フォーカス不要）
                    KeyboardNavigationView(
                        onHome: { scrollPosition = 0 },
                        onEnd: { scrollPosition = maxScrollPosition }
                    )
                )

            // 再生コントロール
            PlaybackControlView(
                playbackService: playbackService,
                isEnabled: syncViewModel.extractedVideoAudioURL != nil
            )
            .padding(.horizontal, 2)

            // 区切り線
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 2)

            // 同期コントロール
            syncControlSection
                .padding(.horizontal, 2)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        )
        // 一時ファイルURLが変更されたら再生サービスを更新
        .onChange(of: syncViewModel.extractedVideoAudioURL) { url in
            playbackService.originalAudioURL = url
        }
        .onChange(of: syncViewModel.extractedReplacementAudioURL) { url in
            playbackService.replacementAudioURL = url
        }
        // オフセットが変更されたら再生サービスに反映
        .onChange(of: offsetSeconds) { newValue in
            playbackService.offsetSeconds = newValue
        }
        // 再生位置が変更されたらカーソル位置を更新
        .onChange(of: playbackService.currentTime) { time in
            if playbackService.isPlaying {
                cursorPosition = time
            }
        }
        // カーソル位置が変更されたら再生位置を更新（再生中でない場合）
        .onChange(of: cursorPosition) { position in
            if let position = position, !playbackService.isPlaying {
                playbackService.seek(to: position)
            }
        }
        .onDisappear {
            playbackService.cleanup()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("音声同期")
                    .font(.system(size: 14, weight: .bold))
            }

            Spacer()

            // 状態インジケーター
            if syncViewModel.syncState.isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(syncViewModel.syncState.statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.08))
                )
            }

        }
    }

    // MARK: - Zoom Control Section

    private var zoomControlSection: some View {
        HStack(spacing: 8) {
            // ズームスライダー（カーソル位置基準）
            HStack(spacing: 3) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))

                Slider(value: Binding(
                    get: { zoomLevel },
                    set: { newZoom in
                        setZoomWithAnchor(newZoom)
                    }
                ), in: 1...200) { _ in }
                    .frame(width: 120)

                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 10))
            }

            Text("\(Int(zoomLevel))x")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            Spacer()

            // スクロール位置（ズーム中のみ表示）
            if zoomLevel > 1 {
                HStack(spacing: 3) {
                    Button(action: { scrollPosition = max(0, scrollPosition - scrollStep) }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(scrollPosition <= 0)

                    Text(formatTime(scrollPosition))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 60)

                    Button(action: { scrollPosition = min(maxScrollPosition, scrollPosition + scrollStep) }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(scrollPosition >= maxScrollPosition)
                }
            }

            // ズームリセットボタン
            Button(action: {
                zoomLevel = 1.0
                scrollPosition = 0
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(zoomLevel == 1.0 && scrollPosition == 0)
            .help("ズームをリセット")
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

    /// カーソル位置またはビュー中央を基準にズームを設定
    private func setZoomWithAnchor(_ newZoom: Double) {
        let effectiveDuration = maxDuration
        let oldVisibleDuration = effectiveDuration / zoomLevel
        let newVisibleDuration = effectiveDuration / newZoom

        // カーソル位置、またはビュー中央を基準点とする
        let anchorTime: Double
        let anchorRatio: Double
        if let cursor = cursorPosition {
            anchorTime = cursor
            anchorRatio = (anchorTime - scrollPosition) / oldVisibleDuration
        } else {
            anchorTime = scrollPosition + oldVisibleDuration / 2
            anchorRatio = 0.5
        }

        // 基準点が同じ相対位置に留まるよう調整
        let newScrollPosition = anchorTime - (anchorRatio * newVisibleDuration)
        let maxScroll = max(0, effectiveDuration - newVisibleDuration)

        zoomLevel = newZoom
        scrollPosition = max(0, min(maxScroll, newScrollPosition))
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        VStack(spacing: 6) {
            // 元動画の音声波形
            ZoomableWaveformView(
                waveform: syncViewModel.videoWaveform,
                color: .blue,
                label: "元動画の音声",
                duration: maxDuration,
                zoomLevel: $zoomLevel,
                scrollPosition: $scrollPosition,
                isDraggable: false,
                offsetSeconds: .constant(0),
                maxDuration: maxDuration,
                cursorPosition: $cursorPosition
            )

            // 置換音声波形（ドラッグ可能）
            ZoomableWaveformView(
                waveform: syncViewModel.audioWaveform,
                color: .green,
                label: "置換音声（ドラッグで調整可能）",
                duration: maxDuration,
                zoomLevel: $zoomLevel,
                scrollPosition: $scrollPosition,
                isDraggable: true,
                offsetSeconds: $offsetSeconds,
                maxDuration: maxDuration,
                cursorPosition: $cursorPosition
            )
            .onChange(of: offsetSeconds) { newValue in
                onOffsetChanged(newValue)
            }
        }
    }

    // MARK: - Sync Control Section

    private var syncControlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 自動同期ボタン
            HStack(spacing: 8) {
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
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                        Text("自動同期")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
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
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("オフセットをリセット")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
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
                .disabled(offsetSeconds == 0)
                .opacity(offsetSeconds == 0 ? 0.5 : 1.0)

                Spacer()

                // 結果表示
                if let result = syncViewModel.lastResult {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("検出: \(String(format: "%.3f", result.detectedOffset))秒")
                            .font(.system(size: 12, weight: .semibold))
                        HStack(spacing: 3) {
                            Circle()
                                .fill(confidenceColor(result.confidenceLevel))
                                .frame(width: 5, height: 5)
                            Text(result.confidenceLevel.description)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(confidenceColor(result.confidenceLevel))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(confidenceColor(result.confidenceLevel).opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(confidenceColor(result.confidenceLevel).opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }

            // 操作ヒント
            if syncViewModel.videoWaveform != nil && syncViewModel.audioWaveform != nil {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text("ホイールでズーム、Shift+ホイールでスクロール、Home/Endで先頭/末尾、緑の波形をドラッグで調整")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.08))
                )
            }

            // エラー表示
            if case .error(let message) = syncViewModel.syncState {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
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
