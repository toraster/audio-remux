import SwiftUI
import UniformTypeIdentifiers

/// メインコンテンツビュー（2カラムレイアウト）
struct ContentView: View {
    private struct PendingWaveformRefresh {
        let videoPath: String
        let audioPath: String
    }

    private struct PendingDropAnimationContext {
        let startPoint: CGPoint
        let mediaKinds: [FileDropSupport.MediaKind]
    }

    @StateObject private var viewModel = ProjectViewModel()
    @StateObject private var syncViewModel = SyncAnalyzerViewModel()

    /// ファイル差し替え確認ダイアログの状態
    @State private var showReplaceConfirmation = false
    @State private var pendingFileActions: [() -> Void] = []
    @State private var pendingWaveformRefresh: PendingWaveformRefresh?
    @State private var pendingDropAnimationContext: PendingDropAnimationContext?
    @State private var activeDropAnimations: [ActiveDropAnimation] = []
    @State private var isGlobalDropTargeted = false
    @State private var isVideoDropTargeted = false
    @State private var isAudioDropTargeted = false
    @State private var fileDropAreaFrame: CGRect = .zero
    @State private var videoDropZoneFrame: CGRect = .zero
    @State private var audioDropZoneFrame: CGRect = .zero

    /// 詳細設定の折りたたみ状態
    @State private var showAdvancedSettings = false

    /// 左カラムの幅
    private let leftColumnWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー（高さ固定）
            headerView
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .fixedSize(horizontal: false, vertical: true)

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
            .frame(maxHeight: .infinity)

            Divider()

            // ステータスバー（高さ固定）
            statusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 950, minHeight: 650)
        .coordinateSpace(name: DropAnimationCoordinateSpace.name)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(dropOverlay)
        .onDrop(of: FileDropSupport.allTypes, delegate: GlobalFileDropDelegate(
            acceptedTypes: FileDropSupport.allTypes,
            isGlobalDropTargeted: $isGlobalDropTargeted,
            onDragChanged: updateDropTargets,
            onDragEnded: resetDropTargets,
            onRejectedDrop: handleRejectedDrop,
            onPerformDrop: handleGlobalDrop
        ))
        .onChange(of: viewModel.project.videoFile?.id) { _ in
            generateWaveformsIfReady()
        }
        .onChange(of: viewModel.project.audioFile?.id) { _ in
            generateWaveformsIfReady()
        }
        .onChange(of: viewModel.project.state) { state in
            if case .error = state {
                recoverPendingWaveformRefreshIfNeeded()
            }
        }
        // ファイル差し替え確認ダイアログ
        .alert("ファイルを差し替えますか？", isPresented: $showReplaceConfirmation) {
            Button("キャンセル", role: .cancel) {
                pendingFileActions = []
                pendingWaveformRefresh = nil
                pendingDropAnimationContext = nil
            }
            Button("差し替える", role: .destructive) {
                resetSyncStateForReplacement()
                playPendingDropAnimationsIfNeeded()
                applyFileActions(pendingFileActions)
                pendingFileActions = []
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
                VideoDropZone(
                    file: viewModel.project.videoFile,
                    isTargeted: isVideoDropTargeted,
                    onDrop: handleVideoDropZoneSelection,
                    onFrameChange: { videoDropZoneFrame = $0 }
                )

                AudioDropZone(
                    file: viewModel.project.audioFile,
                    isTargeted: isAudioDropTargeted,
                    onDrop: handleAudioDropZoneSelection,
                    onFrameChange: { audioDropZoneFrame = $0 }
                )
            }
            .padding(14)
            .background(fileDropAreaFrameReader)

            Divider()
                .padding(.horizontal, 14)

            // エクスポート設定（スクロール可能、残りスペースを占有）
            ScrollView(.vertical, showsIndicators: showAdvancedSettings) {
                exportSettingsSection
                    .padding(14)
            }
            .frame(maxHeight: .infinity)

            // アクションボタン（常に下部に固定）
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

            // 詳細設定（折りたたみ可能）
            DisclosureGroup(isExpanded: $showAdvancedSettings) {
                VStack(alignment: .leading, spacing: 12) {
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
                .padding(.top, 8)
            } label: {
                Text("詳細設定")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
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
                stepGuideStatusView
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var stepGuideStatusView: some View {
        let guide = currentStepGuide
        Image(systemName: guide.icon)
            .foregroundColor(guide.color)
            .font(.system(size: 12))
        Text(guide.message)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
    }

    private var currentStepGuide: (icon: String, color: Color, message: String) {
        let hasVideo = viewModel.project.videoFile != nil
        let hasAudio = viewModel.project.audioFile != nil

        if syncViewModel.syncState.isProcessing {
            return ("waveform", .accentColor, "波形を生成中...")
        } else if hasVideo && hasAudio && syncViewModel.videoWaveform != nil {
            return ("checkmark.circle", .green, "自動同期を試すか、波形をドラッグして調整してエクスポートしてください")
        } else if hasVideo && !hasAudio {
            return ("arrow.down.circle", .accentColor, "音声ファイルをドロップしてください")
        } else if !hasVideo && hasAudio {
            return ("arrow.down.circle", .accentColor, "動画ファイルをドロップしてください")
        } else {
            return ("arrow.down.circle", .secondary, "動画と音声ファイルをドロップしてください")
        }
    }

    private var dropOverlay: some View {
        ZStack {
            globalDropHighlight

            ForEach(activeDropAnimations) { animation in
                DropSuctionTokenView(animation: animation)
            }
        }
        .allowsHitTesting(false)
    }

    private var globalDropHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.accentColor.opacity(isGlobalDropTargeted ? 0.05 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Color.accentColor.opacity(isGlobalDropTargeted ? 0.45 : 0),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 6])
                    )
            )
            .padding(8)
            .animation(.easeInOut(duration: 0.15), value: isGlobalDropTargeted)
    }

    private var fileDropAreaFrameReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    fileDropAreaFrame = proxy.frame(in: .named(DropAnimationCoordinateSpace.name))
                }
                .onChange(of: proxy.frame(in: .named(DropAnimationCoordinateSpace.name))) { frame in
                    fileDropAreaFrame = frame
                }
        }
    }

    // MARK: - Helper Methods

    private func autoGenerateWaveforms(videoURL: URL, audioURL: URL) {
        Task {
            await syncViewModel.generateWaveforms(videoURL: videoURL, audioURL: audioURL)
        }
    }

    private func generateWaveformsIfReady() {
        guard let videoURL = viewModel.project.videoFile?.url,
              let audioURL = viewModel.project.audioFile?.url else {
            return
        }

        if let pendingWaveformRefresh {
            guard videoURL.path == pendingWaveformRefresh.videoPath,
                  audioURL.path == pendingWaveformRefresh.audioPath else {
                return
            }
            self.pendingWaveformRefresh = nil
        }

        autoGenerateWaveforms(videoURL: videoURL, audioURL: audioURL)
    }

    private func recoverPendingWaveformRefreshIfNeeded() {
        guard pendingWaveformRefresh != nil else { return }
        pendingWaveformRefresh = nil
        generateWaveformsIfReady()
    }

    private func handleGlobalDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        FileDropSupport.handleDrop(providers: providers, acceptedTypes: FileDropSupport.allTypes) { urls in
            applyDroppedFiles(urls, dropLocation: location)
        }
    }

    private func applyDroppedFiles(_ urls: [URL], dropLocation: CGPoint) {
        let classifiedURLs = FileDropSupport.classify(urls: urls)

        guard let invalidMessage = FileDropSupport.invalidDropMessage(
            videoCount: classifiedURLs.video.count,
            audioCount: classifiedURLs.audio.count
        ) else {
            applySelectedFiles(
                videoURL: classifiedURLs.video.first,
                audioURL: classifiedURLs.audio.first,
                dropLocation: dropLocation
            )
            return
        }

        handleRejectedDrop(message: invalidMessage)
    }

    private func applySelectedFiles(videoURL: URL?, audioURL: URL?, dropLocation: CGPoint? = nil) {
        var actions: [() -> Void] = []

        if let videoURL {
            actions.append { viewModel.setVideoFile(url: videoURL) }
        }

        if let audioURL {
            actions.append { viewModel.setAudioFile(url: audioURL) }
        }

        guard !actions.isEmpty else { return }

        pendingWaveformRefresh = makePendingWaveformRefresh(videoURL: videoURL, audioURL: audioURL)
        let dropAnimationContext = makePendingDropAnimationContext(
            videoURL: videoURL,
            audioURL: audioURL,
            dropLocation: dropLocation
        )

        let requiresReplacementConfirmation =
            (videoURL != nil && viewModel.project.videoFile != nil) ||
            (audioURL != nil && viewModel.project.audioFile != nil)

        if requiresReplacementConfirmation {
            pendingFileActions = actions
            pendingDropAnimationContext = dropAnimationContext
            showReplaceConfirmation = true
        } else {
            pendingDropAnimationContext = nil
            playDropAnimations(dropAnimationContext)
            applyFileActions(actions)
        }
    }

    private func applyFileActions(_ actions: [() -> Void]) {
        actions.forEach { $0() }
    }

    private func makePendingWaveformRefresh(videoURL: URL?, audioURL: URL?) -> PendingWaveformRefresh? {
        guard let videoURL, let audioURL else { return nil }
        return PendingWaveformRefresh(videoPath: videoURL.path, audioPath: audioURL.path)
    }

    private func makePendingDropAnimationContext(
        videoURL: URL?,
        audioURL: URL?,
        dropLocation: CGPoint?
    ) -> PendingDropAnimationContext? {
        guard let dropLocation else { return nil }

        var mediaKinds: [FileDropSupport.MediaKind] = []
        if videoURL != nil {
            mediaKinds.append(.video)
        }
        if audioURL != nil {
            mediaKinds.append(.audio)
        }

        guard !mediaKinds.isEmpty else { return nil }
        return PendingDropAnimationContext(startPoint: dropLocation, mediaKinds: mediaKinds)
    }

    private func playPendingDropAnimationsIfNeeded() {
        playDropAnimations(pendingDropAnimationContext)
        pendingDropAnimationContext = nil
    }

    private func playDropAnimations(_ context: PendingDropAnimationContext?) {
        guard let context else { return }

        let newAnimations = context.mediaKinds.compactMap { mediaKind -> ActiveDropAnimation? in
            guard let endPoint = dropAnimationEndpoint(for: mediaKind) else { return nil }
            return ActiveDropAnimation(
                iconName: dropAnimationIconName(for: mediaKind),
                tint: dropAnimationTint(for: mediaKind),
                startPoint: context.startPoint,
                endPoint: endPoint
            )
        }

        guard !newAnimations.isEmpty else { return }

        activeDropAnimations.append(contentsOf: newAnimations)

        let animationIDs = Set(newAnimations.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            activeDropAnimations.removeAll { animationIDs.contains($0.id) }
        }
    }

    private func dropAnimationEndpoint(for mediaKind: FileDropSupport.MediaKind) -> CGPoint? {
        guard !fileDropAreaFrame.isEmpty else { return nil }
        let targetFrame: CGRect

        switch mediaKind {
        case .video:
            targetFrame = videoDropZoneFrame
        case .audio:
            targetFrame = audioDropZoneFrame
        }

        guard !targetFrame.isEmpty else { return nil }
        return CGPoint(
            x: targetFrame.minX + targetFrame.width * 0.3,
            y: targetFrame.midY
        )
    }

    private func dropAnimationIconName(for mediaKind: FileDropSupport.MediaKind) -> String {
        switch mediaKind {
        case .video:
            return "film.fill"
        case .audio:
            return "waveform"
        }
    }

    private func dropAnimationTint(for mediaKind: FileDropSupport.MediaKind) -> Color {
        switch mediaKind {
        case .video:
            return .accentColor
        case .audio:
            return .purple
        }
    }

    private func resetSyncStateForReplacement() {
        viewModel.project.exportSettings.offsetSeconds = 0
        syncViewModel.reset()
    }

    private func updateDropTargets(for mediaKinds: Set<FileDropSupport.MediaKind>) {
        isVideoDropTargeted = mediaKinds.contains(.video)
        isAudioDropTargeted = mediaKinds.contains(.audio)
    }

    private func resetDropTargets() {
        isVideoDropTargeted = false
        isAudioDropTargeted = false
    }

    private func handleRejectedDrop(message: String) {
        viewModel.project.state = .error(message: message)
    }

    private func handleVideoDropZoneSelection(url: URL) {
        if url.path.isEmpty {
            viewModel.clearVideoFile()
            syncViewModel.reset()
        } else {
            setVideoFile(url: url)
        }
    }

    private func handleAudioDropZoneSelection(url: URL) {
        if url.path.isEmpty {
            viewModel.clearAudioFile()
            syncViewModel.reset()
        } else {
            setAudioFile(url: url)
        }
    }

    private func setVideoFile(url: URL) {
        applySelectedFiles(videoURL: url, audioURL: nil)
    }

    private func setAudioFile(url: URL) {
        applySelectedFiles(videoURL: nil, audioURL: url)
    }
}

private struct ActiveDropAnimation: Identifiable {
    let id = UUID()
    let iconName: String
    let tint: Color
    let startPoint: CGPoint
    let endPoint: CGPoint
}

private struct GlobalFileDropDelegate: DropDelegate {
    let acceptedTypes: [UTType]
    let isGlobalDropTargeted: Binding<Bool>
    let onDragChanged: (Set<FileDropSupport.MediaKind>) -> Void
    let onDragEnded: () -> Void
    let onRejectedDrop: (String) -> Void
    let onPerformDrop: ([NSItemProvider], CGPoint) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: acceptedTypes).isEmpty
    }

    func dropEntered(info: DropInfo) {
        updateDragState(with: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let providers = info.itemProviders(for: acceptedTypes)
        isGlobalDropTargeted.wrappedValue = !providers.isEmpty

        guard !providers.isEmpty else {
            onDragChanged([])
            return DropProposal(operation: .forbidden)
        }

        let isAllowedDrop = FileDropSupport.isAllowedDrop(providers: providers)
        onDragChanged(isAllowedDrop ? FileDropSupport.mediaKinds(in: providers) : [])
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        resetDragState()
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: acceptedTypes)
        let location = info.location

        resetDragState()

        if let invalidMessage = FileDropSupport.invalidDropMessage(for: providers) {
            onRejectedDrop(invalidMessage)
            return true
        }

        return onPerformDrop(providers, location)
    }

    private func updateDragState(with info: DropInfo) {
        let providers = info.itemProviders(for: acceptedTypes)
        let isAllowedDrop = FileDropSupport.isAllowedDrop(providers: providers)
        isGlobalDropTargeted.wrappedValue = !providers.isEmpty
        onDragChanged(isAllowedDrop ? FileDropSupport.mediaKinds(in: providers) : [])
    }

    private func resetDragState() {
        isGlobalDropTargeted.wrappedValue = false
        onDragEnded()
    }
}

private struct DropSuctionTokenView: View {
    let animation: ActiveDropAnimation

    @State private var hasStarted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: animation.iconName)
                .font(.system(size: 12, weight: .bold))
            Circle()
                .fill(animation.tint.opacity(0.7))
                .frame(width: 6, height: 6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(animation.tint.opacity(0.92))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: animation.tint.opacity(0.28), radius: 10, x: 0, y: 6)
        .position(hasStarted ? animation.endPoint : animation.startPoint)
        .scaleEffect(hasStarted ? 0.42 : 1.0)
        .opacity(hasStarted ? 0.04 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.45)) {
                hasStarted = true
            }
        }
    }
}

#Preview {
    ContentView()
}
