import Foundation
import Accelerate

/// 音声分析サービスエラー
enum AudioAnalyzerError: LocalizedError {
    case insufficientData
    case analysisTimeout
    case calculationFailed

    var errorDescription: String? {
        switch self {
        case .insufficientData:
            return "分析に十分なデータがありません"
        case .analysisTimeout:
            return "分析がタイムアウトしました"
        case .calculationFailed:
            return "計算に失敗しました"
        }
    }
}

/// 音声分析サービス（相互相関計算）
class AudioAnalyzer {
    static let shared = AudioAnalyzer()

    /// 分析ウィンドウの最大長（秒）
    private let maxWindowSeconds: TimeInterval = 30.0

    /// 検索する最大オフセット（秒）
    private let maxOffsetSeconds: TimeInterval = 5.0

    private init() {}

    /// 2つの波形データの同期オフセットを計算
    /// - Parameters:
    ///   - reference: 参照波形（元動画の音声）
    ///   - target: ターゲット波形（置換音声）
    /// - Returns: 同期分析結果
    func findSyncOffset(
        reference: WaveformData,
        target: WaveformData
    ) async throws -> SyncAnalysisResult {
        // サンプルレートは同じ前提（WaveformGeneratorが200Hzにダウンサンプリング）
        let sampleRate = reference.sampleRate

        // 分析ウィンドウのサンプル数
        let windowSamples = min(
            Int(maxWindowSeconds * Double(sampleRate)),
            min(reference.sampleCount, target.sampleCount)
        )

        guard windowSamples > 0 else {
            throw AudioAnalyzerError.insufficientData
        }

        // 検索範囲のサンプル数
        let maxLag = Int(maxOffsetSeconds * Double(sampleRate))

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.crossCorrelation(
                        reference: Array(reference.samples.prefix(windowSamples)),
                        target: Array(target.samples.prefix(windowSamples)),
                        maxLag: maxLag,
                        sampleRate: sampleRate,
                        windowSeconds: Double(windowSamples) / Double(sampleRate)
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// サブサンプル精度のピーク位置を放物線補間で計算
    /// - Parameters:
    ///   - correlations: 相関値の配列
    ///   - peakIndex: 最大相関のインデックス
    /// - Returns: 補間されたピーク位置（サブサンプル精度）
    private func parabolicInterpolation(
        correlations: [Float],
        peakIndex: Int
    ) -> Double {
        // 境界チェック（補間に3点必要）
        guard peakIndex > 0 && peakIndex < correlations.count - 1 else {
            return Double(peakIndex)
        }

        let y0 = Double(correlations[peakIndex - 1])
        let y1 = Double(correlations[peakIndex])
        let y2 = Double(correlations[peakIndex + 1])

        // 放物線の頂点: δ = (y0 - y2) / (2 * (y0 - 2*y1 + y2))
        let denominator = 2.0 * (y0 - 2.0 * y1 + y2)

        // 数値安定性のチェック
        guard abs(denominator) > 1e-10 else {
            return Double(peakIndex)
        }

        let delta = (y0 - y2) / denominator

        // 補間値が妥当な範囲内か確認（-0.5 < delta < 0.5）
        let clampedDelta = max(-0.5, min(0.5, delta))

        return Double(peakIndex) + clampedDelta
    }

    /// 相互相関を計算してオフセットを検出
    private func crossCorrelation(
        reference: [Float],
        target: [Float],
        maxLag: Int,
        sampleRate: Int,
        windowSeconds: Double
    ) throws -> SyncAnalysisResult {
        let n = reference.count
        guard n > 0, target.count > 0 else {
            throw AudioAnalyzerError.insufficientData
        }

        // 相関値を格納する配列（-maxLag から +maxLag）
        let correlationSize = 2 * maxLag + 1
        var correlations = [Float](repeating: 0, count: correlationSize)

        // 参照信号の分散を計算
        var refMean: Float = 0
        vDSP_meanv(reference, 1, &refMean, vDSP_Length(n))

        var refCentered = [Float](repeating: 0, count: n)
        var negRefMean = -refMean
        vDSP_vsadd(reference, 1, &negRefMean, &refCentered, 1, vDSP_Length(n))

        var refVariance: Float = 0
        vDSP_dotpr(refCentered, 1, refCentered, 1, &refVariance, vDSP_Length(n))

        // 各ラグでの相関を計算
        for lagIndex in 0..<correlationSize {
            let lag = lagIndex - maxLag

            // オーバーラップ区間を計算
            let refStart = max(0, lag)
            let targetStart = max(0, -lag)
            let overlapLength = min(n - refStart, target.count - targetStart)

            guard overlapLength > 0 else { continue }

            // ターゲット区間を取得
            let targetSlice = Array(target[targetStart..<(targetStart + overlapLength)])

            // ターゲットの平均を計算
            var targetMean: Float = 0
            vDSP_meanv(targetSlice, 1, &targetMean, vDSP_Length(overlapLength))

            // ターゲットを中心化
            var targetCentered = [Float](repeating: 0, count: overlapLength)
            var negTargetMean = -targetMean
            vDSP_vsadd(targetSlice, 1, &negTargetMean, &targetCentered, 1, vDSP_Length(overlapLength))

            // ターゲットの分散を計算
            var targetVariance: Float = 0
            vDSP_dotpr(targetCentered, 1, targetCentered, 1, &targetVariance, vDSP_Length(overlapLength))

            // 参照区間を取得して中心化
            let refSlice = Array(refCentered[refStart..<(refStart + overlapLength)])

            // 正規化相互相関を計算
            var dotProduct: Float = 0
            vDSP_dotpr(refSlice, 1, targetCentered, 1, &dotProduct, vDSP_Length(overlapLength))

            let denominator = sqrt(refVariance * targetVariance)
            if denominator > 0 {
                correlations[lagIndex] = dotProduct / denominator
            }
        }

        // 最大相関を見つける
        var maxCorrelation: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(correlations, 1, &maxCorrelation, &maxIndex, vDSP_Length(correlationSize))

        // サブサンプル精度で補間
        let refinedIndex = parabolicInterpolation(
            correlations: correlations,
            peakIndex: Int(maxIndex)
        )

        let bestLag = refinedIndex - Double(maxLag)
        let offsetSeconds = bestLag / Double(sampleRate)

        // 信頼度を0-1に正規化（相関係数は-1〜1の範囲）
        let confidence = Double(max(0, maxCorrelation))

        return SyncAnalysisResult(
            detectedOffset: offsetSeconds,
            confidence: confidence,
            analyzedRange: 0...windowSeconds
        )
    }
}
