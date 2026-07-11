import Foundation

/// 삭제 가능한 파일/폴더 하나
struct CleanableItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let detail: String
    let size: Int64
    let createdAt: Date?
    let modifiedAt: Date?

    init(
        url: URL,
        name: String,
        detail: String,
        size: Int64,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil
    ) {
        self.url = url
        self.name = name
        self.detail = detail
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// 시스템 정리 화면의 카테고리 (사용자 캐시, 로그 등)
struct JunkCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    var items: [CleanableItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// 설치된 앱 정보
struct AppInfo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let bundleID: String?
    let size: Int64
    let version: String?
    let createdAt: Date?
    let modifiedAt: Date?
    let lastOpenedAt: Date?
    let isWritable: Bool

    init(
        url: URL,
        name: String,
        bundleID: String?,
        size: Int64,
        version: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        isWritable: Bool = true
    ) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.size = size
        self.version = version
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastOpenedAt = lastOpenedAt
        self.isWritable = isWritable
    }
}

/// 앱 삭제 전 확인할 관련 항목과 차단 상태
struct AppRemovalPlan: Identifiable {
    var id: UUID { app.id }
    let app: AppInfo
    let leftovers: [CleanableItem]
    let warnings: [String]
    let runningAppNames: [String]

    var canUninstall: Bool { runningAppNames.isEmpty }
    var totalSize: Int64 { app.size + leftovers.reduce(0) { $0 + $1.size } }
}

/// 대시보드에 표시할 시스템 상태
struct SystemStatus {
    var diskTotal: Int64 = 0
    var diskFree: Int64 = 0
    var memTotal: Int64 = 0
    var memUsed: Int64 = 0
    var trashSize: Int64 = 0

    var diskUsed: Int64 { max(diskTotal - diskFree, 0) }
    var diskUsageRatio: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }
    var memUsageRatio: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }
}

/// 긴 파일 스캔 작업의 UI 진행 상태
struct FileScanProgress: Sendable {
    var scanned: Int = 0
    var found: Int = 0
    var skippedCloud: Int = 0
    var skippedUnavailable: Int = 0
    var currentPath: String = ""
    var phase: String = ""
}

struct TrashMove: Identifiable, Sendable {
    let id = UUID()
    let originalURL: URL
    let trashedURL: URL
    let size: Int64
}

struct CleanupFailure: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let message: String
}

struct CleanupOutcome: Sendable {
    let moved: [TrashMove]
    let failures: [CleanupFailure]

    var succeeded: Int { moved.count }
    var freed: Int64 { moved.reduce(0) { $0 + $1.size } }
    var errors: [String] { failures.map { "\($0.url.lastPathComponent): \($0.message)" } }

    func didMove(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return moved.contains { $0.originalURL.standardizedFileURL.path == path }
    }
}

struct RestoreOutcome: Sendable {
    let restored: [TrashMove]
    let failures: [CleanupFailure]
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// 칩 이름 (예: "Apple M3") — 사이드바 기기 정보 표시용
func machineChipName() -> String {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    guard size > 0 else { return "Mac" }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
    return String(cString: buffer)
}
