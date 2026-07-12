import SwiftUI

// MARK: - 오래된 다운로드 정리

enum DownloadsScanner {
    /// 다운로드 폴더에서 일정 기간 수정되지 않은 항목 탐색
    static func scan(olderThanMonths months: Int) -> [CleanableItem] {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()),
              let children = try? FileManager.default.contentsOfDirectory(
                  at: downloads,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let excludedPaths = ExclusionRules.snapshot()
        var items: [CleanableItem] = []
        for url in children {
            guard !ExclusionRules.isExcluded(url, in: excludedPaths) else { continue }
            guard !StorageAvailability.isOnlineOnlyUbiquitousItem(url) else { continue }
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate,
                modified < cutoff else { continue }
            let size = FileSizer.itemSize(url)
            guard size > 0 else { continue }
            items.append(CleanableItem(
                url: url,
                name: url.lastPathComponent,
                detail: "마지막 수정 \(formatter.string(from: modified))",
                size: size,
                modifiedAt: modified
            ))
        }
        return items.sorted { $0.size > $1.size }
    }
}

@MainActor
final class DownloadsViewModel: ObservableObject {
    @Published var items: [CleanableItem] = []
    @Published var selected: Set<UUID> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var months = 6
    @Published var resultMessage: String?

    init() {
        let storedMonths = UserDefaults.standard.integer(forKey: "settings.defaultDownloadMonths")
        if storedMonths > 0 {
            months = storedMonths
        }
    }

    var selectedItems: [CleanableItem] { items.filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let months = months
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                DownloadsScanner.scan(olderThanMonths: months)
            }.value
            self.items = result
            self.selected = []
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func trashSelected() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        isScanning = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Cleaner.trash(urls) }.value
            var message = "\(outcome.succeeded)개 항목을 휴지통으로 이동했습니다 (\(formatBytes(outcome.freed)) 확보)."
            if !outcome.errors.isEmpty { message += "\n실패 \(outcome.errors.count)건" }
            CleanupRecorder.record(action: "다운로드 정리", outcome: outcome)
            self.resultMessage = message
            let movedPaths = Set(outcome.moved.map { $0.originalURL.standardizedFileURL.path })
            self.items.removeAll { movedPaths.contains($0.url.standardizedFileURL.path) }
            let failedPaths = Set(outcome.failures.map { $0.url.standardizedFileURL.path })
            self.selected = Set(self.items.filter {
                failedPaths.contains($0.url.standardizedFileURL.path)
            }.map(\.id))
            self.isScanning = false
        }
    }

    func exclude(_ item: CleanableItem) {
        ExclusionStore.shared.add(item)
        items.removeAll { $0.id == item.id }
        selected.remove(item.id)
        resultMessage = "'\(item.name)'을(를) 제외 목록에 추가했습니다."
    }
}

struct DownloadsView: View {
    @ObservedObject var vm: DownloadsViewModel
    @State private var confirmTrash = false
    @State private var fileDetail: ScannedFileDetail?
    @State private var sort = ScanItemSort.modified

    private var sortedItems: [CleanableItem] {
        sort.sorted(vm.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageToolbar(
                subtitle: "다운로드 폴더에서 오랫동안 손대지 않은 항목을 찾습니다"
            ) {
                HStack {
                    BrandMenuPicker(
                        title: "기간",
                        selection: $vm.months,
                        options: [
                            (1, "1개월 이상"),
                            (3, "3개월 이상"),
                            (6, "6개월 이상"),
                            (12, "1년 이상"),
                        ]
                    )
                    .frame(width: 150)
                    BrandMenuPicker(
                        title: "정렬",
                        selection: $sort,
                        options: ScanItemSort.allCases.map { ($0, $0.rawValue) }
                    )
                    .frame(width: 100)

                    Button {
                        vm.scan()
                    } label: {
                        Label("스캔", systemImage: "magnifyingglass")
                    }
                    .disabled(vm.isScanning)

                    Button(role: .destructive) {
                        confirmTrash = true
                    } label: {
                        Label("삭제 (\(formatBytes(vm.selectedSize)))", systemImage: "trash")
                    }
                    .disabled(vm.isScanning || vm.selectedItems.isEmpty)
                }
            }

            if vm.isScanning {
                Spacer()
                ProgressView("다운로드 폴더를 확인하는 중...")
                Spacer()
            } else if !vm.hasScanned {
                emptyState(icon: "arrow.down.circle", message: "기간을 정하고 스캔을 눌러보세요")
            } else if vm.items.isEmpty {
                emptyState(icon: "checkmark.circle", message: "해당 기간보다 오래된 항목이 없습니다")
            } else {
                ScrollView(showsIndicators: false) {
                    TossList(items: sortedItems) { item in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { vm.selected.contains(item.id) },
                                set: { on in
                                    if on { vm.selected.insert(item.id) } else { vm.selected.remove(item.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(formatBytes(item.size))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button {
                                fileDetail = ScannedFileDetail(item: item)
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                            .help("파일 상세 정보")
                            .accessibilityLabel("\(item.name) 상세 정보")
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: {
                                Image(systemName: "magnifyingglass.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Finder에서 보기")
                            .accessibilityLabel("\(item.name) Finder에서 보기")
                            Button {
                                vm.exclude(item)
                            } label: {
                                Image(systemName: "nosign")
                            }
                            .buttonStyle(.plain)
                            .help("다시 추천하지 않기")
                            .accessibilityLabel("\(item.name) 제외 목록에 추가")
                        }
                        .padding(.vertical, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    Button("전체 선택") { vm.selected = Set(vm.items.map(\.id)) }
                    Button("전체 해제") { vm.selected = [] }
                    Spacer()
                    Text("선택됨: \(vm.selectedItems.count)개 · \(formatBytes(vm.selectedSize))")
                        .foregroundStyle(TossColor.grey500)
                }
            }
        }
        .confirmationDialog(
            "선택한 \(vm.selectedItems.count)개 항목(\(formatBytes(vm.selectedSize)))을 휴지통으로 이동할까요?",
            isPresented: $confirmTrash
        ) {
            Button("휴지통으로 이동", role: .destructive) { vm.trashSelected() }
            Button("취소", role: .cancel) {}
        }
        .sheet(item: $fileDetail) { detail in
            FileDetailView(detail: detail)
        }
        .alert(
            "삭제 완료",
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
