import Foundation
import AppKit

// MARK: - 크기 계산

enum FileSizer {
    static func directorySize(
        _ url: URL,
        isCancelled: () -> Bool
    ) -> (size: Int64, wasCancelled: Bool) {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return (0, false) }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if isCancelled() { return (total, true) }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return (total, false)
    }

    static func directorySize(_ url: URL) -> Int64 {
        directorySize(url, isCancelled: { false }).size
    }

    /// 파일이면 파일 크기, 폴더면 전체 크기
    static func itemSize(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue { return directorySize(url) }
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? 0)
    }
}

enum StorageAvailability {
    static func isOnlineOnlyUbiquitousItem(_ url: URL) -> Bool {
        guard FileManager.default.isUbiquitousItem(at: url) else { return false }
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        return status != .current && status != .downloaded
    }
}

// MARK: - 삭제 안전장치

enum FileProtection {
    static func deletionTargets(from urls: [URL]) -> (urls: [URL], rejections: [CleanupFailure]) {
        var rejections: [CleanupFailure] = []
        var accepted: [(url: URL, path: String)] = []
        var seen = Set<String>()

        for url in urls {
            if let reason = rejectionReason(for: url) {
                rejections.append(CleanupFailure(url: url, message: reason))
                continue
            }

            let path = normalizedPath(url)
            guard seen.insert(path).inserted else { continue }
            accepted.append((url, path))
        }

        accepted.sort { pathDepth($0.path) < pathDepth($1.path) }

        var collapsed: [(url: URL, path: String)] = []
        for candidate in accepted {
            let isCoveredByParent = collapsed.contains { isSameOrInside(candidate.path, $0.path) }
            if !isCoveredByParent {
                collapsed.append(candidate)
            }
        }

        return (collapsed.map(\.url), rejections)
    }

    static func rejectionReason(for url: URL) -> String? {
        let path = normalizedPath(url)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let homePath = normalizedPath(home)

        if let appPath = Bundle.main.bundleURL.path.nilIfEmpty,
           isSameOrInside(path, appPath) {
            return "현재 실행 중인 앱은 삭제할 수 없습니다"
        }

        let protectedSystemRoots = [
            "/", "/System", "/Library", "/bin", "/sbin", "/usr", "/private", "/etc",
        ]
        if protectedSystemRoots.contains(where: { isSameOrInside(path, $0) }) {
            return "시스템 보호 경로입니다"
        }

        let protectedContainerRoots = [
            "/Applications", "/Users", "/Volumes", "/Network",
            homePath,
            "\(homePath)/Desktop",
            "\(homePath)/Documents",
            "\(homePath)/Downloads",
            "\(homePath)/Movies",
            "\(homePath)/Music",
            "\(homePath)/Pictures",
            "\(homePath)/Library",
            "\(homePath)/.Trash",
        ]
        if protectedContainerRoots.contains(path) {
            return "폴더 전체 삭제가 제한된 보호 위치입니다"
        }

        let sensitiveUserPaths = [
            "\(homePath)/.ssh",
            "\(homePath)/.gnupg",
            "\(homePath)/.aws",
            "\(homePath)/.config/gh",
            "\(homePath)/Library/Keychains",
            "\(homePath)/Library/Accounts",
            "\(homePath)/Library/Mobile Documents",
            "\(homePath)/Library/Group Containers/group.com.apple.notes",
            "\(homePath)/Pictures/Photos Library.photoslibrary",
            "\(homePath)/Pictures/Photo Booth Library",
        ]
        if sensitiveUserPaths.contains(where: { isSameOrInside(path, $0) }) {
            return "계정/키체인/사진 보관함 같은 민감 데이터는 삭제할 수 없습니다"
        }

        return nil
    }

    private static func normalizedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.count > 1 else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func isSameOrInside(_ path: String, _ root: String) -> Bool {
        if root == "/" { return path == "/" }
        return path == root || path.hasPrefix(root + "/")
    }

    private static func pathDepth(_ path: String) -> Int {
        path.split(separator: "/").count
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - 시스템 정리 (캐시 / 로그 / 개발 찌꺼기)

enum JunkScanner {
    static func scan() -> [JunkCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var categories: [JunkCategory] = []

        categories.append(JunkCategory(
            name: "사용자 캐시",
            icon: "internaldrive",
            items: itemsInDirectory(home.appendingPathComponent("Library/Caches"))
        ))

        categories.append(JunkCategory(
            name: "로그 파일",
            icon: "doc.text",
            items: itemsInDirectory(home.appendingPathComponent("Library/Logs"))
        ))

        // Xcode를 쓰는 경우에만 나타나는 항목들
        var devItems: [CleanableItem] = []
        let devPaths = [
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/Archives",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Developer/CoreSimulator/Caches",
        ]
        for path in devPaths {
            let url = home.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = FileSizer.directorySize(url)
            if size > 0 {
                devItems.append(CleanableItem(url: url, name: url.lastPathComponent, detail: url.path, size: size))
            }
        }
        if !devItems.isEmpty {
            categories.append(JunkCategory(name: "개발자 데이터 (Xcode)", icon: "hammer", items: devItems))
        }

        // Mail 앱이 로컬에 저장한 첨부파일 캐시
        let mailDownloads = home.appendingPathComponent(
            "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        )
        let mailItems = itemsInDirectory(mailDownloads)
        if !mailItems.isEmpty {
            categories.append(JunkCategory(name: "메일 첨부파일", icon: "envelope", items: mailItems))
        }

        // 빈 카테고리는 제외하고, 각 카테고리 안에서 큰 항목부터 정렬
        return categories
            .map { cat in
                var c = cat
                c.items.sort { $0.size > $1.size }
                return c
            }
            .filter { !$0.items.isEmpty }
    }

    private static func itemsInDirectory(_ dir: URL) -> [CleanableItem] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.compactMap { url in
            let size = FileSizer.itemSize(url)
            guard size > 0 else { return nil }
            return CleanableItem(url: url, name: url.lastPathComponent, detail: url.path, size: size)
        }
    }
}

// MARK: - 대용량 파일

enum LargeFileScanner {
    /// 홈 디렉토리에서 minBytes 이상인 파일 탐색 (~/Library 제외)
    static func scan(
        minBytes: Int64,
        isCancelled: () -> Bool = { false },
        progress: (FileScanProgress) -> Void = { _ in }
    ) -> (items: [CleanableItem], wasCancelled: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return ([], false) }

        let excludedPaths = ExclusionRules.snapshot()
        var results: [CleanableItem] = []
        var scanned = 0
        var skippedCloud = 0
        var skippedUnavailable = 0
        for case let url as URL in enumerator {
            if isCancelled() { return (results, true) }
            scanned += 1
            if scanned % 150 == 0 {
                progress(FileScanProgress(
                    scanned: scanned,
                    found: results.count,
                    skippedCloud: skippedCloud,
                    skippedUnavailable: skippedUnavailable,
                    currentPath: url.path,
                    phase: "홈 폴더 탐색 중"
                ))
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                skippedUnavailable += 1
                continue
            }

            if values.isDirectory == true {
                if ExclusionRules.isExcluded(url, in: excludedPaths) {
                    enumerator.skipDescendants()
                    continue
                }
                // 홈 바로 아래의 Library는 시스템 정리에서 다루므로 건너뜀
                if url.lastPathComponent == "Library",
                   url.deletingLastPathComponent().path == home.path {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true,
                  let size = values.totalFileAllocatedSize,
                  Int64(size) >= minBytes else { continue }
            guard !ExclusionRules.isExcluded(url, in: excludedPaths) else { continue }
            if StorageAvailability.isOnlineOnlyUbiquitousItem(url) {
                skippedCloud += 1
                continue
            }

            results.append(CleanableItem(
                url: url,
                name: url.lastPathComponent,
                detail: url.deletingLastPathComponent().path,
                size: Int64(size),
                createdAt: values.creationDate,
                modifiedAt: values.contentModificationDate
            ))
        }

        results.sort { $0.size > $1.size }
        let limited = Array(results.prefix(300))
        progress(FileScanProgress(
            scanned: scanned,
            found: limited.count,
            skippedCloud: skippedCloud,
            skippedUnavailable: skippedUnavailable,
            currentPath: "",
            phase: "스캔 완료"
        ))
        if skippedCloud + skippedUnavailable > 0 {
            DiagnosticLog.record(
                category: "대용량 파일 스캔",
                message: "온라인 전용 \(skippedCloud)개, 접근 불가 \(skippedUnavailable)개 제외"
            )
        }
        return (limited, false)
    }

    static func scan(minBytes: Int64) -> [CleanableItem] {
        scan(minBytes: minBytes, isCancelled: { false }, progress: { _ in }).items
    }
}

// MARK: - 앱 관리 (완전 삭제)

private struct CachedAppSize: Codable {
    let modifiedAt: TimeInterval
    let size: Int64
}

private enum AppSizeCache {
    private static let key = "scanner.app-size-cache.v1"
    private static let lock = NSLock()
    private static var entries: [String: CachedAppSize] = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: CachedAppSize].self, from: data) else {
            return [:]
        }
        return decoded
    }()

    static func size(
        for url: URL,
        modifiedAt: Date?,
        isCancelled: () -> Bool
    ) -> (size: Int64, wasCancelled: Bool) {
        let path = url.standardizedFileURL.path
        let timestamp = modifiedAt?.timeIntervalSince1970 ?? 0

        lock.lock()
        let cached = entries[path]
        lock.unlock()
        if let cached, cached.modifiedAt == timestamp {
            return (cached.size, false)
        }

        let result = FileSizer.directorySize(url, isCancelled: isCancelled)
        guard !result.wasCancelled else { return result }

        lock.lock()
        entries[path] = CachedAppSize(modifiedAt: timestamp, size: result.size)
        if entries.count > 500 {
            entries = Dictionary(uniqueKeysWithValues: entries.sorted { $0.key < $1.key }.suffix(500))
        }
        let snapshot = entries
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return result
    }
}

enum AppScanner {
    static func scan(
        isCancelled: () -> Bool = { false },
        progress: (FileScanProgress) -> Void = { _ in }
    ) -> (apps: [AppInfo], wasCancelled: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]

        var appURLs: [URL] = []
        var seen = Set<String>()
        let currentAppPath = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        for dir in dirs {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                DiagnosticLog.record(category: "앱 스캔", message: "접근 불가: \(dir.path)")
                continue
            }

            for url in children where url.pathExtension == "app" {
                if isCancelled() { return ([], true) }
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard path != currentAppPath, seen.insert(path).inserted else { continue }
                appURLs.append(url)
            }
        }

        var apps: [AppInfo] = []
        for (index, url) in appURLs.enumerated() {
            if isCancelled() { return (apps, true) }
            progress(FileScanProgress(
                scanned: index,
                found: apps.count,
                currentPath: url.path,
                phase: "앱 크기 계산 중"
            ))

            let values = try? url.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
                .isWritableKey,
            ])
            let size = AppSizeCache.size(
                for: url,
                modifiedAt: values?.contentModificationDate,
                isCancelled: isCancelled
            )
            if size.wasCancelled { return (apps, true) }

            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            apps.append(AppInfo(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                bundleID: bundleID,
                size: size.size,
                version: version,
                createdAt: values?.creationDate,
                modifiedAt: values?.contentModificationDate,
                lastOpenedAt: values?.contentAccessDate,
                isWritable: values?.isWritable ?? FileManager.default.isWritableFile(atPath: url.path)
            ))
            progress(FileScanProgress(
                scanned: index + 1,
                found: apps.count,
                currentPath: url.path,
                phase: "앱 크기 계산 중"
            ))
        }

        apps.sort { $0.size > $1.size }
        progress(FileScanProgress(
            scanned: appURLs.count,
            found: apps.count,
            currentPath: "",
            phase: "스캔 완료"
        ))
        return (apps, false)
    }

    static func scan() -> [AppInfo] {
        scan(isCancelled: { false }, progress: { _ in }).apps
    }

    static func removalPlan(for app: AppInfo) -> AppRemovalPlan {
        let leftovers = leftovers(for: app)
        let related = relatedLaunchItems(for: app)
        let running = runningApplications(for: app).compactMap {
            $0.localizedName ?? $0.bundleIdentifier ?? app.name
        }

        var warnings = related.warnings
        if !app.isWritable {
            warnings.append("이 앱은 관리자 소유일 수 있어 현재 권한으로 휴지통 이동이 실패할 수 있습니다.")
        }
        if ThirdPartyUninstallerDetector.isCleanMyMacMonitorRunning {
            warnings.append("CleanMyMac의 앱 삭제 감시가 실행 중이어서 휴지통 이동 시 CleanMyMac 창이 열릴 수 있습니다.")
        }
        warnings += related.manualItems.map {
            "관리자 영역 항목은 자동 삭제하지 않습니다: \($0.path)"
        }
        warnings += privilegedHelperWarnings(for: app)

        let allLeftovers = (leftovers + related.deletableItems).deduplicatedByPath()
        return AppRemovalPlan(
            app: app,
            leftovers: allLeftovers,
            warnings: Array(Set(warnings)).sorted(),
            runningAppNames: Array(Set(running)).sorted()
        )
    }

    static func runningApplications(for app: AppInfo) -> [NSRunningApplication] {
        let appPath = app.url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.filter { running in
            if let bundleID = app.bundleID, running.bundleIdentifier == bundleID {
                return true
            }
            return running.bundleURL?.standardizedFileURL.path == appPath
        }
    }

    static func requestTerminate(_ app: AppInfo) -> Int {
        let running = runningApplications(for: app)
        running.forEach { $0.terminate() }
        return running.count
    }

    /// 앱이 홈 폴더에 남기는 잔여 파일 (설정, 캐시, 상태 저장 등)
    static func leftovers(for app: AppInfo) -> [CleanableItem] {
        guard let bid = app.bundleID else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser

        let candidates: [String] = [
            "Library/Application Support/\(bid)",
            "Library/Application Support/\(app.name)",
            "Library/Caches/\(bid)",
            "Library/Preferences/\(bid).plist",
            "Library/Saved Application State/\(bid).savedState",
            "Library/Containers/\(bid)",
            "Library/HTTPStorages/\(bid)",
            "Library/WebKit/\(bid)",
            "Library/Logs/\(app.name)",
        ]

        var seen = Set<String>()
        var items: [CleanableItem] = []
        for path in candidates {
            let url = home.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path),
                  seen.insert(url.path).inserted else { continue }
            items.append(CleanableItem(
                url: url,
                name: url.lastPathComponent,
                detail: url.path,
                size: FileSizer.itemSize(url)
            ))
        }
        return items.sorted { $0.size > $1.size }
    }

    private static func relatedLaunchItems(
        for app: AppInfo
    ) -> (deletableItems: [CleanableItem], manualItems: [URL], warnings: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs: [(URL, Bool)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), true),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), false),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), false),
        ]

        var deletable: [CleanableItem] = []
        var manual: [URL] = []
        var warnings: [String] = []

        for (dir, canDelete) in dirs {
            guard let plists = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for plistURL in plists where plistURL.pathExtension == "plist" {
                guard launchItem(plistURL, matches: app) else { continue }
                if canDelete {
                    deletable.append(CleanableItem(
                        url: plistURL,
                        name: plistURL.lastPathComponent,
                        detail: "시작 프로그램: \(plistURL.path)",
                        size: FileSizer.itemSize(plistURL)
                    ))
                } else {
                    manual.append(plistURL)
                }
            }
        }

        if !deletable.isEmpty {
            warnings.append("관련 시작 프로그램 \(deletable.count)개를 함께 휴지통으로 이동합니다.")
        }

        return (deletable, manual, warnings)
    }

    private static func launchItem(_ plistURL: URL, matches app: AppInfo) -> Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any] else { return false }

        var haystack = [
            plistURL.lastPathComponent,
            plist["Label"] as? String,
            plist["Program"] as? String,
        ].compactMap { $0 }

        if let args = plist["ProgramArguments"] as? [String] {
            haystack.append(contentsOf: args)
        }

        let appPath = app.url.standardizedFileURL.path.lowercased()
        let bundleID = app.bundleID?.lowercased()
        let appName = app.name.lowercased()
        return haystack.map { $0.lowercased() }.contains { value in
            let bundleMatch = bundleID.map { value.contains($0) } == true
            let appPathMatch = value.contains(appPath) || value.contains("/\(appName).app")
            let fallbackNameMatch = bundleID == nil && value.contains(appName)
            return bundleMatch || appPathMatch || fallbackNameMatch
        }
    }

    private static func privilegedHelperWarnings(for app: AppInfo) -> [String] {
        let dir = URL(fileURLWithPath: "/Library/PrivilegedHelperTools")
        guard let helpers = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let bundleID = app.bundleID?.lowercased()
        let appName = app.name.lowercased()
        return helpers.compactMap { helper in
            let name = helper.lastPathComponent.lowercased()
            let matches = bundleID.map { name.contains($0) } == true
                || (bundleID == nil && name.contains(appName))
            guard matches else {
                return nil
            }
            return "관리자 Helper는 자동 삭제하지 않습니다: \(helper.path)"
        }
    }
}

private extension Array where Element == CleanableItem {
    func deduplicatedByPath() -> [CleanableItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.url.standardizedFileURL.path).inserted }
            .sorted { $0.size > $1.size }
    }
}

// MARK: - 시스템 상태

enum SystemStatusProvider {
    static func current() -> SystemStatus {
        var status = SystemStatus()

        // 디스크
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]) {
            status.diskTotal = Int64(values.volumeTotalCapacity ?? 0)
            status.diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
        }

        // 메모리
        status.memTotal = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let pageSize = Int64(vm_kernel_page_size)
            let used = Int64(stats.active_count) + Int64(stats.wire_count)
                + Int64(stats.compressor_page_count)
            status.memUsed = used * pageSize
        }

        // 휴지통
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        status.trashSize = FileSizer.directorySize(trash)

        return status
    }
}

// MARK: - 삭제 처리

enum Cleaner {
    /// 항목들을 휴지통으로 이동. (영구 삭제하지 않음)
    static func trash(_ urls: [URL]) -> CleanupOutcome {
        var moved: [TrashMove] = []
        let targets = FileProtection.deletionTargets(from: urls)
        var failures = targets.rejections

        for url in targets.urls {
            let size = FileSizer.itemSize(url)
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                guard let trashedURL = resultingURL as URL? else {
                    failures.append(CleanupFailure(url: url, message: "휴지통 위치를 확인하지 못했습니다"))
                    continue
                }
                moved.append(TrashMove(originalURL: url, trashedURL: trashedURL, size: size))
            } catch {
                failures.append(CleanupFailure(url: url, message: error.localizedDescription))
            }
        }
        return CleanupOutcome(moved: moved, failures: failures)
    }

    static func restore(_ moves: [TrashMove]) -> RestoreOutcome {
        var restored: [TrashMove] = []
        var failures: [CleanupFailure] = []

        for move in moves {
            guard FileManager.default.fileExists(atPath: move.trashedURL.path) else {
                failures.append(CleanupFailure(url: move.trashedURL, message: "휴지통에서 항목을 찾을 수 없습니다"))
                continue
            }
            guard !FileManager.default.fileExists(atPath: move.originalURL.path) else {
                failures.append(CleanupFailure(url: move.trashedURL, message: "원래 위치에 같은 이름의 항목이 있습니다"))
                continue
            }
            do {
                try FileManager.default.moveItem(at: move.trashedURL, to: move.originalURL)
                restored.append(move)
            } catch {
                failures.append(CleanupFailure(url: move.trashedURL, message: error.localizedDescription))
            }
        }
        return RestoreOutcome(restored: restored, failures: failures)
    }

    /// Finder를 통해 휴지통 비우기 (자동화 권한 필요)
    static func emptyTrash() -> String? {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo, let message = errorInfo[NSAppleScript.errorMessage] as? String {
            return message
        }
        return nil
    }
}
