import Foundation
import Combine

/// 同期分析ビューモデル
@MainActor
class SyncAnalyzerViewModel: ObservableObject {
    @Published var syncState: SyncAnalysisState = .idle
    @Published var videoWaveform: WaveformData?
    @Published var audioWaveform: WaveformData?
    @Published var lastResult: SyncAnalysisResult?

    private let ffmpeg = FFmpegService.shared
    private let waveformGenerator = WaveformGenerator.shared
    private let audioAnalyzer = AudioAnalyzer.shared

    /// 現在実行中のタスク
    private var currentTask: Task<Void, Never>?

    /// 波形データを生成
    /// - Parameters:
    ///   - videoURL: 動画ファイルのURL
    ///   - audioURL: 音声ファイルのURL
    func generateWaveforms(videoURL: URL, audioURL: URL) async {
        // 前のタスクをキャンセル
        currentTask?.cancel()

        // ファイル存在チェック
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("[SyncAnalyzer] Error: Video file does not exist")
            syncState = .error("動画ファイルが見つかりません")
            return
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("[SyncAnalyzer] Error: Audio file does not exist")
            syncState = .error("音声ファイルが見つかりません")
            return
        }

        // 処理中の場合は強制リセットしてから開始（スタック防止）
        if syncState.isProcessing {
            print("[SyncAnalyzer] Warning: Previous process was stuck, resetting state")
            syncState = .idle
        }

        syncState = .extractingAudio
        print("[SyncAnalyzer] Starting audio extraction...")
        print("[SyncAnalyzer] Video: \(videoURL.path)")
        print("[SyncAnalyzer] Audio: \(audioURL.path)")

        // 一時ファイルのパス（関数スコープで保持）
        let tempDir = FileManager.default.temporaryDirectory
        let videoAudioURL = tempDir.appendingPathComponent("video_audio_\(UUID().uuidString).wav")
        let audioWavURL = tempDir.appendingPathComponent("audio_\(UUID().uuidString).wav")

        // 最終的に一時ファイルを削除
        defer {
            try? FileManager.default.removeItem(at: videoAudioURL)
            try? FileManager.default.removeItem(at: audioWavURL)
            print("[SyncAnalyzer] Cleaned up temp files")
        }

        do {
            // 動画から音声を抽出
            print("[SyncAnalyzer] Extracting audio from video...")
            try await ffmpeg.extractAudio(from: videoURL, to: videoAudioURL)
            print("[SyncAnalyzer] Video audio extraction completed")

            // 音声ファイルをWAVに変換
            print("[SyncAnalyzer] Converting audio to WAV...")
            try await ffmpeg.convertToWav(from: audioURL, to: audioWavURL)
            print("[SyncAnalyzer] Audio conversion completed")

            syncState = .generatingWaveform
            print("[SyncAnalyzer] Generating waveforms...")

            // 波形データを生成
            async let videoWaveformTask = waveformGenerator.generateWaveform(from: videoAudioURL)
            async let audioWaveformTask = waveformGenerator.generateWaveform(from: audioWavURL)

            let (videoWf, audioWf) = try await (videoWaveformTask, audioWaveformTask)

            videoWaveform = videoWf
            audioWaveform = audioWf
            syncState = .idle
            print("[SyncAnalyzer] Waveform generation completed successfully")

        } catch is CancellationError {
            print("[SyncAnalyzer] Operation was cancelled")
            syncState = .error("処理がキャンセルされました")
        } catch {
            print("[SyncAnalyzer] Error: \(error.localizedDescription)")
            syncState = .error(error.localizedDescription)
        }
    }

    /// 自動同期分析を実行
    func analyzeSync() async {
        guard let videoWf = videoWaveform, let audioWf = audioWaveform else {
            syncState = .error("波形データが生成されていません")
            return
        }

        syncState = .analyzing

        do {
            let result = try await audioAnalyzer.findSyncOffset(
                reference: videoWf,
                target: audioWf
            )

            lastResult = result
            syncState = .completed(result)

        } catch {
            syncState = .error(error.localizedDescription)
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

        syncState = .idle
        videoWaveform = nil
        audioWaveform = nil
        lastResult = nil
    }
}
