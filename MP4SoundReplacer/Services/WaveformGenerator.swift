import Foundation
import AVFoundation

/// 波形生成サービスエラー
enum WaveformError: LocalizedError {
    case fileNotFound
    case invalidAudioFormat
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "音声ファイルが見つかりません"
        case .invalidAudioFormat:
            return "無効な音声形式です"
        case .readFailed(let message):
            return "音声の読み込みに失敗しました: \(message)"
        }
    }
}

/// 波形データ生成サービス
class WaveformGenerator {
    static let shared = WaveformGenerator()

    private init() {}

    /// WAVファイルから波形データを生成
    /// - Parameter url: WAVファイルのURL
    /// - Returns: 波形データ
    func generateWaveform(from url: URL) async throws -> WaveformData {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WaveformError.fileNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.readWavFile(url: url)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// WAVファイルを読み込んでサンプルを抽出
    private func readWavFile(url: URL) throws -> WaveformData {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw WaveformError.invalidAudioFormat
        }

        try file.read(into: buffer)

        guard let floatChannelData = buffer.floatChannelData else {
            throw WaveformError.invalidAudioFormat
        }

        // 最初のチャンネルからサンプルを取得
        let channelData = floatChannelData[0]
        let sampleCount = Int(buffer.frameLength)

        // 表示用にダウンサンプリング（100Hz程度）
        let targetSampleRate = 100
        let originalSampleRate = Int(format.sampleRate)
        let downsampleRatio = max(1, originalSampleRate / targetSampleRate)

        var samples: [Float] = []
        samples.reserveCapacity(sampleCount / downsampleRatio)

        for i in stride(from: 0, to: sampleCount, by: downsampleRatio) {
            // 区間内の最大絶対値を保持
            var maxAbs: Float = 0
            var maxValue: Float = 0
            let endIndex = min(i + downsampleRatio, sampleCount)

            for j in i..<endIndex {
                let value = channelData[j]
                let absValue = abs(value)
                if absValue > maxAbs {
                    maxAbs = absValue
                    maxValue = value
                }
            }
            samples.append(maxValue)
        }

        let duration = Double(sampleCount) / format.sampleRate

        return WaveformData(
            samples: samples,
            sampleRate: targetSampleRate,
            duration: duration
        )
    }
}
