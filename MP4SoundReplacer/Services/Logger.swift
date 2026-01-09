import Foundation
import os

/// ログカテゴリ
enum LogCategory: String {
    case ffmpeg = "FFmpeg"
    case ffprobe = "FFprobe"
    case syncAnalyzer = "SyncAnalyzer"
    case download = "FFmpegDownload"
    case general = "General"
}

/// 構造化ログシステム
enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mp4soundreplacer"

    private static func logger(for category: LogCategory) -> os.Logger {
        os.Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// デバッグログ（DEBUGビルドのみ出力）
    static func debug(_ message: String, category: LogCategory = .general) {
        #if DEBUG
        logger(for: category).debug("\(message, privacy: .public)")
        #endif
    }

    /// 情報ログ
    static func info(_ message: String, category: LogCategory = .general) {
        logger(for: category).info("\(message, privacy: .public)")
    }

    /// 警告ログ
    static func warning(_ message: String, category: LogCategory = .general) {
        logger(for: category).warning("\(message, privacy: .public)")
    }

    /// エラーログ
    static func error(_ message: String, category: LogCategory = .general) {
        logger(for: category).error("\(message, privacy: .public)")
    }
}
