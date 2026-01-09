import SwiftUI

/// メインコンテンツビュー
struct ContentView: View {
    @StateObject private var viewModel = ProjectViewModel()
    @StateObject private var syncViewModel = SyncAnalyzerViewModel()

    /// ファイル差し替え確認ダイアログの状態
    @State private var showReplaceConfirmation = false
    @State private var pendingFileAction: (() -> Void)?

    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.windowBackgroundColor).opacity(0.95)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    // ヘッダー
                    headerView

                    // 上部セクション: ファイルドロップゾーン + エクスポート設定を横並び
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
                    .animation(.easeInOut(duration: 0.3), value: viewModel.project.isReady)

                    // アクションボタン
                    actionButtonsView

                    // プログレス表示
                    if case .exporting(let progress) = viewModel.project.state {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .transition(.opacity.combined(with: .scale))
                    }

                    // エラー表示
                    if case .error(let message) = viewModel.project.state {
                        errorView(message)
                            .transition(.opacity.combined(with: .scale))
                    }

                    // 完了表示
                    if case .completed(let url) = viewModel.project.state {
                        completedView(url)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
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
        HStack(spacing: 12) {
            // アイコンにグラデーション
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: "film.stack")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("MP4 Sound Replacer")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Spacer()

            // FFmpeg状態表示
            ffmpegStatusView
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
    }

    /// FFmpeg状態表示
    private var ffmpegStatusView: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(viewModel.isFFmpegAvailable ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .frame(width: 20, height: 20)

                Circle()
                    .fill(viewModel.isFFmpegAvailable ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
            }

            Text(viewModel.isFFmpegAvailable ? "FFmpeg OK" : "FFmpeg未設定")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
    }

    /// 上部セクション: ファイルドロップゾーン + エクスポート設定（50/50レイアウト）
    private var topSection: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左側: ファイルドロップゾーン（縦並び）
            VStack(spacing: 8) {
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
            .frame(maxWidth: .infinity)

            // 右側: エクスポート設定（常に表示、無効状態で）
            ExportSettingsView(settings: $viewModel.project.exportSettings)
                .disabled(!viewModel.project.isReady)
                .opacity(viewModel.project.isReady ? 1.0 : 0.5)
                .frame(maxWidth: .infinity)
        }
    }

    /// アクションボタン
    private var actionButtonsView: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation {
                    viewModel.reset()
                    syncViewModel.reset()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("リセット")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.project.state.isProcessing)
            .opacity(viewModel.project.state.isProcessing ? 0.5 : 1.0)

            Spacer()

            Button(action: {
                withAnimation {
                    viewModel.export()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("エクスポート")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.project.canExport || !viewModel.isFFmpegAvailable)
            .opacity((!viewModel.project.canExport || !viewModel.isFFmpegAvailable) ? 0.5 : 1.0)
            .scaleEffect((!viewModel.project.canExport || !viewModel.isFFmpegAvailable) ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: viewModel.project.canExport)
        }
    }

    /// エラー表示
    private func errorView(_ message: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("エラーが発生しました")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.red)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.9))
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.red.opacity(0.1), radius: 6, x: 0, y: 2)
    }

    /// 完了表示
    private func completedView(_ url: URL) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("エクスポート完了")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.green)

                Text(url.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Finderで表示")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.green.opacity(0.1), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}
