import SwiftUI

// MARK: - 정리 기록

struct CleanupHistoryRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let action: String
    let itemCount: Int
    let freedBytes: Int64
    let failedCount: Int
    let errors: [String]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        action: String,
        itemCount: Int,
        freedBytes: Int64,
        failedCount: Int,
        errors: [String]
    ) {
        self.id = id
        self.date = date
        self.action = action
        self.itemCount = itemCount
        self.freedBytes = freedBytes
        self.failedCount = failedCount
        self.errors = errors
    }
}

@MainActor
final class CleanupHistoryStore: ObservableObject {
    static let shared = CleanupHistoryStore()

    @Published private(set) var records: [CleanupHistoryRecord] = []

    private let key = "cleanup.history.records.v1"
    private let limit = 120

    private init() {
        records = Self.load(key: key)
    }

    func add(action: String, itemCount: Int, freedBytes: Int64, errors: [String]) {
        let record = CleanupHistoryRecord(
            action: action,
            itemCount: itemCount,
            freedBytes: freedBytes,
            failedCount: errors.count,
            errors: Array(errors.prefix(6))
        )
        records.insert(record, at: 0)
        if records.count > limit {
            records = Array(records.prefix(limit))
        }
        save()
    }

    func clear() {
        records = []
        save()
    }

    func openTrash() {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        NSWorkspace.shared.open(trash)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load(key: String) -> [CleanupHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([CleanupHistoryRecord].self, from: data) else {
            return []
        }
        return records
    }
}

// MARK: - 제외 목록

enum ExclusionRules {
    static let key = "cleanup.exclusion.paths.v1"

    static func snapshot() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func isExcluded(_ url: URL, in paths: [String]) -> Bool {
        let path = normalizedPath(url)
        return paths.contains { excluded in
            path == excluded || path.hasPrefix(excluded + "/")
        }
    }

    static func normalizedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.count > 1 else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

@MainActor
final class ExclusionStore: ObservableObject {
    static let shared = ExclusionStore()

    @Published private(set) var paths: [String] = []

    private init() {
        paths = ExclusionRules.snapshot()
    }

    func isExcluded(_ url: URL) -> Bool {
        ExclusionRules.isExcluded(url, in: paths)
    }

    func add(_ url: URL) {
        let path = ExclusionRules.normalizedPath(url)
        guard !paths.contains(path) else { return }
        paths.append(path)
        paths.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        save()
    }

    func add(_ item: CleanableItem) {
        add(item.url)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "제외"
        panel.message = "스캔 결과에서 제외할 파일이나 폴더를 선택하세요"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(add)
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
        save()
    }

    func clear() {
        paths = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(paths, forKey: ExclusionRules.key)
    }
}

// MARK: - 설정

struct SettingsView: View {
    @ObservedObject var history: CleanupHistoryStore
    @ObservedObject var exclusions: ExclusionStore

    @AppStorage("settings.defaultDownloadMonths") private var defaultDownloadMonths = 6
    @State private var diagnosticMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "설정",
                subtitle: "정리 기록, 제외 목록, 기본 스캔 옵션을 관리합니다"
            ) {
                Button {
                    exclusions.chooseFolder()
                } label: {
                    Label("제외 항목 추가", systemImage: "plus")
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    optionsSection
                    diagnosticsSection
                    exclusionsSection
                    historySection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .alert(
            "진단 보고서",
            isPresented: Binding(
                get: { diagnosticMessage != nil },
                set: { if !$0 { diagnosticMessage = nil } }
            )
        ) {
            Button("확인") { diagnosticMessage = nil }
        } message: {
            Text(diagnosticMessage ?? "")
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TossSectionTitle(text: "진단 및 지원")
            VStack(spacing: 0) {
                settingRow(
                    icon: "doc.text.magnifyingglass",
                    title: "진단 보고서 내보내기",
                    subtitle: "운영체제 정보와 최근 정리 오류를 텍스트 파일로 저장합니다"
                ) {
                    Button {
                        switch DiagnosticReport.export(
                            history: history.records,
                            exclusions: exclusions.paths
                        ) {
                        case .cancelled:
                            break
                        case .saved:
                            diagnosticMessage = "진단 보고서를 저장했습니다."
                        case .failed(let error):
                            diagnosticMessage = "보고서를 저장하지 못했습니다: \(error)"
                        }
                    } label: {
                        Label("내보내기", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .background(TossColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TossColor.line)
            )
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TossSectionTitle(text: "기본 옵션")
            VStack(spacing: 0) {
                settingRow(
                    icon: "calendar",
                    title: "다운로드 정리 기본 기준",
                    subtitle: "다운로드 정리 화면의 기본 기간입니다"
                ) {
                    BrandMenuPicker(
                        title: "기본 기간",
                        selection: $defaultDownloadMonths,
                        options: [
                            (1, "1개월"),
                            (3, "3개월"),
                            (6, "6개월"),
                            (12, "1년"),
                        ]
                    )
                    .frame(width: 130)
                }
            }
            .background(TossColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TossColor.line)
            )
        }
    }

    private var exclusionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TossSectionTitle(text: "제외 목록", trailing: "\(exclusions.paths.count)개")
            if exclusions.paths.isEmpty {
                compactEmptyCard(icon: "nosign", text: "제외된 파일이나 폴더가 없습니다.")
            } else {
                TossList(items: exclusions.paths.map(ExclusionPath.init)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "nosign")
                            .foregroundStyle(TossColor.grey400)
                            .frame(width: 22)
                        Text(item.path)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(TossColor.grey700)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            exclusions.remove(item.path)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .help("제외 목록에서 제거")
                        .accessibilityLabel("\(item.path) 제외 목록에서 제거")
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TossSectionTitle(text: "정리 기록", trailing: "\(history.records.count)개")
                Spacer()
                Button {
                    history.openTrash()
                } label: {
                    Label("휴지통 열기", systemImage: "trash")
                }
                Button(role: .destructive) {
                    history.clear()
                } label: {
                    Label("기록 지우기", systemImage: "xmark.circle")
                }
                .disabled(history.records.isEmpty)
            }

            if history.records.isEmpty {
                compactEmptyCard(icon: "clock.arrow.circlepath", text: "아직 정리 기록이 없습니다.")
            } else {
                TossList(items: history.records) { record in
                    historyRow(record)
                }
            }
        }
    }

    private func settingRow<Trailing: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(TossColor.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(TossColor.grey900)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func historyRow(_ record: CleanupHistoryRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(record.failedCount > 0 ? TossColor.orange : TossColor.mint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(record.action)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(TossColor.grey900)
                    Text(record.date, style: .date)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TossColor.grey400)
                    Text(record.date, style: .time)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TossColor.grey400)
                }
                Text("\(record.itemCount)개 항목 · \(formatBytes(record.freedBytes)) 확보 · 실패 \(record.failedCount)건")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
                if let firstError = record.errors.first {
                    Text(firstError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TossColor.grey400)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
    }

    private func compactEmptyCard(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(TossColor.grey400)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TossColor.grey500)
            Spacer()
        }
        .padding(16)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TossColor.line)
        )
    }
}

private struct ExclusionPath: Identifiable {
    let path: String
    var id: String { path }
}
