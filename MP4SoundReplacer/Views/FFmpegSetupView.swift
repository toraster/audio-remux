import SwiftUI

/// FFmpegセットアップ画面
struct FFmpegSetupView: View {
    @StateObject private var downloadService = FFmpegDownloadService.shared
    @Binding var isFFmpegAvailable: Bool

    var body: some View {
        VStack(spacing: 24) {
            // アイコン
            iconView

            // タイトル
            Text("FFmpegのセットアップ")
                .font(.title2.bold())

            // 説明
            Text("音声処理に必要なFFmpegをダウンロードします")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 8)

            // 状態に応じた表示
            stateView

            Spacer()
                .frame(height: 8)

            // 追加情報
            additionalInfo
        }
        .padding(40)
        .frame(width: 450, height: 400)
    }

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch downloadService.state {
        case .idle:
            idleView

        case .checking:
            progressIndicator(message: "確認中...")

        case .downloading(let progress, let fileName):
            downloadingView(progress: progress, fileName: fileName)

        case .extracting:
            progressIndicator(message: "解凍中...")

        case .signing:
            progressIndicator(message: "セットアップを完了中...")

        case .completed:
            completedView

        case .failed(let message):
            failedView(message: message)
        }
    }

    private var idleView: some View {
        VStack(spacing: 16) {
            Button(action: startDownload) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("ダウンロード開始")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("約 80 MB のダウンロードが必要です")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func downloadingView(progress: Double, fileName: String) -> some View {
        VStack(spacing: 12) {
            Text("\(fileName) をダウンロード中...")
                .font(.headline)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 250)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    private func progressIndicator(message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .foregroundColor(.secondary)
        }
    }

    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("セットアップ完了")
                .font(.headline)
                .foregroundColor(.green)

            Button(action: {
                isFFmpegAvailable = true
            }) {
                Text("続ける")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("エラーが発生しました")
                .font(.headline)
                .foregroundColor(.red)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            HStack(spacing: 12) {
                Button("キャンセル") {
                    downloadService.cancel()
                }
                .buttonStyle(.bordered)

                Button("再試行") {
                    startDownload()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var additionalInfo: some View {
        VStack(spacing: 8) {
            Divider()

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("FFmpegは")
                    .foregroundColor(.secondary)
                Link("martin-riedl.de", destination: URL(string: "https://ffmpeg.martin-riedl.de/")!)
                Text("からダウンロードされます")
                    .foregroundColor(.secondary)
            }
            .font(.caption)

            #if arch(arm64)
            Text("アーキテクチャ: Apple Silicon (arm64)")
                .font(.caption2)
                .foregroundColor(.secondary)
            #else
            Text("アーキテクチャ: Intel (x86_64)")
                .font(.caption2)
                .foregroundColor(.secondary)
            #endif
        }
    }

    private func startDownload() {
        Task {
            do {
                try await downloadService.downloadAndInstall()
            } catch {
                print("Download failed: \(error)")
            }
        }
    }
}

#Preview {
    FFmpegSetupView(isFFmpegAvailable: .constant(false))
}
