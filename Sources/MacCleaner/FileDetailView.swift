import AppKit
import SwiftUI

enum ScanItemSort: String, CaseIterable, Identifiable {
    case size = "크기순"
    case modified = "날짜순"
    case name = "이름순"

    var id: String { rawValue }

    func sorted(_ items: [CleanableItem]) -> [CleanableItem] {
        switch self {
        case .size:
            return items.sorted { $0.size > $1.size }
        case .modified:
            return items.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        case .name:
            return items.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }
}

struct ScannedFileDetail: Identifiable {
    let id = UUID()
    let item: CleanableItem
    let createdAt: Date?
    let modifiedAt: Date?
    let lastAccessedAt: Date?
    let volumeName: String
    let storageState: String

    init(item: CleanableItem) {
        self.item = item
        let values = try? item.url.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .volumeNameKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        createdAt = values?.creationDate
        modifiedAt = values?.contentModificationDate
        lastAccessedAt = values?.contentAccessDate
        volumeName = values?.volumeName ?? "알 수 없음"

        if FileManager.default.isUbiquitousItem(at: item.url) {
            switch values?.ubiquitousItemDownloadingStatus {
            case .current: storageState = "iCloud · 이 Mac에 다운로드됨"
            case .downloaded: storageState = "iCloud · 다운로드됨"
            default: storageState = "iCloud · 온라인 전용 가능"
            }
        } else if item.url.path.hasPrefix("/Volumes/") {
            storageState = "외장 또는 별도 볼륨"
        } else {
            storageState = "내장 저장 공간"
        }
    }
}

struct FileDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let detail: ScannedFileDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: detail.item.url.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(detail.item.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(TossColor.grey900)
                        .lineLimit(2)
                    Text(formatBytes(detail.item.size))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(TossColor.blue)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                row("최근 접근", dateText(detail.lastAccessedAt))
                Divider()
                row("수정일", dateText(detail.modifiedAt))
                Divider()
                row("생성일", dateText(detail.createdAt))
                Divider()
                row("저장 상태", detail.storageState)
                Divider()
                row("볼륨", detail.volumeName)
                Divider()
                row("경로", detail.item.url.path)
            }
            .padding(14)
            .background(TossColor.grey100)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([detail.item.url])
                } label: {
                    Label("Finder에서 보기", systemImage: "folder")
                }
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(TossColor.card)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(TossColor.grey700)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 7)
    }

    private func dateText(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "알 수 없음"
    }
}
