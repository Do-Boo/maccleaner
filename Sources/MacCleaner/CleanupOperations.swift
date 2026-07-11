import AppKit
import Foundation
import UniformTypeIdentifiers

struct TrashUndoSession: Identifiable {
    let id = UUID()
    let action: String
    let moves: [TrashMove]
    let createdAt = Date()
}

@MainActor
final class TrashUndoStore: ObservableObject {
    static let shared = TrashUndoStore()

    @Published private(set) var latest: TrashUndoSession?
    @Published private(set) var isRestoring = false
    @Published var resultMessage: String?

    private init() {}

    func record(action: String, outcome: CleanupOutcome) {
        guard !outcome.moved.isEmpty else { return }
        latest = TrashUndoSession(action: action, moves: outcome.moved)
    }

    func dismiss() {
        latest = nil
    }

    func undoLatest() {
        guard let session = latest, !isRestoring else { return }
        isRestoring = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Cleaner.restore(session.moves)
            }.value
            self.isRestoring = false

            if result.failures.isEmpty {
                self.latest = nil
                self.resultMessage = "\(result.restored.count)개 항목을 원래 위치로 복원했습니다."
            } else {
                let failedPaths = Set(result.failures.map { $0.url.standardizedFileURL.path })
                let remaining = session.moves.filter {
                    failedPaths.contains($0.trashedURL.standardizedFileURL.path)
                }
                self.latest = remaining.isEmpty
                    ? nil
                    : TrashUndoSession(action: session.action, moves: remaining)
                self.resultMessage = "\(result.restored.count)개를 복원했고, \(result.failures.count)개는 복원하지 못했습니다.\n\(result.failures.prefix(3).map(\.message).joined(separator: "\n"))"
            }
        }
    }
}

@MainActor
enum CleanupRecorder {
    static func record(action: String, outcome: CleanupOutcome) {
        CleanupHistoryStore.shared.add(
            action: action,
            itemCount: outcome.succeeded,
            freedBytes: outcome.freed,
            errors: outcome.errors
        )
        TrashUndoStore.shared.record(action: action, outcome: outcome)
    }
}

enum DiagnosticReport {
    enum ExportResult {
        case cancelled
        case saved
        case failed(String)
    }

    @MainActor
    static func export(history: [CleanupHistoryRecord], exclusions: [String]) -> ExportResult {
        let panel = NSSavePanel()
        panel.title = "진단 보고서 내보내기"
        panel.nameFieldStringValue = "MacCleaner-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let process = ProcessInfo.processInfo
        let bundle = Bundle.main
        var lines = [
            "MacCleaner 진단 보고서",
            "생성: \(Date().formatted(date: .numeric, time: .standard))",
            "앱 버전: \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드")",
            "macOS: \(process.operatingSystemVersionString)",
            "기기: \(machineChipName())",
            "제외 항목 수: \(exclusions.count)",
            "CleanMyMac 감시 실행: \(ThirdPartyUninstallerDetector.isCleanMyMacMonitorRunning ? "예" : "아니요")",
            "",
            "최근 진단 이벤트",
        ]

        let events = DiagnosticLog.snapshot()
        if events.isEmpty {
            lines.append("기록 없음")
        } else {
            for event in events.prefix(50) {
                lines.append("[\(event.date.formatted(date: .numeric, time: .standard))] \(event.category): \(event.message)")
            }
        }

        lines += [
            "",
            "최근 정리 기록",
        ]

        if history.isEmpty {
            lines.append("기록 없음")
        } else {
            for record in history.prefix(30) {
                lines.append("[\(record.date.formatted(date: .numeric, time: .standard))] \(record.action) | 성공 \(record.itemCount) | 실패 \(record.failedCount) | \(formatBytes(record.freedBytes))")
                record.errors.prefix(3).forEach { lines.append("  오류: \($0)") }
            }
        }

        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

struct DiagnosticEvent: Codable {
    let date: Date
    let category: String
    let message: String
}

enum DiagnosticLog {
    private static let key = "diagnostics.events.v1"
    private static let lock = NSLock()

    static func record(category: String, message: String) {
        lock.lock()
        var events = snapshotUnlocked()
        events.insert(DiagnosticEvent(date: Date(), category: category, message: message), at: 0)
        events = Array(events.prefix(100))
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
        lock.unlock()
    }

    static func snapshot() -> [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return snapshotUnlocked()
    }

    private static func snapshotUnlocked() -> [DiagnosticEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let events = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return []
        }
        return events
    }
}

enum ThirdPartyUninstallerDetector {
    static var isCleanMyMacMonitorRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            let identifier = app.bundleIdentifier?.lowercased() ?? ""
            return identifier.contains("com.macpaw.cleanmymac")
        }
    }
}
