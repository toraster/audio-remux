import Foundation
import Combine

/// 同期分析ビューモデル
@MainActor
class SyncAnalyzerViewModel: ObservableObject {
    @Published var syncState: SyncAnalysisState = .idle
    @Published var videoWaveform: WaveformData?
    @Published var audioWaveform: WaveformData?
    @Published var lastResult: SyncAnalysisResult?

    /// 抽出した元動画の音声ファイルURL（再生用に保持）
    @Published private(set) var extractedVideoAudioURL: URL?
    /// 変換した置換音声ファイルURL（再生用に保持）
    @Published private(set) var extractedReplacementAudioURL: URL?

    private let ffmpeg = FFmpegService.shared
    private let waveformGenerator = WaveformGenerator.shared
    private let audioAnalyzer = AudioAnalyzer.shared

    /// 現在実行中のタスク
    private var currentTask: Task<Void, Never>?

    /// 波形データを生成
    /// - Parameters:
    ///   - videoURL: 動画ファイルのURL
    ///   - audioURL: 音声ファイルのURL
    /// - Returns: 成功した場合true、失敗またはキャンセルの場合false
    @discardableResult
    func generateWaveforms(videoURL: URL, audioURL: URL) async -> Bool {
        // 前のタスクをキャンセル
        currentTask?.cancel()

        // ファイル存在チェック
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            Logger.error("Video file does not exist", category: .syncAnalyzer)
            syncState = .error("動画ファイルが見つかりません")
            return false
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Logger.error("Audio file does not exist", category: .syncAnalyzer)
            syncState = .error("音声ファイルが見つかりません")
            return false
        }

        // 処理中の場合は強制リセットしてから開始（スタック防止）
        if syncState.isProcessing {
            Logger.warning("Previous process was stuck, resetting state", category: .syncAnalyzer)
            syncState = .idle
        }

        syncState = .extractingAudio
        Logger.debug("Starting audio extraction...", category: .syncAnalyzer)
        Logger.debug("Video: \(videoURL.path)", category: .syncAnalyzer)
        Logger.debug("Audio: \(audioURL.path)", category: .syncAnalyzer)

        // 以前の一時ファイルを削除
        cleanupTempFiles()

        // 一時ファイルのパス（関数スコープで保持）
        let tempDir = FileManager.default.temporaryDirectory
        let videoAudioURL = tempDir.appendingPathComponent("video_audio_\(UUID().uuidString).wav")
        let audioWavURL = tempDir.appendingPathComponent("audio_\(UUID().uuidString).wav")

        do {
            // 動画から音声を抽出
            Logger.debug("Extracting audio from video...", category: .syncAnalyzer)
            try await ffmpeg.extractAudio(from: videoURL, to: videoAudioURL)
            Logger.debug("Video audio extraction completed", category: .syncAnalyzer)

            // 音声ファイルをWAVに変換
            Logger.debug("Converting audio to WAV...", category: .syncAnalyzer)
            try await ffmpeg.convertToWav(from: audioURL, to: audioWavURL)
            Logger.debug("Audio conversion completed", category: .syncAnalyzer)

            syncState = .generatingWaveform
            Logger.debug("Generating waveforms...", category: .syncAnalyzer)

            // 波形データを生成
            async let videoWaveformTask = waveformGenerator.generateWaveform(from: videoAudioURL)
            async let audioWaveformTask = waveformGenerator.generateWaveform(from: audioWavURL)

            let (videoWf, audioWf) = try await (videoWaveformTask, audioWaveformTask)

            videoWaveform = videoWf
            audioWaveform = audioWf

            // 再生用に一時ファイルURLを保持
            extractedVideoAudioURL = videoAudioURL
            extractedReplacementAudioURL = audioWavURL

            syncState = .idle
            Logger.info("Waveform generation completed successfully", category: .syncAnalyzer)
            return true

        } catch is CancellationError {
            // エラー時は一時ファイルを削除
            try? FileManager.default.removeItem(at: videoAudioURL)
            try? FileManager.default.removeItem(at: audioWavURL)
            Logger.debug("Operation was cancelled", category: .syncAnalyzer)
            syncState = .error("処理がキャンセルされました")
            return false
        } catch {
            // エラー時は一時ファイルを削除
            try? FileManager.default.removeItem(at: videoAudioURL)
            try? FileManager.default.removeItem(at: audioWavURL)
            Logger.error("Error: \(error.localizedDescription)", category: .syncAnalyzer)
            syncState = .error(error.localizedDescription)
            return false
        }
    }

    /// 自動同期分析を実行
    /// - Returns: 成功した場合SyncAnalysisResult、失敗の場合nil
    @discardableResult
    func analyzeSync() async -> SyncAnalysisResult? {
        guard let videoWf = videoWaveform, let audioWf = audioWaveform else {
            syncState = .error("波形データが生成されていません")
            return nil
        }

        syncState = .analyzing

        do {
            let result = try await audioAnalyzer.findSyncOffset(
                reference: videoWf,
                target: audioWf
            )

            lastResult = result
            syncState = .completed(result)
            return result

        } catch {
            syncState = .error(error.localizedDescription)
            return nil
        }
    }

    /// 波形生成と自動同期を連続実行
    func generateWaveformsAndAnalyze(videoURL: URL, audioURL: URL) async {
        await generateWaveforms(videoURL: videoURL, audioURL: audioURL)

        // 波形生成が成功した場合のみ分析を実行
        if videoWaveform != nil && audioWaveform != nil {
            await analyzeSync()
        }
    }

    /// リセット
    func reset() {
        // 進行中のタスクをキャンセル
        currentTask?.cancel()
        currentTask = nil

        // 一時ファイルを削除
        cleanupTempFiles()

        syncState = .idle
        videoWaveform = nil
        audioWaveform = nil
        lastResult = nil
    }

    /// 一時ファイルを削除
    private func cleanupTempFiles() {
        if let url = extractedVideoAudioURL {
            try? FileManager.default.removeItem(at: url)
            extractedVideoAudioURL = nil
            Logger.debug("Cleaned up video audio temp file", category: .syncAnalyzer)
        }
        if let url = extractedReplacementAudioURL {
            try? FileManager.default.removeItem(at: url)
            extractedReplacementAudioURL = nil
            Logger.debug("Cleaned up replacement audio temp file", category: .syncAnalyzer)
        }
    }
}
