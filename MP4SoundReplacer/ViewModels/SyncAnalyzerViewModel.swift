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

    /// 波形データを生成
    /// - Parameters:
    ///   - videoURL: 動画ファイルのURL
    ///   - audioURL: 音声ファイルのURL
    func generateWaveforms(videoURL: URL, audioURL: URL) async {
        syncState = .extractingAudio

        do {
            // 一時ファイルのパス
            let tempDir = FileManager.default.temporaryDirectory
            let videoAudioURL = tempDir.appendingPathComponent("video_audio_\(UUID().uuidString).wav")
            let audioWavURL = tempDir.appendingPathComponent("audio_\(UUID().uuidString).wav")

            defer {
                // 一時ファイルの削除
                try? FileManager.default.removeItem(at: videoAudioURL)
                try? FileManager.default.removeItem(at: audioWavURL)
            }

            // 動画から音声を抽出
            try await ffmpeg.extractAudio(from: videoURL, to: videoAudioURL)

            // 音声ファイルをWAVに変換（必要な場合）
            if audioURL.pathExtension.lowercased() == "wav" {
                // すでにWAVの場合もモノラル化のため変換
                try await ffmpeg.convertToWav(from: audioURL, to: audioWavURL)
            } else {
                try await ffmpeg.convertToWav(from: audioURL, to: audioWavURL)
            }

            syncState = .generatingWaveform

            // 波形データを生成
            async let videoWaveformTask = waveformGenerator.generateWaveform(from: videoAudioURL)
            async let audioWaveformTask = waveformGenerator.generateWaveform(from: audioWavURL)

            let (videoWf, audioWf) = try await (videoWaveformTask, audioWaveformTask)

            videoWaveform = videoWf
            audioWaveform = audioWf
            syncState = .idle

        } catch {
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
        syncState = .idle
        videoWaveform = nil
        audioWaveform = nil
        lastResult = nil
    }
}
