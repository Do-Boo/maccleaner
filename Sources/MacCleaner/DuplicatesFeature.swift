import SwiftUI
import CryptoKit

// MARK: - 중복 파일 찾기

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let size: Int64 // 파일 하나의 크기
    let files: [CleanableItem]

    var wastedSize: Int64 { size * Int64(max(files.count - 1, 0)) }
}

private struct CachedFileHash: Codable {
    let size: Int64
    let modifiedAt: TimeInterval
    let hash: String
}

private enum DuplicateHashCache {
    private static let key = "scanner.duplicate-hash-cache.v1"
    private static let lock = NSLock()
    private static var entries: [String: CachedFileHash] = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: CachedFileHash].self, from: data) else {
            return [:]
        }
        return decoded
    }()

    static func value(for url: URL, size: Int64, modifiedAt: Date?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let entry = entries[url.standardizedFileURL.path]
        guard entry?.size == size,
              entry?.modifiedAt == (modifiedAt?.timeIntervalSince1970 ?? 0) else { return nil }
        return entry?.hash
    }

    static func store(_ hash: String, for url: URL, size: Int64, modifiedAt: Date?) {
        lock.lock()
        entries[url.standardizedFileURL.path] = CachedFileHash(
            size: size,
            modifiedAt: modifiedAt?.timeIntervalSince1970 ?? 0,
            hash: hash
        )
        if entries.count > 2_000 {
            entries = Dictionary(uniqueKeysWithValues: entries.sorted { $0.key < $1.key }.suffix(2_000))
        }
        let snapshot = entries
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum DuplicateScanner {
    /// 1MB 이상 파일을 크기 → SHA-256 해시 순으로 비교해 중복 그룹을 찾음
    static func scan(
        roots: [URL],
        isCancelled: () -> Bool = { false },
        progress: (FileScanProgress) -> Void = { _ in }
    ) -> (groups: [DuplicateGroup], wasCancelled: Bool) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let excludedPaths = ExclusionRules.snapshot()
        var bySize: [Int64: [URL]] = [:]
        var scanned = 0
        var candidates = 0
        var skippedCloud = 0
        var skippedUnavailable = 0

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if isCancelled() { return ([], true) }
                scanned += 1
                if scanned % 150 == 0 {
                    progress(FileScanProgress(
                        scanned: scanned,
                        found: candidates,
                        skippedCloud: skippedCloud,
                        skippedUnavailable: skippedUnavailable,
                        currentPath: url.path,
                        phase: "후보 파일 찾는 중"
                    ))
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                    skippedUnavailable += 1
                    continue
                }
                if values.isDirectory == true,
                   ExclusionRules.isExcluded(url, in: excludedPaths) {
                    enumerator.skipDescendants()
                    continue
                }

                guard values.isRegularFile == true,
                      let size = values.fileSize, size >= 1_000_000 else { continue }
                guard !ExclusionRules.isExcluded(url, in: excludedPaths) else { continue }
                if StorageAvailability.isOnlineOnlyUbiquitousItem(url) {
                    skippedCloud += 1
                    continue
                }
                bySize[Int64(size), default: []].append(url)
                candidates += 1
            }
        }

        var groups: [DuplicateGroup] = []
        var hashed = 0
        let hashTargets = bySize.values.reduce(0) { partial, urls in
            urls.count > 1 ? partial + urls.count : partial
        }
        for (size, urls) in bySize where urls.count > 1 {
            var byHash: [String: [URL]] = [:]
            for url in urls {
                if isCancelled() { return (groups, true) }
                hashed += 1
                if hashed % 20 == 0 {
                    progress(FileScanProgress(
                        scanned: hashed,
                        found: groups.count,
                        skippedCloud: skippedCloud,
                        skippedUnavailable: skippedUnavailable,
                        currentPath: url.path,
                        phase: "파일 내용 비교 중 (\(hashed)/\(hashTargets))"
                    ))
                }
                guard let hash = sha256(url, isCancelled: isCancelled) else {
                    if isCancelled() { return (groups, true) }
                    continue
                }
                byHash[hash, default: []].append(url)
            }
            for (_, dupes) in byHash where dupes.count > 1 {
                let items = dupes.map {
                    let values = try? $0.resourceValues(forKeys: [
                        .creationDateKey,
                        .contentModificationDateKey,
                    ])
                    return CleanableItem(
                        url: $0,
                        name: $0.lastPathComponent,
                        detail: $0.deletingLastPathComponent().path,
                        size: size,
                        createdAt: values?.creationDate,
                        modifiedAt: values?.contentModificationDate
                    )
                }
                groups.append(DuplicateGroup(size: size, files: items))
            }
        }
        let sorted = groups.sorted { $0.wastedSize > $1.wastedSize }
        progress(FileScanProgress(
            scanned: scanned,
            found: sorted.count,
            skippedCloud: skippedCloud,
            skippedUnavailable: skippedUnavailable,
            currentPath: "",
            phase: "스캔 완료"
        ))
        if skippedCloud + skippedUnavailable > 0 {
            DiagnosticLog.record(
                category: "중복 파일 스캔",
                message: "온라인 전용 \(skippedCloud)개, 접근 불가 \(skippedUnavailable)개 제외"
            )
        }
        return (sorted, false)
    }

    static func scan(roots: [URL]) -> [DuplicateGroup] {
        scan(roots: roots, isCancelled: { false }, progress: { _ in }).groups
    }

    private static func sha256(_ url: URL, isCancelled: () -> Bool) -> String? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values?.fileSize ?? 0)
        if let cached = DuplicateHashCache.value(
            for: url,
            size: size,
            modifiedAt: values?.contentModificationDate
        ) {
            return cached
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while true {
                if isCancelled() { return nil }
                guard let data = try handle.read(upToCount: 4_000_000), !data.isEmpty else { break }
                hasher.update(data: data)
            }
        } catch {
            DiagnosticLog.record(category: "중복 파일 스캔", message: "읽기 실패: \(url.path)")
            return nil
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        DuplicateHashCache.store(hash, for: url, size: size, modifiedAt: values?.contentModificationDate)
        return hash
    }
}

@MainActor
final class DuplicatesViewModel: ObservableObject {
    @Published var roots: [URL]
    @Published var groups: [DuplicateGroup] = []
    @Published var selected: Set<UUID> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var resultMessage: String?
    @Published var scanProgress = FileScanProgress()

    private var scanTask: Task<(groups: [DuplicateGroup], wasCancelled: Bool), Never>?
    private var scanID = UUID()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        roots = ["Downloads", "Documents", "Desktop"].map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var selectedItems: [CleanableItem] {
        groups.flatMap(\.files).filter { selected.contains($0.id) }
    }

    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "선택"
        panel.message = "중복 파일을 찾을 폴더를 선택하세요"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            roots = panel.urls
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = FileScanProgress(phase: "스캔 준비 중")
        resultMessage = nil
        let targets = roots
        let id = UUID()
        scanID = id
        let worker = Task.detached(priority: .userInitiated) {
            DuplicateScanner.scan(
                roots: targets,
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
                self.resultMessage = "중복 파일 스캔을 취소했습니다."
                return
            }
            self.groups = result.groups
            // 각 그룹에서 첫 번째(원본으로 간주)만 남기고 자동 선택
            self.selected = Set(result.groups.flatMap { $0.files.dropFirst().map(\.id) })
            self.hasScanned = true
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func trashSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        isScanning = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Cleaner.trash(items.map(\.url))
            }.value
            var message = "\(outcome.succeeded)개 중복 파일을 휴지통으로 이동했습니다 (\(formatBytes(outcome.freed)) 확보)."
            if !outcome.errors.isEmpty { message += "\n실패 \(outcome.errors.count)건" }
            CleanupRecorder.record(action: "중복 파일", outcome: outcome)
            self.resultMessage = message

            // 남은 파일이 2개 미만인 그룹은 더 이상 중복이 아니므로 제거
            let movedPaths = Set(outcome.moved.map { $0.originalURL.standardizedFileURL.path })
            self.groups = self.groups.compactMap { group in
                let remaining = group.files.filter { !movedPaths.contains($0.url.standardizedFileURL.path) }
                return remaining.count > 1 ? DuplicateGroup(size: group.size, files: remaining) : nil
            }
            let failedPaths = Set(outcome.failures.map { $0.url.standardizedFileURL.path })
            self.selected = Set(self.groups.flatMap(\.files).filter {
                failedPaths.contains($0.url.standardizedFileURL.path)
            }.map(\.id))
            self.isScanning = false
        }
    }

    func exclude(_ item: CleanableItem) {
        ExclusionStore.shared.add(item)
        groups = groups.compactMap { group in
            let remaining = group.files.filter { $0.id != item.id }
            return remaining.count > 1 ? DuplicateGroup(size: group.size, files: remaining) : nil
        }
        selected.remove(item.id)
        resultMessage = "'\(item.name)'을(를) 제외 목록에 추가했습니다."
    }
}

struct DuplicatesView: View {
    @ObservedObject var vm: DuplicatesViewModel
    @State private var confirmTrash = false
    @State private var fileDetail: ScannedFileDetail?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "중복 파일",
                subtitle: "내용이 완전히 같은 파일을 찾아 정리합니다 (1MB 이상)"
            ) {
                HStack {
                    Button {
                        vm.chooseFolders()
                    } label: {
                        Label("폴더 선택", systemImage: "folder")
                    }
                    Button {
                        vm.scan()
                    } label: {
                        Label("스캔", systemImage: "magnifyingglass")
                    }
                    .disabled(vm.isScanning)
                    Button(role: .destructive) {
                        confirmTrash = true
                    } label: {
                        Label("정리 (\(formatBytes(vm.selectedSize)))", systemImage: "trash")
                    }
                    .disabled(vm.isScanning || vm.selectedItems.isEmpty)
                }
            }

            Text("검색 대상: \(vm.roots.map(\.lastPathComponent).joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            if vm.isScanning {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(vm.scanProgress.phase.isEmpty ? "파일 내용을 비교하는 중..." : vm.scanProgress.phase)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TossColor.grey700)
                    Text("검사 \(vm.scanProgress.scanned)개 · 발견 \(vm.scanProgress.found)개")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                        .monospacedDigit()
                    if vm.scanProgress.skippedCloud + vm.scanProgress.skippedUnavailable > 0 {
                        Text("온라인 전용 \(vm.scanProgress.skippedCloud)개 · 접근 불가 \(vm.scanProgress.skippedUnavailable)개 제외")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(TossColor.grey400)
                    }
                    if !vm.scanProgress.currentPath.isEmpty {
                        Text(vm.scanProgress.currentPath)
                            .font(.caption)
                            .foregroundStyle(TossColor.grey400)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 520)
                    }
                    Button("스캔 취소") { vm.cancelScan() }
                        .buttonStyle(TossPillButtonStyle(
                            foreground: TossColor.grey700,
                            background: TossColor.grey100
                        ))
                }
                Spacer()
            } else if !vm.hasScanned {
                emptyState(icon: "doc.on.doc", message: "폴더를 정하고 스캔을 눌러 중복 파일을 찾아보세요")
            } else if vm.groups.isEmpty {
                emptyState(icon: "checkmark.circle", message: "중복 파일이 없습니다")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(vm.groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(group.files.count)개 동일 · 각 \(formatBytes(group.size))")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(TossColor.grey500)
                                    Spacer()
                                    Text("낭비 공간 \(formatBytes(group.wastedSize))")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(TossColor.orange)
                                }
                                .padding(.horizontal, 6)
                                TossList(items: group.files) { file in
                                HStack {
                                    Toggle(isOn: Binding(
                                        get: { vm.selected.contains(file.id) },
                                        set: { on in
                                            if on { vm.selected.insert(file.id) } else { vm.selected.remove(file.id) }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(file.name)
                                            Text(file.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                    }
                                    Spacer()
                                    Button {
                                        fileDetail = ScannedFileDetail(item: file)
                                    } label: {
                                        Image(systemName: "info.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("파일 상세 정보")
                                    .accessibilityLabel("\(file.name) 상세 정보")
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                    } label: {
                                        Image(systemName: "magnifyingglass.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Finder에서 보기")
                                    .accessibilityLabel("\(file.name) Finder에서 보기")
                                    Button {
                                        vm.exclude(file)
                                    } label: {
                                        Image(systemName: "nosign")
                                    }
                                    .buttonStyle(.plain)
                                    .help("다시 추천하지 않기")
                                    .accessibilityLabel("\(file.name) 제외 목록에 추가")
                                }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    Text("\(vm.groups.count)개 그룹 발견 · 체크된 파일만 삭제됩니다 (그룹마다 1개는 자동으로 남김)")
                        .font(.caption)
                        .foregroundStyle(TossColor.grey500)
                    Spacer()
                    Text("선택됨: \(vm.selectedItems.count)개 · \(formatBytes(vm.selectedSize))")
                        .foregroundStyle(TossColor.grey500)
                }
            }
        }
        .confirmationDialog(
            "선택한 \(vm.selectedItems.count)개 중복 파일(\(formatBytes(vm.selectedSize)))을 휴지통으로 이동할까요?",
            isPresented: $confirmTrash
        ) {
            Button("휴지통으로 이동", role: .destructive) { vm.trashSelected() }
            Button("취소", role: .cancel) {}
        }
        .sheet(item: $fileDetail) { detail in
            FileDetailView(detail: detail)
        }
        .alert(
            "중복 파일",
            isPresented: Binding(
                get: { vm.resultMessage != nil },
                set: { if !$0 { vm.resultMessage = nil } }
            )
        ) {
            Button("확인") { vm.resultMessage = nil }
        } message: {
            Text(vm.resultMessage ?? "")
        }
    }
}
