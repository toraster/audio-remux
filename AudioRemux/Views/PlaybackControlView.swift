import SwiftUI

/// 再生コントロールビュー
struct PlaybackControlView: View {
    @ObservedObject var playbackService: AudioPlaybackService
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 再生/一時停止ボタン
            Button(action: {
                playbackService.togglePlayPause()
            }) {
                Image(systemName: playbackService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                    )
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.5)

            // 停止ボタン
            Button(action: {
                playbackService.stop()
            }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                Circle()
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.5)

            // 区切り線
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1, height: 20)

            // モード選択
            Picker("", selection: $playbackService.playbackMode) {
                ForEach(PlaybackMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1.0 : 0.5)

            Spacer()

            // 時間表示
            HStack(spacing: 4) {
                Text(formatTime(playbackService.currentTime))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                Text("/")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(formatTime(playbackService.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    PlaybackControlView(
        playbackService: AudioPlaybackService(),
        isEnabled: true
    )
    .padding()
    .frame(width: 500)
}
