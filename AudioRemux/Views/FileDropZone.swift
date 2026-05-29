import SwiftUI
import UniformTypeIdentifiers

enum DropAnimationCoordinateSpace {
    static let name = "global-file-drop-area"
}

enum FileDropSupport {
    enum MediaKind: Hashable {
        case video
        case audio
    }

    static let videoTypes: [UTType] = [
        .mpeg4Movie,
        .quickTimeMovie,
        UTType("com.apple.m4v-video")!
    ]

    static let audioTypes: [UTType] = [
        .wav,
        .aiff,
        UTType(filenameExtension: "flac")!
    ]

    static let allTypes: [UTType] = {
        var seenIdentifiers = Set<String>()
        return (videoTypes + audioTypes).filter { seenIdentifiers.insert($0.identifier).inserted }
    }()

    static func mediaKinds(in providers: [NSItemProvider]) -> Set<MediaKind> {
        providers.reduce(into: Set<MediaKind>()) { result, provider in
            result.formUnion(mediaKinds(for: provider))
        }
    }

    static func countSupportedMedia(in providers: [NSItemProvider]) -> (video: Int, audio: Int) {
        providers.reduce(into: (video: 0, audio: 0)) { result, provider in
            let kinds = mediaKinds(for: provider)
            if kinds.contains(.video) {
                result.video += 1
            }
            if kinds.contains(.audio) {
                result.audio += 1
            }
        }
    }

    static func isAllowedDrop(providers: [NSItemProvider]) -> Bool {
        let counts = countSupportedMedia(in: providers)
        return !providers.isEmpty && counts.video <= 1 && counts.audio <= 1
    }

    static func invalidDropMessage(for providers: [NSItemProvider]) -> String? {
        let counts = countSupportedMedia(in: providers)
        return invalidDropMessage(videoCount: counts.video, audioCount: counts.audio)
    }

    static func classify(urls: [URL]) -> (video: [URL], audio: [URL]) {
        urls.reduce(into: (video: [URL](), audio: [URL]())) { result, url in
            switch MediaFile.detectType(from: url) {
            case .video?:
                result.video.append(url)
            case .audio?:
                result.audio.append(url)
            default:
                break
            }
        }
    }

    static func invalidDropMessage(videoCount: Int, audioCount: Int) -> String? {
        if videoCount > 1 && audioCount > 1 {
            return "動画ファイルと音声ファイルは、それぞれ1つずつだけドロップできます。"
        }

        if videoCount > 1 {
            return "動画ファイルは1つだけドロップできます。"
        }

        if audioCount > 1 {
            return "音声ファイルは1つだけドロップできます。"
        }

        return nil
    }

    static func handleDrop(
        providers: [NSItemProvider],
        acceptedTypes: [UTType],
        onLoad: @escaping ([URL]) -> Void
    ) -> Bool {
        let acceptedProviders = providers.enumerated().compactMap { index, provider -> (Int, NSItemProvider, [String])? in
            let matchingTypeIdentifiers = acceptedTypes
                .map(\.identifier)
                .filter { provider.hasItemConformingToTypeIdentifier($0) }

            guard !matchingTypeIdentifiers.isEmpty else { return nil }
            return (index, provider, matchingTypeIdentifiers)
        }

        guard !acceptedProviders.isEmpty else { return false }

        var urlsByIndex = Array<URL?>(repeating: nil, count: providers.count)
        let group = DispatchGroup()

        for (index, provider, identifiers) in acceptedProviders {
            group.enter()
            loadURL(from: provider, typeIdentifiers: identifiers) { url in
                DispatchQueue.main.async {
                    urlsByIndex[index] = url
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let urls = urlsByIndex.compactMap { $0 }
            guard !urls.isEmpty else { return }
            onLoad(urls)
        }

        return true
    }

    private static func mediaKinds(for provider: NSItemProvider) -> Set<MediaKind> {
        var result = Set<MediaKind>()

        if videoTypes.contains(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
            result.insert(.video)
        }

        if audioTypes.contains(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
            result.insert(.audio)
        }

        return result
    }

    private static func loadURL(
        from provider: NSItemProvider,
        typeIdentifiers: [String],
        index: Int = 0,
        completion: @escaping (URL?) -> Void
    ) {
        guard index < typeIdentifiers.count else {
            completion(nil)
            return
        }

        provider.loadItem(forTypeIdentifier: typeIdentifiers[index], options: nil) { item, _ in
            if let url = extractURL(from: item) {
                completion(url)
            } else {
                loadURL(from: provider, typeIdentifiers: typeIdentifiers, index: index + 1, completion: completion)
            }
        }
    }

    private static func extractURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let url = item as? NSURL {
            return url as URL
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            if let url = URL(string: string), url.scheme != nil {
                return url
            }
            return URL(fileURLWithPath: string)
        }

        return nil
    }
}

/// ファイルドロップゾーン
struct FileDropZone: View {
    let title: String
    let icon: String
    let acceptedTypes: [UTType]
    let file: MediaFile?
    let isTargeted: Bool
    let onDrop: (URL) -> Void
    let onFrameChange: (CGRect) -> Void

    init(
        title: String,
        icon: String,
        acceptedTypes: [UTType],
        file: MediaFile?,
        isTargeted: Bool = false,
        onDrop: @escaping (URL) -> Void,
        onFrameChange: @escaping (CGRect) -> Void = { _ in }
    ) {
        self.title = title
        self.icon = icon
        self.acceptedTypes = acceptedTypes
        self.file = file
        self.isTargeted = isTargeted
        self.onDrop = onDrop
        self.onFrameChange = onFrameChange
    }

    var body: some View {
        VStack(spacing: 6) {
            if let file = file {
                // ファイルが設定されている場合
                fileInfoView(file)
            } else {
                // ドロップ待ち
                dropPromptView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: file == nil ? 70 : 60)
        .padding(10)
        .background(
            ZStack {
                // ベース背景
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))

                // グラデーションオーバーレイ（ターゲット時）
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.15),
                                    Color.accentColor.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ?
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [Color.secondary.opacity(0.2), Color.secondary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    style: StrokeStyle(
                        lineWidth: isTargeted ? 2 : 1,
                        dash: file == nil ? [8, 4] : []
                    )
                )
        )
        .shadow(color: isTargeted ? Color.accentColor.opacity(0.2) : Color.black.opacity(0.03),
                radius: isTargeted ? 8 : 4,
                x: 0,
                y: isTargeted ? 3 : 1)
        .scaleEffect(isTargeted ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
        .background(frameReader)
    }

    /// ドロップ待ち表示
    private var dropPromptView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.15),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text("ドラッグ&ドロップ")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                selectFile()
            }) {
                Text("選択")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.1))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    /// ファイル情報表示
    private func fileInfoView(_ file: MediaFile) -> some View {
        HStack(spacing: 10) {
            // アイコン
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.15),
                                Color.accentColor.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: file.isVideo ? "film.fill" : "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            // ファイル情報
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !file.summary.isEmpty {
                    Text(file.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            // 削除ボタン
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    // file:// スキームのみのURLを使用（pathが空文字になる）
                    onDrop(URL(string: "file://")!)
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 24, height: 24)

                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var frameReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    reportFrame(proxy.frame(in: .named(DropAnimationCoordinateSpace.name)))
                }
                .onChange(of: proxy.frame(in: .named(DropAnimationCoordinateSpace.name))) { frame in
                    reportFrame(frame)
                }
        }
    }

    private func reportFrame(_ frame: CGRect) {
        guard !frame.isEmpty else { return }
        onFrameChange(frame)
    }

    /// ファイル選択ダイアログ
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = acceptedTypes

        if panel.runModal() == .OK, let url = panel.url {
            onDrop(url)
        }
    }
}

/// 動画ドロップゾーン
struct VideoDropZone: View {
    let file: MediaFile?
    let isTargeted: Bool
    let onDrop: (URL) -> Void
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        FileDropZone(
            title: "動画ファイル",
            icon: "film.circle.fill",
            acceptedTypes: FileDropSupport.videoTypes,
            file: file,
            isTargeted: isTargeted,
            onDrop: onDrop,
            onFrameChange: onFrameChange
        )
    }
}

/// 音声ドロップゾーン
struct AudioDropZone: View {
    let file: MediaFile?
    let isTargeted: Bool
    let onDrop: (URL) -> Void
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        FileDropZone(
            title: "音声ファイル",
            icon: "waveform.circle.fill",
            acceptedTypes: FileDropSupport.audioTypes,
            file: file,
            isTargeted: isTargeted,
            onDrop: onDrop,
            onFrameChange: onFrameChange
        )
    }
}

#Preview {
    VStack {
        VideoDropZone(file: nil, isTargeted: false, onDrop: { _ in }, onFrameChange: { _ in })
        AudioDropZone(file: nil, isTargeted: false, onDrop: { _ in }, onFrameChange: { _ in })
    }
    .padding()
    .coordinateSpace(name: DropAnimationCoordinateSpace.name)
    .frame(width: 300)
}
