import SwiftUI

/// メインコンテンツビュー（2カラムレイアウト）
struct ContentView: View {
    @StateObject private var viewModel = ProjectViewModel()
    @StateObject private var syncViewModel = SyncAnalyzerViewModel()

    /// ファイル差し替え確認ダイアログの状態
    @State private var showReplaceConfirmation = false
    @State private var pendingFileAction: (() -> Void)?

    /// 左カラムの幅
    private let leftColumnWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // メインコンテンツ（2カラム）
            HStack(spacing: 0) {
                // 左カラム: ファイル選択 + エクスポート
                leftColumn
                    .frame(width: leftColumnWidth)

                Divider()

                // 右カラム: 波形表示 + オフセット調整
                rightColumn
                    .frame(maxWidth: .infinity)
            }

            Divider()

            // ステータスバー
            statusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(minWidth: 950, minHeight: 650)
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
                    .frame(width: 34, height: 34)

                Image(systemName: "film.stack")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("Audio Remux")
                .font(.system(size: 17, weight: .bold, design: .rounded))

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
        VStack(spacing: 0) {
            // ファイルドロップゾーン
            VStack(spacing: 10) {
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
            .padding(14)

            Divider()
                .padding(.horizontal, 14)

            // エクスポート設定
            exportSettingsSection
                .padding(14)

            Spacer()

            // アクションボタン（下揃え）
            actionButtonsSection
                .padding(14)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    // MARK: - Export Settings Section

    private var exportSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 出力フォーマット選択
            VStack(alignment: .leading, spacing: 6) {
                Text("出力フォーマット")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Picker("", selection: $viewModel.project.exportSettings.outputContainer) {
                    ForEach(OutputContainer.allCases) { container in
                        Text(container.displayName).tag(container)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.project.exportSettings.outputContainer) { _ in
                    viewModel.project.exportSettings.adjustCodecForContainer()
                }

                Text(viewModel.project.exportSettings.outputContainer.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // コーデック選択
            HStack {
                Text("出力コーデック")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                Spacer()

                Picker("", selection: $viewModel.project.exportSettings.audioCodec) {
                    ForEach(viewModel.project.exportSettings.outputContainer.supportedAudioCodecs) { codec in
                        Text(codec == viewModel.project.exportSettings.outputContainer.recommendedCodec
                             ? "\(codec.displayName) (推奨)"
                             : codec.displayName)
                            .tag(codec)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            // ビット深度選択（FLAC/ALAC/PCM選択時のみ表示）
            if viewModel.project.exportSettings.audioCodec.supportsBitDepth {
                HStack {
                    Text("ビット深度")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)

                    Spacer()

                    Picker("", selection: $viewModel.project.exportSettings.audioBitDepth) {
                        ForEach(BitDepth.allCases) { depth in
                            Text(depth.displayName).tag(depth)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }

            // ビットレート選択（AAC選択時のみ表示）
            if viewModel.project.exportSettings.audioCodec.requiresBitrate {
                HStack {
                    Text("ビットレート")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)

                    Spacer()

                    Picker("", selection: $viewModel.project.exportSettings.audioBitrate) {
                        ForEach(AudioBitrate.allCases) { bitrate in
                            Text(bitrate.displayName).tag(bitrate)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }

            // コーデック互換性警告
            if let warning = viewModel.project.exportSettings.outputContainer.warning(for: viewModel.project.exportSettings.audioCodec) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }

            // ファイル名サフィックス
            VStack(alignment: .leading, spacing: 4) {
                Text("ファイル名サフィックス")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)

                TextField("_replaced", text: $viewModel.project.exportSettings.outputSuffix)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Text("出力例: input\(viewModel.project.exportSettings.effectiveSuffix).\(viewModel.project.exportSettings.outputContainer.fileExtension)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // 自動フェード
            HStack {
                Text("自動フェード")
                    .font(.system(size: 13))

                Spacer()

                Toggle("", isOn: $viewModel.project.exportSettings.autoFadeEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        HStack(spacing: 8) {
            // リセットボタン
            Button(action: {
                withAnimation {
                    viewModel.reset()
                    syncViewModel.reset()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                    Text("リセット")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
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
            .disabled(viewModel.project.state.isProcessing)

            // エクスポートボタン
            Button(action: {
                withAnimation {
                    viewModel.export()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("エクスポート")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.project.canExport || !viewModel.isFFmpegAvailable)
            .opacity((!viewModel.project.canExport || !viewModel.isFFmpegAvailable) ? 0.5 : 1.0)
        }
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
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // オフセットコントロール（波形の直下）
                OffsetControlView(
                    offsetSeconds: $viewModel.project.exportSettings.offsetSeconds,
                    onReset: {
                        viewModel.project.exportSettings.offsetSeconds = 0
                    }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

                Spacer()
            } else {
                // プレースホルダー
                VStack(spacing: 14) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 56))
                        .foregroundColor(.secondary.opacity(0.3))

                    Text("ファイルを選択すると\n波形が表示されます")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .monospacedDigit()

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .lineLimit(1)

            case .completed(let url):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
                Text("完了: \(url.lastPathComponent)")
                    .font(.system(size: 12))
                    .lineLimit(1)
                Button("Finderで表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.link)
                .font(.system(size: 12))

            default:
                if viewModel.project.isReady {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("エクスポート準備完了")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    Text("動画と音声ファイルを選択してください")
                        .font(.system(size: 12))
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
