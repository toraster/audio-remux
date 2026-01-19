import Foundation
import AVFoundation
import Combine

/// 再生モード
enum PlaybackMode: String, CaseIterable {
    case original = "元音声"
    case replacement = "置換音声"
    case both = "両方"
}

/// 音声再生サービス
@MainActor
class AudioPlaybackService: ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var playbackMode: PlaybackMode = .both {
        didSet {
            if isPlaying && oldValue != playbackMode {
                applyModeChange(from: oldValue, to: playbackMode)
            }
        }
    }

    private var originalPlayer: AVAudioPlayer?
    private var replacementPlayer: AVAudioPlayer?
    private var displayLink: CVDisplayLink?
    private var timer: Timer?

    /// オフセット（秒）：正の値は置換音声を遅らせる
    var offsetSeconds: Double = 0

    /// 元音声ファイルのURL
    var originalAudioURL: URL? {
        didSet {
            setupPlayer(for: .original)
        }
    }

    /// 置換音声ファイルのURL
    var replacementAudioURL: URL? {
        didSet {
            setupPlayer(for: .replacement)
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Player Setup

    private func setupPlayer(for type: PlayerType) {
        let url: URL?
        switch type {
        case .original:
            url = originalAudioURL
        case .replacement:
            url = replacementAudioURL
        }

        guard let url = url else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()

            switch type {
            case .original:
                originalPlayer = player
                // durationは元音声の長さを基準とする
                duration = player.duration
            case .replacement:
                replacementPlayer = player
            }
        } catch {
            Logger.error("Failed to setup player: \(error.localizedDescription)", category: .syncAnalyzer)
        }
    }

    // MARK: - Playback Control

    /// 再生開始
    func play() {
        play(from: currentTime)
    }

    /// 指定位置から再生開始
    func play(from time: TimeInterval) {
        stop()

        let startTime = max(0, time)
        currentTime = startTime

        switch playbackMode {
        case .original:
            playOriginal(from: startTime)
        case .replacement:
            playReplacement(from: startTime)
        case .both:
            playBoth(from: startTime)
        }

        isPlaying = true
        startTimer()
    }

    /// 一時停止
    func pause() {
        originalPlayer?.pause()
        replacementPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    /// 停止（先頭に戻る）
    func stop() {
        originalPlayer?.stop()
        replacementPlayer?.stop()
        isPlaying = false
        stopTimer()
    }

    /// シーク
    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        stop()
        currentTime = max(0, min(time, duration))

        if wasPlaying {
            play(from: currentTime)
        }
    }

    /// 再生/一時停止のトグル
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    // MARK: - Dynamic Mode Change

    /// 再生中にモードを変更した場合の処理
    private func applyModeChange(from oldMode: PlaybackMode, to newMode: PlaybackMode) {
        let time = currentTime

        // 両方のプレイヤーを停止
        originalPlayer?.stop()
        replacementPlayer?.stop()

        // 新しいモードで再生を再開（同期を確実に取る）
        switch newMode {
        case .original:
            playOriginal(from: time)
        case .replacement:
            playReplacement(from: time)
        case .both:
            playBoth(from: time)
        }
    }

    // MARK: - Private Playback Methods

    private func playOriginal(from time: TimeInterval) {
        guard let player = originalPlayer else { return }
        player.currentTime = time
        player.play()
    }

    private func playReplacement(from time: TimeInterval) {
        guard let player = replacementPlayer else { return }
        // オフセットを適用：置換音声の再生位置 = 指定時間 - オフセット
        let adjustedTime = time - offsetSeconds
        if adjustedTime >= 0 && adjustedTime < player.duration {
            player.currentTime = adjustedTime
            player.play()
        } else if adjustedTime < 0 {
            // オフセットが正で、まだ再生開始時刻に達していない場合は遅延再生
            scheduleDelayedPlayback(for: player, delay: -adjustedTime)
        }
    }

    private func playBoth(from time: TimeInterval) {
        // 元音声は常に指定位置から再生
        if let original = originalPlayer {
            original.currentTime = time
        }

        // 置換音声はオフセットを適用
        let replacementStartTime = time - offsetSeconds

        if let replacement = replacementPlayer {
            if replacementStartTime >= 0 && replacementStartTime < replacement.duration {
                replacement.currentTime = replacementStartTime
            } else if replacementStartTime < 0 {
                // 遅延再生の場合、一旦先頭に設定
                replacement.currentTime = 0
            }
        }

        // 同時再生開始
        let hostTime = mach_absolute_time()
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        let nanoseconds = Double(hostTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        let currentHostTime = nanoseconds / 1_000_000_000.0
        let playTime = currentHostTime + 0.01

        if let original = originalPlayer {
            original.play(atTime: playTime)
        }

        if let replacement = replacementPlayer, replacementStartTime >= 0 {
            replacement.play(atTime: playTime)
        } else if let replacement = replacementPlayer, replacementStartTime < 0 {
            // 遅延再生
            let delay = -replacementStartTime
            scheduleDelayedPlayback(for: replacement, delay: delay)
        }
    }

    private func scheduleDelayedPlayback(for player: AVAudioPlayer, delay: TimeInterval) {
        player.currentTime = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak player] in
            guard let self = self, let player = player, self.isPlaying else { return }
            player.play()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentTime() {
        // 元音声の再生位置を基準とする
        if let original = originalPlayer, original.isPlaying {
            currentTime = original.currentTime
        } else if let replacement = replacementPlayer, replacement.isPlaying {
            // 置換音声のみの場合はオフセットを考慮
            currentTime = replacement.currentTime + offsetSeconds
        }

        // 再生終了チェック
        if !isAnyPlayerPlaying() && isPlaying {
            isPlaying = false
            stopTimer()
        }
    }

    private func isAnyPlayerPlaying() -> Bool {
        switch playbackMode {
        case .original:
            return originalPlayer?.isPlaying ?? false
        case .replacement:
            return replacementPlayer?.isPlaying ?? false
        case .both:
            return (originalPlayer?.isPlaying ?? false) || (replacementPlayer?.isPlaying ?? false)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stop()
        originalPlayer = nil
        replacementPlayer = nil
        originalAudioURL = nil
        replacementAudioURL = nil
        currentTime = 0
        duration = 0
    }
}

private enum PlayerType {
    case original
    case replacement
}
