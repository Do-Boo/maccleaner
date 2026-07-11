import Foundation
import SwiftUI
import ServiceManagement

// MARK: - 시스템 정리

@MainActor
final class JunkViewModel: ObservableObject {
    @Published var categories: [JunkCategory] = []
    @Published var selected: Set<UUID> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var resultMessage: String?

    var selectedItems: [CleanableItem] {
        categories.flatMap(\.items).filter { selected.contains($0.id) }
    }

    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { JunkScanner.scan() }.value
            self.categories = result
            self.selected = Set(result.flatMap { $0.items.map(\.id) })
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func clean() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        isScanning = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Cleaner.trash(urls) }.value
            var message = "\(outcome.succeeded)개 항목을 휴지통으로 이동했습니다 (\(formatBytes(outcome.freed)) 확보)."
            if !outcome.errors.isEmpty {
                message += "\n실패 \(outcome.errors.count)건: \(outcome.errors.prefix(3).joined(separator: ", "))"
            }
            CleanupRecorder.record(action: "시스템 정리", outcome: outcome)
            self.resultMessage = message
            self.isScanning = false
            self.scan() // 정리 후 다시 스캔해서 목록 갱신
        }
    }
}

// MARK: - 대용량 파일

@MainActor
final class LargeFilesViewModel: ObservableObject {
    @Published var files: [CleanableItem] = []
    @Published var selected: Set<UUID> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var minSizeMB: Int = 500
    @Published var resultMessage: String?
    @Published var scanProgress = FileScanProgress()

    private var scanTask: Task<(items: [CleanableItem], wasCancelled: Bool), Never>?
    private var scanID = UUID()

    var selectedItems: [CleanableItem] { files.filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = FileScanProgress(phase: "스캔 준비 중")
        resultMessage = nil
        let minBytes = Int64(minSizeMB) * 1_000_000
        let id = UUID()
        scanID = id
        let worker = Task.detached(priority: .userInitiated) {
            LargeFileScanner.scan(
                minBytes: minBytes,
                isCancelled: { Task.isCancelled },
                progress: { progress in
                    Task { @MainActor in
                        self.scanProgress = progress
                    }
                }
            )
        }
        scanTask = worker
        Task {
            let result = await worker.value
            guard self.scanID == id else { return }
            self.scanTask = nil
            self.isScanning = false
            if result.wasCancelled {
                self.resultMessage = "대용량 파일 스캔을 취소했습니다."
                return
            }
            self.files = result.items
            self.selected = []
            self.hasScanned = true
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func trashSelected() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        isScanning = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Cleaner.trash(urls) }.value
            var message = "\(outcome.succeeded)개 파일을 휴지통으로 이동했습니다 (\(formatBytes(outcome.freed)) 확보)."
            if !outcome.errors.isEmpty {
                message += "\n실패 \(outcome.errors.count)건"
            }
            CleanupRecorder.record(action: "대용량 파일", outcome: outcome)
            self.resultMessage = message
            let movedPaths = Set(outcome.moved.map { $0.originalURL.standardizedFileURL.path })
            self.files.removeAll { movedPaths.contains($0.url.standardizedFileURL.path) }
            let failedPaths = Set(outcome.failures.map { $0.url.standardizedFileURL.path })
            self.selected = Set(self.files.filter {
                failedPaths.contains($0.url.standardizedFileURL.path)
            }.map(\.id))
            self.isScanning = false
        }
    }

    func exclude(_ item: CleanableItem) {
        ExclusionStore.shared.add(item)
        files.removeAll { $0.id == item.id }
        selected.remove(item.id)
        resultMessage = "'\(item.name)'을(를) 제외 목록에 추가했습니다."
    }
}

// MARK: - 앱 관리

@MainActor
final class AppsViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var scanProgress = FileScanProgress()
    @Published var pendingRemovalPlan: AppRemovalPlan?
    @Published var preparingAppID: UUID?
    @Published var isUninstalling = false
    @Published var resultMessage: String?

    private var scanTask: Task<(apps: [AppInfo], wasCancelled: Bool), Never>?
    private var scanID = UUID()
    private var retryURLs: [URL] = []
    private var retryApp: AppInfo?

    var canRetryFailures: Bool { !retryURLs.isEmpty && !isUninstalling }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = FileScanProgress(phase: "앱 목록 확인 중")
        resultMessage = nil
        let id = UUID()
        scanID = id
        let worker = Task.detached(priority: .userInitiated) {
            AppScanner.scan(
                isCancelled: { Task.isCancelled },
                progress: { progress in
                    Task { @MainActor in
                        self.scanProgress = progress
                    }
                }
            )
        }
        scanTask = worker
        Task {
            let result = await worker.value
            guard self.scanID == id else { return }
            self.scanTask = nil
            self.isScanning = false
            if result.wasCancelled {
                self.resultMessage = "앱 목록 스캔을 취소했습니다."
                return
            }
            self.apps = result.apps
            self.hasScanned = true
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// 삭제 확인 시트를 띄우기 위해 앱과 잔여 파일을 준비
    func prepareUninstall(_ app: AppInfo) {
        guard preparingAppID == nil else { return }
        preparingAppID = app.id
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                AppScanner.removalPlan(for: app)
            }.value
            self.pendingRemovalPlan = plan
            self.preparingAppID = nil
        }
    }

    func confirmUninstall(selectedLeftoverPaths: Set<String>) {
        guard let plan = pendingRemovalPlan else { return }
        guard !isUninstalling else { return }
        guard plan.canUninstall else {
            resultMessage = "'\(plan.app.name)'이(가) 실행 중입니다. 앱을 종료한 뒤 다시 시도하세요."
            return
        }
        let app = plan.app
        isUninstalling = true
        resultMessage = nil
        Task {
            let refreshedPlan = await Task.detached(priority: .userInitiated) {
                AppScanner.removalPlan(for: app)
            }.value
            guard refreshedPlan.canUninstall else {
                self.pendingRemovalPlan = refreshedPlan
                self.isUninstalling = false
                self.resultMessage = "삭제 직전 확인 결과 '\(app.name)'이(가) 실행 중입니다. 앱을 종료한 뒤 다시 시도하세요."
                return
            }

            let availableLeftovers = refreshedPlan.leftovers.filter {
                selectedLeftoverPaths.contains($0.url.standardizedFileURL.path)
            }
            let urls = [app.url] + availableLeftovers.map(\.url)
            let outcome = await Task.detached(priority: .userInitiated) { Cleaner.trash(urls) }.value
            var message = "'\(app.name)' 관련 \(outcome.succeeded)개 항목을 휴지통으로 이동했습니다 (\(formatBytes(outcome.freed)) 확보)."
            if !outcome.errors.isEmpty {
                message += "\n실패: \(outcome.errors.joined(separator: ", "))"
            }
            CleanupRecorder.record(action: "앱 삭제: \(app.name)", outcome: outcome)
            self.pendingRemovalPlan = nil
            self.isUninstalling = false
            self.retryURLs = outcome.failures.map(\.url)
            self.retryApp = outcome.failures.isEmpty ? nil : app
            self.resultMessage = message
            if outcome.didMove(app.url) {
                self.apps.removeAll { $0.id == app.id }
            }
        }
    }

    func retryFailedUninstall() {
        guard canRetryFailures else { return }
        let urls = retryURLs
        let app = retryApp
        retryURLs = []
        retryApp = nil
        isUninstalling = true
        resultMessage = nil

        Task {
            if let app {
                let running = await Task.detached(priority: .userInitiated) {
                    AppScanner.runningApplications(for: app)
                }.value
                guard running.isEmpty else {
                    self.retryURLs = urls
                    self.retryApp = app
                    self.isUninstalling = false
                    self.resultMessage = "'\(app.name)'이(가) 다시 실행 중이라 재시도하지 않았습니다."
                    return
                }
            }

            let outcome = await Task.detached(priority: .userInitiated) { Cleaner.trash(urls) }.value
            let action = app.map { "앱 삭제 재시도: \($0.name)" } ?? "삭제 재시도"
            CleanupRecorder.record(action: action, outcome: outcome)
            self.retryURLs = outcome.failures.map(\.url)
            self.retryApp = outcome.failures.isEmpty ? nil : app
            self.isUninstalling = false
            self.resultMessage = outcome.failures.isEmpty
                ? "실패했던 \(outcome.succeeded)개 항목을 휴지통으로 이동했습니다."
                : "\(outcome.succeeded)개 성공, \(outcome.failures.count)개 실패했습니다.\n\(outcome.errors.prefix(3).joined(separator: "\n"))"
            if let app, outcome.didMove(app.url) {
                self.apps.removeAll { $0.id == app.id }
            }
        }
    }

    func requestTerminatePendingApp() {
        guard let plan = pendingRemovalPlan else { return }
        let app = plan.app
        let count = AppScanner.requestTerminate(app)
        resultMessage = count > 0
            ? "'\(app.name)'에 종료 요청을 보냈습니다. 종료 후 삭제 버튼을 다시 누르세요."
            : "실행 중인 '\(app.name)'을 찾지 못했습니다."

        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            let refreshed = await Task.detached(priority: .userInitiated) {
                AppScanner.removalPlan(for: app)
            }.value
            self.pendingRemovalPlan = refreshed
        }
    }

    func dismissRemovalPlan() {
        pendingRemovalPlan = nil
    }
}

// MARK: - 대시보드

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var status = SystemStatus()
    @Published var isLoading = false
    @Published var resultMessage: String?
    @Published var launchAtLogin = false

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            resultMessage = "자동 시작 설정 실패: \(error.localizedDescription)\n(빌드된 MacCleaner.app으로 실행 중일 때만 설정할 수 있습니다)"
            refreshLaunchAtLogin()
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { SystemStatusProvider.current() }.value
            self.status = result
            self.isLoading = false
        }
    }

    func emptyTrash() {
        let trashSizeBefore = status.trashSize
        Task {
            let error = await Task.detached(priority: .userInitiated) { Cleaner.emptyTrash() }.value
            if let error {
                self.resultMessage = "휴지통 비우기 실패: \(error)\nFinder 제어 권한이 필요할 수 있습니다. (시스템 설정 > 개인정보 보호 및 보안 > 자동화)"
            } else {
                CleanupHistoryStore.shared.add(
                    action: "휴지통 비우기",
                    itemCount: trashSizeBefore > 0 ? 1 : 0,
                    freedBytes: trashSizeBefore,
                    errors: []
                )
                self.resultMessage = "휴지통을 비웠습니다."
            }
            self.refresh()
        }
    }

    /// 비활성 메모리 정리 (purge — 관리자 암호 필요)
    func freeMemory() {
        let usedBefore = status.memUsed
        Task {
            let error = await Task.detached(priority: .userInitiated) { Shell.runAsAdmin("purge") }.value
            if let error {
                if !error.contains("User canceled") {
                    self.resultMessage = "메모리 해제 실패: \(error)"
                }
            } else {
                let after = await Task.detached { SystemStatusProvider.current() }.value
                let freed = max(usedBefore - after.memUsed, 0)
                self.status = after
                self.resultMessage = "메모리를 정리했습니다. (약 \(formatBytes(freed)) 확보)"
            }
        }
    }
}
