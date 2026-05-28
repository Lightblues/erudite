import Foundation
import os

// MARK: - Erudite Logging System
//
// Unified logging with multiple sinks:
// 1. os.Logger — system log (Console.app, filtered by category)
// 2. FileLogger — ~/Library/Logs/Erudite/ (daily rotation, exportable)
// 3. DebugLog buffer — in-memory ring buffer for in-app debug panel
//
// Usage:
//   Log.ai.info("Stream started: model=\(model)")
//   Log.ai.error("API error", error: error)
//   Log.memory.debug("Extracted \(count) observations")
//   Log.db.warning("Slow query: \(ms)ms")

// MARK: - Log Categories

enum Log {
    static let ai = ELogger(category: "AI")
    static let memory = ELogger(category: "Memory")
    static let db = ELogger(category: "Database")
    static let app = ELogger(category: "App")
    static let ui = ELogger(category: "UI")
}

// MARK: - Log Level

enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var symbol: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let error: String?
    let metadata: [String: String]?

    var formatted: String {
        let ts = Self.formatter.string(from: timestamp)
        let err = error.map { " | \($0)" } ?? ""
        let meta = metadata.map { dict in
            " | " + dict.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        } ?? ""
        return "\(ts) [\(level.label)] [\(category)] \(message)\(err)\(meta)"
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

// MARK: - ELogger (per-category logger)

final class ELogger: @unchecked Sendable {
    let category: String
    private let osLogger: os.Logger

    init(category: String) {
        self.category = category
        self.osLogger = os.Logger(subsystem: "com.erudite.app", category: category)
    }

    func debug(_ message: String, metadata: [String: String]? = nil) {
        log(level: .debug, message: message, metadata: metadata)
    }

    func info(_ message: String, metadata: [String: String]? = nil) {
        log(level: .info, message: message, metadata: metadata)
    }

    func warning(_ message: String, metadata: [String: String]? = nil) {
        log(level: .warning, message: message, metadata: metadata)
    }

    func error(_ message: String, error: Error? = nil, metadata: [String: String]? = nil) {
        log(level: .error, message: message, error: error, metadata: metadata)
    }

    private func log(level: LogLevel, message: String, error: Error? = nil, metadata: [String: String]? = nil) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            error: error?.localizedDescription,
            metadata: metadata
        )

        // 1. os.Logger (always)
        let osMsg = entry.formatted
        switch level {
        case .debug: osLogger.debug("\(osMsg)")
        case .info: osLogger.info("\(osMsg)")
        case .warning: osLogger.warning("\(osMsg)")
        case .error: osLogger.error("\(osMsg)")
        }

        // 2. In-memory buffer (for debug panel)
        DebugLog.shared.append(entry)

        // 3. File logger (info+ only)
        if level >= .info {
            FileLogger.shared.write(entry)
        }
    }
}

// MARK: - Debug Log (in-memory ring buffer)

@Observable
final class DebugLog {
    static let shared = DebugLog()

    private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    private init() {}

    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func filtered(category: String? = nil, level: LogLevel = .debug) -> [LogEntry] {
        entries.filter { entry in
            entry.level >= level &&
            (category == nil || entry.category == category)
        }
    }
}

// MARK: - File Logger

final class FileLogger: @unchecked Sendable {
    static let shared = FileLogger()

    private let logDirectory: URL
    private let queue = DispatchQueue(label: "com.erudite.filelogger", qos: .utility)
    private var fileHandle: FileHandle?
    private var currentDate: String = ""

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logDirectory = appSupport.appendingPathComponent("Erudite/Logs", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            print("[FileLogger] Failed to create log directory: \(logDirectory.path) — \(error)")
        }
        rotateIfNeeded()
        print("[FileLogger] Initialized at: \(logDirectory.path)")
    }

    func write(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            self.rotateIfNeeded()
            guard let handle = self.fileHandle else { return }

            let line = entry.formatted + "\n"
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        }
    }

    /// Get path to current log file (for export)
    var currentLogPath: URL {
        logDirectory.appendingPathComponent("erudite-\(todayString()).log")
    }

    /// List all log files
    var logFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }) ?? []
    }

    private func rotateIfNeeded() {
        let today = todayString()
        guard today != currentDate else { return }

        fileHandle?.closeFile()
        currentDate = today
        let filePath = logDirectory.appendingPathComponent("erudite-\(today).log")

        if !FileManager.default.fileExists(atPath: filePath.path) {
            let created = FileManager.default.createFile(atPath: filePath.path, contents: nil)
            if !created {
                print("[FileLogger] Failed to create log file at: \(filePath.path)")
            }
        }

        do {
            fileHandle = try FileHandle(forWritingTo: filePath)
            fileHandle?.seekToEndOfFile()
        } catch {
            print("[FileLogger] Failed to open log file: \(error)")
            fileHandle = nil
        }

        // Clean up old logs (keep 7 days)
        cleanOldLogs()
    }

    private func cleanOldLogs() {
        let files = logFiles
        if files.count > 7 {
            for file in files.dropFirst(7) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
