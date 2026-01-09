import SwiftUI

/// メインコンテンツビュー（2カラムレイアウト）
struct ContentView: View {
    @StateObject private var viewModel = ProjectViewModel()
    @StateObject private var syncViewModel = SyncAnalyzerViewModel()

    /// ファイル差し替え確認ダイアログの状態
    @State private var showReplaceConfirmation = false
    @State private var pendingFileAction: (() -> Void)?

    /// 左カラムの幅
    private let leftColumnWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // メインコンテンツ（2カラム）
            HStack(spacing: 0) {
                // 左カラム: コントロールパネル
                leftColumn
                    .frame(width: leftColumnWidth)

                Divider()

                // 右カラム: 波形表示
                rightColumn
                    .frame(maxWidth: .infinity)
            }

            Divider()

            // ステータスバー
            statusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 900, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        // 自動波形表示: 両方のファイルがセットされたら自動的に波形を生成
        .onChange(of: viewModel.project.isReady) { isReady in
            if isReady {
                autoGenerateWaveforms()
            }
        }
        // ファイル差し替え時も波形を再生成
        .onChange(of: viewModel.project.videoFile?.id) { _ in
            if viewModel.project.isReady {
                autoGenerateWaveforms()
            }
        }
        .onChange(of: viewModel.project.audioFile?.id) { _ in
            if viewModel.project.isReady {
                autoGenerateWaveforms()
            }
        }
        // ファイル差し替え確認ダイアログ
        .alert("ファイルを差し替えますか？", isPresented: $showReplaceConfirmation) {
            Button("キャンセル", role: .cancel) {
                pendingFileAction = nil
            }
            Button("差し替える", role: .destructive) {
                viewModel.project.exportSettings.offsetSeconds = 0
                syncViewModel.reset()
                pendingFileAction?()
                pendingFileAction = nil
            }
        } message: {
            Text("現在の波形とオフセット設定がリセットされます。")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // アイコン
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "film.stack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("MP4 Sound Replacer")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Spacer()

            // FFmpeg状態表示
            ffmpegStatusView
        }
    }

    private var ffmpegStatusView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isFFmpegAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(viewModel.isFFmpegAvailable ? "FFmpeg OK" : "FFmpeg未設定")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ファイルドロップゾーン
                VStack(spacing: 10) {
                    Text("ファイル")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VideoDropZone(file: viewModel.project.videoFile) { url in
                        if url.path.isEmpty {
                            viewModel.clearVideoFile()
                            syncViewModel.reset()
                        } else {
                            setVideoFile(url: url)
                        }
                    }

                    AudioDropZone(file: viewModel.project.audioFile) { url in
                        if url.path.isEmpty {
                            viewModel.clearAudioFile()
                            syncViewModel.reset()
                        } else {
                            setAudioFile(url: url)
                        }
                    }
                }

                Divider()

                // エクスポート設定
                VStack(spacing: 10) {
                    Text("エクスポート設定")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ExportSettingsView(settings: $viewModel.project.exportSettings)
                        .disabled(!viewModel.project.isReady)
                        .opacity(viewModel.project.isReady ? 1.0 : 0.6)
                }

                Divider()

                // アクションボタン
                actionButtonsView

                Spacer()
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        VStack(spacing: 0) {
            if viewModel.project.isReady {
                // 波形同期ビュー
                WaveformSyncView(
                    syncViewModel: syncViewModel,
                    offsetSeconds: $viewModel.project.exportSettings.offsetSeconds,
                    videoURL: viewModel.project.videoFile?.url,
                    audioURL: viewModel.project.audioFile?.url,
                    onOffsetChanged: { newOffset in
                        viewModel.project.exportSettings.offsetSeconds = newOffset
                    },
                    onResetOffset: {
                        viewModel.project.exportSettings.offsetSeconds = 0
                    }
                )
                .padding(16)
            } else {
                // プレースホルダー
                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary.opacity(0.3))

                    Text("ファイルを選択すると\n波形が表示されます")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtonsView: some View {
        VStack(spacing: 10) {
            // エクスポートボタン
            Button(action: {
                withAnimation {
                    viewModel.export()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("エクスポート")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.project.canExport || !viewModel.isFFmpegAvailable)
            .opacity((!viewModel.project.canExport || !viewModel.isFFmpegAvailable) ? 0.5 : 1.0)

            // リセットボタン
            Button(action: {
                withAnimation {
                    viewModel.reset()
                    syncViewModel.reset()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                    Text("リセット")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.project.state.isProcessing)
            .opacity(viewModel.project.state.isProcessing ? 0.5 : 1.0)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            switch viewModel.project.state {
            case .exporting(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(1)

            case .completed(let url):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("完了: \(url.lastPathComponent)")
                    .font(.system(size: 11))
                    .lineLimit(1)
                Button("Finderで表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.link)
                .font(.system(size: 11))

            default:
                if viewModel.project.isReady {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("エクスポート準備完了")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    Text("動画と音声ファイルを選択してください")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Helper Methods

    private func autoGenerateWaveforms() {
        guard let videoURL = viewModel.project.videoFile?.url,
              let audioURL = viewModel.project.audioFile?.url else {
            return
        }
        Task {
            await syncViewModel.generateWaveforms(videoURL: videoURL, audioURL: audioURL)
        }
    }

    private func setVideoFile(url: URL) {
        if viewModel.project.videoFile != nil {
            pendingFileAction = { viewModel.setVideoFile(url: url) }
            showReplaceConfirmation = true
        } else {
            viewModel.setVideoFile(url: url)
        }
    }

    private func setAudioFile(url: URL) {
        if viewModel.project.audioFile != nil {
            pendingFileAction = { viewModel.setAudioFile(url: url) }
            showReplaceConfirmation = true
        } else {
            viewModel.setAudioFile(url: url)
        }
    }
}

#Preview {
    ContentView()
}
