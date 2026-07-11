import SwiftUI
import ServiceManagement

// MARK: - 권한 진단

enum PermissionSeverity {
    case ok
    case warning
    case manual

    var title: String {
        switch self {
        case .ok: "정상"
        case .warning: "확인 필요"
        case .manual: "수동 확인"
        }
    }

    var tint: Color {
        switch self {
        case .ok: TossColor.mint
        case .warning: TossColor.orange
        case .manual: TossColor.grey500
        }
    }

    var background: Color {
        switch self {
        case .ok: TossColor.mintLight
        case .warning: TossColor.orangeLight
        case .manual: TossColor.grey100
        }
    }
}

enum PermissionSettingsDestination {
    case fullDiskAccess
    case filesAndFolders
    case automation
    case loginItems

    var url: URL? {
        let raw: String
        switch self {
        case .fullDiskAccess:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .filesAndFolders:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case .automation:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .loginItems:
            raw = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        }
        return URL(string: raw)
    }
}

struct PermissionCheck: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let detail: String
    let icon: String
    let severity: PermissionSeverity
    let destination: PermissionSettingsDestination?
}

enum PermissionDiagnostics {
    static func run() -> [PermissionCheck] {
        [
            downloadsAccess(),
            documentsAccess(),
            fullDiskAccess(),
            finderAutomation(),
            loginItemStatus(),
        ]
    }

    private static func downloadsAccess() -> PermissionCheck {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        return folderAccessCheck(
            title: "다운로드 폴더 접근",
            description: "다운로드 정리와 중복 파일 기본 스캔에 필요합니다.",
            icon: "arrow.down.circle",
            url: url,
            destination: .filesAndFolders
        )
    }

    private static func documentsAccess() -> PermissionCheck {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return folderAccessCheck(
            title: "문서 폴더 접근",
            description: "중복 파일 기본 스캔과 대용량 파일 탐색에 필요합니다.",
            icon: "doc.text",
            url: url,
            destination: .filesAndFolders
        )
    }

    private static func fullDiskAccess() -> PermissionCheck {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes = [
            home.appendingPathComponent("Library/Safari/History.db"),
            home.appendingPathComponent("Library/Messages/chat.db"),
            home.appendingPathComponent("Library/Mail"),
        ]
        let existing = probes.filter { FileManager.default.fileExists(atPath: $0.path) }
        let readable = existing.contains { FileManager.default.isReadableFile(atPath: $0.path) }

        if readable {
            return PermissionCheck(
                title: "전체 디스크 접근",
                description: "Safari 방문 기록, Mail 데이터 등 보호된 위치를 더 정확히 스캔합니다.",
                detail: "보호된 사용자 데이터 위치를 읽을 수 있습니다.",
                icon: "lock.shield",
                severity: .ok,
                destination: .fullDiskAccess
            )
        }

        return PermissionCheck(
            title: "전체 디스크 접근",
            description: "Safari 방문 기록, Mail 데이터 등 보호된 위치를 더 정확히 스캔합니다.",
            detail: existing.isEmpty
                ? "확인할 보호 데이터가 없어 수동 확인이 필요합니다."
                : "보호된 사용자 데이터 위치를 읽지 못했습니다.",
            icon: "lock.shield",
            severity: existing.isEmpty ? .manual : .warning,
            destination: .fullDiskAccess
        )
    }

    private static func finderAutomation() -> PermissionCheck {
        PermissionCheck(
            title: "Finder 자동화",
            description: "휴지통 비우기 기능에서 Finder 제어 권한이 필요합니다.",
            detail: "macOS는 자동화 권한 상태를 미리 읽기 어렵습니다. 휴지통 비우기 실패 시 이 설정을 확인하세요.",
            icon: "finder",
            severity: .manual,
            destination: .automation
        )
    }

    private static func loginItemStatus() -> PermissionCheck {
        let status = SMAppService.mainApp.status
        let enabled = status == .enabled
        return PermissionCheck(
            title: "로그인 시 자동 시작",
            description: "메뉴바 실시간 모니터를 로그인 후 자동으로 실행합니다.",
            detail: enabled ? "자동 시작이 켜져 있습니다." : "자동 시작이 꺼져 있거나 아직 등록되지 않았습니다.",
            icon: "power",
            severity: enabled ? .ok : .manual,
            destination: .loginItems
        )
    }

    private static func folderAccessCheck(
        title: String,
        description: String,
        icon: String,
        url: URL,
        destination: PermissionSettingsDestination
    ) -> PermissionCheck {
        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return PermissionCheck(
                title: title,
                description: description,
                detail: "\(url.path)을 읽을 수 있습니다.",
                icon: icon,
                severity: .ok,
                destination: destination
            )
        } catch {
            return PermissionCheck(
                title: title,
                description: description,
                detail: "\(url.path)을 읽지 못했습니다. \(error.localizedDescription)",
                icon: icon,
                severity: .warning,
                destination: destination
            )
        }
    }
}

@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published var checks: [PermissionCheck] = []
    @Published var isChecking = false

    func refresh() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                PermissionDiagnostics.run()
            }.value
            self.checks = result
            self.isChecking = false
        }
    }

    func openSettings(_ destination: PermissionSettingsDestination?) {
        guard let url = destination?.url else { return }
        NSWorkspace.shared.open(url)
    }
}

struct PermissionsView: View {
    @ObservedObject var vm: PermissionsViewModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "권한 진단",
                subtitle: "스캔 결과가 비거나 정리가 실패할 때 필요한 macOS 권한을 확인합니다"
            ) {
                Button {
                    vm.refresh()
                } label: {
                    Label("다시 진단", systemImage: "arrow.clockwise")
                }
                .disabled(vm.isChecking)
            }

            if vm.isChecking {
                Spacer()
                ProgressView("권한 상태를 확인하는 중...")
                Spacer()
            } else if vm.checks.isEmpty {
                emptyState(icon: "lock.shield", message: "권한 진단을 실행합니다")
                    .onAppear { vm.refresh() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary
                        TossList(items: vm.checks) { check in
                            row(check)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    Text("설정 변경 후 앱으로 돌아와 '다시 진단'을 누르세요.")
                        .font(.caption)
                        .foregroundStyle(TossColor.grey500)
                    Spacer()
                }
            }
        }
    }

    private var summary: some View {
        let warnings = vm.checks.filter { $0.severity == .warning }.count
        let manual = vm.checks.filter { $0.severity == .manual }.count
        return HStack(spacing: 12) {
            summaryTile(title: "정상", value: vm.checks.filter { $0.severity == .ok }.count, tint: TossColor.mint)
            summaryTile(title: "확인 필요", value: warnings, tint: TossColor.orange)
            summaryTile(title: "수동 확인", value: manual, tint: TossColor.grey500)
        }
    }

    private func summaryTile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(TossColor.grey500)
            Text("\(value)")
                .font(.system(size: 24, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func row(_ check: PermissionCheck) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(check.severity.background)
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: check.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(check.severity.tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(check.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TossColor.grey900)
                    Text(check.severity.title)
                        .font(.system(size: 10.5, weight: .heavy))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(check.severity.background)
                        .foregroundStyle(check.severity.tint)
                        .clipShape(Capsule())
                }
                Text(check.description)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
                Text(check.detail)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(TossColor.grey400)
                    .lineLimit(2)
            }

            Spacer()
            Button {
                vm.openSettings(check.destination)
            } label: {
                Label("설정 열기", systemImage: "gearshape")
            }
            .disabled(check.destination == nil)
        }
        .padding(.vertical, 4)
    }
}
