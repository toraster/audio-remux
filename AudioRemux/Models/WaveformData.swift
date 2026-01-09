import Foundation

/// 波形データ
struct WaveformData {
    /// 正規化されたサンプル（-1.0 〜 1.0）
    let samples: [Float]

    /// サンプルレート（Hz）
    let sampleRate: Int

    /// 元の音声の長さ（秒）
    let duration: TimeInterval

    /// サンプル数
    var sampleCount: Int {
        samples.count
    }

    /// 表示用にダウンサンプリングされたサンプルを取得
    /// - Parameter targetCount: 目標サンプル数
    /// - Returns: ダウンサンプリングされたサンプル配列
    func downsampled(to targetCount: Int) -> [Float] {
        guard targetCount > 0, samples.count > targetCount else {
            return samples
        }

        let ratio = Float(samples.count) / Float(targetCount)
        var result = [Float](repeating: 0, count: targetCount)

        for i in 0..<targetCount {
            let startIndex = Int(Float(i) * ratio)
            let endIndex = min(Int(Float(i + 1) * ratio), samples.count)

            // 区間内の最大絶対値を取得（波形のピークを保持）
            var maxAbs: Float = 0
            for j in startIndex..<endIndex {
                let absValue = abs(samples[j])
                if absValue > maxAbs {
                    maxAbs = absValue
                    result[i] = samples[j]
                }
            }
        }

        return result
    }

    /// 指定した時間範囲のサンプルを取得
    /// - Parameters:
    ///   - start: 開始時間（秒）
    ///   - end: 終了時間（秒）
    /// - Returns: 範囲内のサンプル
    func samples(from start: TimeInterval, to end: TimeInterval) -> [Float] {
        let startIndex = max(0, Int(start * Double(sampleRate)))
        let endIndex = min(samples.count, Int(end * Double(sampleRate)))

        guard startIndex < endIndex else { return [] }

        return Array(samples[startIndex..<endIndex])
    }
}
