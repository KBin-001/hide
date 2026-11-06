import Foundation

/// App-owned events. A serial queue preserves ordering and keeps file I/O off the UI
/// and the authorization worker. Each snapshot keeps only the most recent events.
final class DiagnosticLog: @unchecked Sendable {
    static let shared: DiagnosticLog = {
        let files = FileManager.default
        let root = files.urls(for: .cachesDirectory, in: .userDomainMask).first ?? files.temporaryDirectory
        return DiagnosticLog(directory: root.appendingPathComponent("Diagnostics", isDirectory: true))
    }()

    private let queue = DispatchQueue(label: "calculator.diagnostics")
    private let directory: URL
    private let limit: Int
    private let session = String(UUID().uuidString.prefix(8))
    private let timestamp = ISO8601DateFormatter()
    private var lines: [String]?
    private var persistenceFailed = false
    private var journal: URL { directory.appendingPathComponent("authorization.log") }

    init(directory: URL, limit: Int = 300) {
        self.directory = directory
        self.limit = max(1, limit)
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func record(_ message: String) {
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let lane = Thread.isMainThread ? "main" : "worker"
        let safeLine = String(message.prefix(640)).replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        queue.async {
            self.loadIfNeeded()
            let seconds = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), uptime)
            let line = "\(self.timestamp.string(from: now)) uptime=\(seconds) session=\(self.session) lane=\(lane) \(safeLine)"
            self.lines?.append(line)
            self.lines = self.lines.map { Array($0.suffix(self.limit)) }
            do {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                let data = Data(((self.lines ?? []).joined(separator: "\n") + "\n").utf8)
                #if os(iOS)
                try data.write(to: self.journal, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try data.write(to: self.journal, options: .atomic)
                #endif
            } catch { self.persistenceFailed = true }
        }
    }

    func snapshot() async -> Data {
        await withCheckedContinuation { continuation in
            queue.async {
                self.loadIfNeeded()
                let header = "Calculator authorization diagnostics (format 1, UTC timestamps)\n"
                    + "Source: app events and installed executable metadata.\n"
                    + (self.persistenceFailed ? "Some events could not be saved to disk.\n" : "")
                continuation.resume(returning: Data((header + (self.lines ?? []).joined(separator: "\n") + "\n").utf8))
            }
        }
    }

    private func loadIfNeeded() {
        guard lines == nil else { return }
        do {
            let saved = try String(contentsOf: journal, encoding: .utf8)
            lines = Array(saved.split(separator: "\n").suffix(limit).map(String.init))
        } catch {
            if FileManager.default.fileExists(atPath: journal.path) { persistenceFailed = true }
            lines = []
        }
    }
}
