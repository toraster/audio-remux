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
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 8) {
            if let file = file {
                // ファイルが設定されている場合
                fileInfoView(file)
            } else {
                // ドロップ待ち
                dropPromptView
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .padding(12)
        .background(
            ZStack {
                // ベース背景
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))

                // グラデーションオーバーレイ（ターゲット時）
                if isTargeted {
                    RoundedRectangle(cornerRadius: 16)
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
            RoundedRectangle(cornerRadius: 16)
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
                        lineWidth: isTargeted ? 2.5 : 1.5,
                        dash: file == nil ? [12, 6] : []
                    )
                )
        )
        .shadow(color: isTargeted ? Color.accentColor.opacity(0.2) : Color.black.opacity(0.05),
                radius: isTargeted ? 12 : 6,
                x: 0,
                y: isTargeted ? 4 : 2)
        .scaleEffect(isTargeted ? 1.02 : (isHovered ? 1.01 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    /// ドロップ待ち表示
    private var dropPromptView: some View {
        VStack(spacing: 6) {
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
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text("ドラッグ&ドロップ または")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Button(action: {
                selectFile()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("ファイルを選択")
                        .font(.system(size: 11, weight: .semibold))
                }
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
                RoundedRectangle(cornerRadius: 10)
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
                    .frame(width: 44, height: 44)

                Image(systemName: file.isVideo ? "film.fill" : "waveform")
                    .font(.system(size: 20, weight: .semibold))
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
                        .lineLimit(1)
                }
            }

            Spacer()

            // 削除ボタン
            Button(action: {
                showDeleteConfirmation = true
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
        .alert("ファイルを削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("キャンセル", role: .cancel) { }
            Button("削除", role: .destructive) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onDrop(URL(fileURLWithPath: ""))
                }
            }
        } message: {
            Text("\(file.fileName) を削除します。")
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
