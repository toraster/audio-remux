import Foundation

/// FFmpegダウンロードの状態
enum FFmpegDownloadState: Equatable {
    case idle
    case checking
    case downloading(progress: Double, fileName: String)
    case extracting
    case signing
    case completed
    case failed(String)

    var isProcessing: Bool {
        switch self {
        case .checking, .downloading, .extracting, .signing:
            return true
        default:
            return false
        }
    }
}

/// FFmpegダウンロードサービス
/// martin-riedl.de からFFmpegバイナリをダウンロードして設定する
class FFmpegDownloadService: NSObject, ObservableObject {
    static let shared = FFmpegDownloadService()

    @Published var state: FFmpegDownloadState = .idle
    @Published var downloadProgress: Double = 0

    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession!
    private var currentCompletion: ((Result<URL, Error>) -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    /// FFmpegの保存先ディレクトリ
    var binariesDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("MP4SoundReplacer")
            .appendingPathComponent("bin")
    }

    /// 現在のアーキテクチャを検出
    private var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    /// FFmpegダウンロードURL
    private func downloadURL(for binary: String) -> URL {
        URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(currentArchitecture)/release/\(binary).zip")!
    }

    /// ダウンロード済みFFmpegパス
    var ffmpegPath: URL {
        binariesDirectory.appendingPathComponent("ffmpeg")
    }

    /// ダウンロード済みFFprobeパス
    var ffprobePath: URL {
        binariesDirectory.appendingPathComponent("ffprobe")
    }

    /// FFmpegが利用可能かチェック
    func isFFmpegAvailable() -> Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: ffmpegPath.path) &&
               fm.isExecutableFile(atPath: ffprobePath.path)
    }

    /// FFmpegをダウンロード・インストール
    @MainActor
    func downloadAndInstall() async throws {
        guard !state.isProcessing else { return }

        state = .checking
        let fm = FileManager.default

        do {
            // ディレクトリ作成
            try fm.createDirectory(at: binariesDirectory, withIntermediateDirectories: true)

            // ffmpegとffprobeをダウンロード
            for binary in ["ffmpeg", "ffprobe"] {
                state = .downloading(progress: 0, fileName: binary)
                downloadProgress = 0

                let url = downloadURL(for: binary)
                let zipPath = binariesDirectory.appendingPathComponent("\(binary).zip")
                let binaryPath = binariesDirectory.appendingPathComponent(binary)

                // 既存ファイルを削除
                try? fm.removeItem(at: zipPath)
                try? fm.removeItem(at: binaryPath)

                // ダウンロード
                print("[FFmpegDownload] Downloading \(binary) from \(url)")
                let downloadedURL = try await downloadFile(from: url)

                // ダウンロードしたファイルを移動
                try fm.moveItem(at: downloadedURL, to: zipPath)

                // 解凍
                state = .extracting
                print("[FFmpegDownload] Extracting \(binary)...")
                try await extractZip(zipPath, to: binariesDirectory)

                // ZIPファイル削除
                try? fm.removeItem(at: zipPath)
            }

            // コード署名
            state = .signing
            print("[FFmpegDownload] Signing binaries...")
            try await signBinaries()

            state = .completed
            print("[FFmpegDownload] Installation completed successfully")

        } catch {
            print("[FFmpegDownload] Error: \(error)")
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    /// ファイルをダウンロード
    private func downloadFile(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            currentCompletion = { result in
                continuation.resume(with: result)
            }
            downloadTask = session.downloadTask(with: url)
            downloadTask?.resume()
        }
    }

    /// ZIPを解凍
    private func extractZip(_ zipPath: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", zipPath.path, "-d", destination.path]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: FFmpegDownloadError.extractionFailed)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// バイナリにad-hoc署名
    private func signBinaries() async throws {
        for path in [ffmpegPath, ffprobePath] {
            // quarantine属性をSwift APIで削除
            removeQuarantineAttribute(from: path)

            // 実行権限をSwift APIで設定
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: path.path
            )

            // ad-hoc署名
            try await runProcess("/usr/bin/codesign", arguments: ["-s", "-", "-f", path.path])
        }
    }

    /// quarantine属性を削除
    private func removeQuarantineAttribute(from url: URL) {
        let attributes = ["com.apple.quarantine", "com.apple.provenance"]
        for attr in attributes {
            _ = url.withUnsafeFileSystemRepresentation { fileSystemPath in
                if let path = fileSystemPath {
                    removexattr(path, attr, 0)
                }
            }
        }
    }

    /// プロセスを実行
    private func runProcess(_ executablePath: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// ダウンロードをキャンセル
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }
}

// MARK: - URLSessionDownloadDelegate

extension FFmpegDownloadService: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 一時ファイルを安全な場所にコピー
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        do {
            try FileManager.default.copyItem(at: location, to: tempURL)
            currentCompletion?(.success(tempURL))
        } catch {
            currentCompletion?(.failure(error))
        }
        currentCompletion = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        DispatchQueue.main.async {
            self.downloadProgress = progress
            if case .downloading(_, let fileName) = self.state {
                self.state = .downloading(progress: progress, fileName: fileName)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            currentCompletion?(.failure(error))
            currentCompletion = nil
        }
    }
}

// MARK: - Errors

enum FFmpegDownloadError: LocalizedError {
    case downloadFailed
    case extractionFailed
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "ダウンロードに失敗しました"
        case .extractionFailed:
            return "解凍に失敗しました"
        case .signingFailed:
            return "署名に失敗しました"
        }
    }
}
