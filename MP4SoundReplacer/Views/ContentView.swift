import SwiftUI

/// メインコンテンツビュー
struct ContentView: View {
    @StateObject private var viewModel = ProjectViewModel()
    @StateObject private var syncViewModel = SyncAnalyzerViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ヘッダー
                headerView

                // 上部セクション: ファイルドロップゾーン + エクスポート設定を横並び
                topSection

                // 波形同期（ファイル設定後に表示）
                if viewModel.project.isReady {
                    WaveformSyncView(
                        syncViewModel: syncViewModel,
                        offsetSeconds: $viewModel.project.exportSettings.offsetSeconds,
                        videoURL: viewModel.project.videoFile?.url,
                        audioURL: viewModel.project.audioFile?.url,
                        onOffsetChanged: { newOffset in
                            viewModel.project.exportSettings.offsetSeconds = newOffset
                        }
                    )
                }

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
        .frame(minWidth: 800, minHeight: 500)
        // 自動波形表示: 両方のファイルがセットされたら自動的に波形を生成
        .onChange(of: viewModel.project.isReady) { isReady in
            if isReady {
                autoGenerateWaveforms()
            }
        }
    }

    /// 自動波形生成
    private func autoGenerateWaveforms() {
        guard let videoURL = viewModel.project.videoFile?.url,
              let audioURL = viewModel.project.audioFile?.url else {
            return
        }
        // 波形がまだ生成されていない場合のみ実行
        if syncViewModel.videoWaveform == nil || syncViewModel.audioWaveform == nil {
            Task {
                await syncViewModel.generateWaveforms(videoURL: videoURL, audioURL: audioURL)
            }
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
                    .font(.caption)
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
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// 上部セクション: ファイルドロップゾーン + エクスポート設定
    private var topSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // 動画ファイル
            VideoDropZone(file: viewModel.project.videoFile) { url in
                if url.path.isEmpty {
                    viewModel.clearVideoFile()
                    syncViewModel.reset()
                } else {
                    viewModel.setVideoFile(url: url)
                }
            }
            .frame(minWidth: 200)

            // 音声ファイル
            AudioDropZone(file: viewModel.project.audioFile) { url in
                if url.path.isEmpty {
                    viewModel.clearAudioFile()
                    syncViewModel.reset()
                } else {
                    viewModel.setAudioFile(url: url)
                }
            }
            .frame(minWidth: 200)

            // エクスポート設定（ファイル設定後に表示）
            if viewModel.project.isReady {
                ExportSettingsView(settings: $viewModel.project.exportSettings)
                    .frame(minWidth: 280)
            }
        }
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
                .font(.caption)
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
                .font(.caption)
                .fontWeight(.medium)

            Text(url.lastPathComponent)
                .font(.caption)
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
