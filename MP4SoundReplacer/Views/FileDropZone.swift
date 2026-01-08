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

    var body: some View {
        VStack(spacing: 12) {
            if let file = file {
                // ファイルが設定されている場合
                fileInfoView(file)
            } else {
                // ドロップ待ち
                dropPromptView
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.gray.opacity(0.3),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: file == nil ? [8] : [])
                )
        )
        .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    /// ドロップ待ち表示
    private var dropPromptView: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text(title)
                .font(.headline)

            Text("ドラッグ&ドロップ")
                .font(.callout)
                .foregroundColor(.secondary)

            Button("ファイルを選択...") {
                selectFile()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    /// ファイル情報表示
    private func fileInfoView(_ file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: file.isVideo ? "film" : "waveform")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                Text(file.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(action: { onDrop(URL(fileURLWithPath: "")) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if !file.summary.isEmpty {
                Text(file.summary)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
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
            acceptedTypes: [.mpeg4Movie, .quickTimeMovie],
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
            acceptedTypes: [.wav, .aiff],
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
    .frame(width: 400)
}
