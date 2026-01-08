import SwiftUI

/// メインコンテンツビュー
struct ContentView: View {
    @StateObject private var viewModel = ProjectViewModel()
    @StateObject private var syncViewModel = SyncAnalyzerViewModel()

    /// ファイル差し替え確認ダイアログの状態
    @State private var showReplaceConfirmation = false
    @State private var pendingFileAction: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ヘッダー
                headerView

                // 上部セクション: ファイルドロップゾーン + エクスポート設定を横並び（50/50）
                topSection

                // 波形同期（常に表示、無効状態で）
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
                .disabled(!viewModel.project.isReady)
                .opacity(viewModel.project.isReady ? 1.0 : 0.5)

                // アクションボタン
                actionButtonsView

                // プログレス表示
                if case .exporting(let progress) = viewModel.project.state {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }

                // エラー表示
                if case .error(let message) = viewModel.project.state {
                    errorView(message)
                }

                // 完了表示
                if case .completed(let url) = viewModel.project.state {
                    completedView(url)
                }
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
        // 自動波形表示: 両方のファイルがセットされたら自動的に波形を生成
        .onChange(of: viewModel.project.isReady) { isReady in
            if isReady {
                autoGenerateWaveforms()
            }
        }
        // ファイル差し替え確認ダイアログ
        .alert("ファイルを差し替えますか？", isPresented: $showReplaceConfirmation) {
            Button("キャンセル", role: .cancel) {
                pendingFileAction = nil
            }
            Button("差し替える", role: .destructive) {
                // 設定をリセット
                viewModel.project.exportSettings.offsetSeconds = 0
                syncViewModel.reset()
                // ファイルを設定
                pendingFileAction?()
                pendingFileAction = nil
            }
        } message: {
            Text("現在の波形とオフセット設定がリセットされます。")
        }
    }

    /// 自動波形生成
    private func autoGenerateWaveforms() {
        guard let videoURL = viewModel.project.videoFile?.url,
              let audioURL = viewModel.project.audioFile?.url else {
            return
        }
        Task {
            await syncViewModel.generateWaveforms(videoURL: videoURL, audioURL: audioURL)
        }
    }

    /// ファイル設定（差し替え時は確認ダイアログを表示）
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

    /// ヘッダー
    private var headerView: some View {
        HStack {
            Image(systemName: "film")
                .font(.title)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading) {
                Text("MP4 Sound Replacer")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("動画の音声を無劣化で差し替え")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // FFmpeg状態表示
            ffmpegStatusView
        }
    }

    /// FFmpeg状態表示
    private var ffmpegStatusView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(viewModel.isFFmpegAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(viewModel.isFFmpegAvailable ? "FFmpeg OK" : "FFmpeg未設定")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    /// 上部セクション: ファイルドロップゾーン + エクスポート設定（50/50レイアウト）
    private var topSection: some View {
        GeometryReader { geometry in
            let halfWidth = (geometry.size.width - 16) / 2
            HStack(alignment: .top, spacing: 16) {
                // 左側: ファイルドロップゾーン（縦並び）
                VStack(spacing: 12) {
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
                .frame(width: halfWidth)

                // 右側: エクスポート設定（常に表示、無効状態で）
                ExportSettingsView(settings: $viewModel.project.exportSettings)
                    .disabled(!viewModel.project.isReady)
                    .opacity(viewModel.project.isReady ? 1.0 : 0.5)
                    .frame(width: halfWidth)
            }
        }
        .frame(height: 280)
    }

    /// アクションボタン
    private var actionButtonsView: some View {
        HStack {
            Button("リセット") {
                viewModel.reset()
                syncViewModel.reset()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.project.state.isProcessing)

            Spacer()

            Button("エクスポート") {
                viewModel.export()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.project.canExport || !viewModel.isFFmpegAvailable)
        }
    }

    /// エラー表示
    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.callout)
                .foregroundColor(.red)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
    }

    /// 完了表示
    private func completedView(_ url: URL) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

            Text("エクスポート完了")
                .font(.callout)
                .fontWeight(.medium)

            Text(url.lastPathComponent)
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            Button("Finderで表示") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.1))
        )
    }
}

#Preview {
    ContentView()
}
