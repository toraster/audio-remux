import SwiftUI
import UniformTypeIdentifiers

/// ファイルドロップゾーン
struct FileDropZone: View {
    let title: String
    let icon: String
    let acceptedTypes: [UTType]
    let file: MediaFile?
    let onDrop: (URL) -> Void

    @State private var isTargeted = false
    @State private var isHovered = false

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
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
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

    /// ドロップハンドラ
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        for type in acceptedTypes {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            onDrop(url)
                        }
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            onDrop(url)
                        }
                    }
                }
                return true
            }
        }
        return false
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
    let onDrop: (URL) -> Void

    var body: some View {
        FileDropZone(
            title: "動画ファイル",
            icon: "film.circle.fill",
            acceptedTypes: [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video")!],
            file: file,
            onDrop: onDrop
        )
    }
}

/// 音声ドロップゾーン
struct AudioDropZone: View {
    let file: MediaFile?
    let onDrop: (URL) -> Void

    var body: some View {
        FileDropZone(
            title: "音声ファイル",
            icon: "waveform.circle.fill",
            acceptedTypes: [.wav, .aiff, UTType(filenameExtension: "flac")!],
            file: file,
            onDrop: onDrop
        )
    }
}

#Preview {
    VStack {
        VideoDropZone(file: nil) { _ in }
        AudioDropZone(file: nil) { _ in }
    }
    .padding()
    .frame(width: 300)
}
