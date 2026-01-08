import SwiftUI

/// メインコンテンツビュー
struct ContentView: View {
    @StateObject private var viewModel = ProjectViewModel()

    var body: some View {
        VStack(spacing: 20) {
            // ヘッダー
            headerView

            // ファイルドロップゾーン
            fileDropZonesView

            // エクスポート設定
            if viewModel.project.isReady {
                ExportSettingsView(settings: $viewModel.project.exportSettings)
            }

            Spacer()

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
        .frame(minWidth: 600, minHeight: 500)
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

    /// ファイルドロップゾーン
    private var fileDropZonesView: some View {
        HStack(spacing: 16) {
            VideoDropZone(file: viewModel.project.videoFile) { url in
                if url.path.isEmpty {
                    viewModel.clearVideoFile()
                } else {
                    viewModel.setVideoFile(url: url)
                }
            }

            AudioDropZone(file: viewModel.project.audioFile) { url in
                if url.path.isEmpty {
                    viewModel.clearAudioFile()
                } else {
                    viewModel.setAudioFile(url: url)
                }
            }
        }
    }

    /// アクションボタン
    private var actionButtonsView: some View {
        HStack {
            Button("リセット") {
                viewModel.reset()
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
