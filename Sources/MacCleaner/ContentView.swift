import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "대시보드"
    case smartScan = "스마트 스캔"
    case permissions = "권한 진단"
    case junk = "시스템 정리"
    case largeFiles = "대용량 파일"
    case duplicates = "중복 파일"
    case downloads = "다운로드 정리"
    case apps = "앱 및 관련 파일 삭제"
    case updater = "업데이터"
    case loginItems = "시작 프로그램"
    case maintenance = "유지보수"
    case privacy = "개인정보"
    case shredder = "셰레더"
    case settings = "설정"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .smartScan: "bolt.fill"
        case .permissions: "lock.shield"
        case .junk: "sparkles"
        case .largeFiles: "externaldrive"
        case .duplicates: "doc.on.doc"
        case .downloads: "arrow.down.circle"
        case .apps: "trash"
        case .updater: "arrow.triangle.2.circlepath"
        case .loginItems: "power"
        case .maintenance: "wrench.and.screwdriver"
        case .privacy: "hand.raised"
        case .shredder: "flame"
        case .settings: "gearshape"
        }
    }
}

/// 사이드바 그룹 구성
private let sidebarGroups: [(title: String, sections: [AppSection])] = [
    ("분석 및 비우기", [.dashboard, .smartScan, .permissions]),
    ("정리", [.junk, .largeFiles, .duplicates, .downloads]),
    ("앱", [.apps, .updater]),
    ("속도", [.loginItems, .maintenance]),
    ("보안", [.privacy, .shredder]),
    ("관리", [.settings]),
]

struct ContentView: View {
    @State private var selection: AppSection? = .dashboard
    @StateObject private var dashboardVM = DashboardViewModel()
    @StateObject private var smartScanVM = SmartScanViewModel()
    @StateObject private var permissionsVM = PermissionsViewModel()
    @StateObject private var junkVM = JunkViewModel()
    @StateObject private var largeFilesVM = LargeFilesViewModel()
    @StateObject private var duplicatesVM = DuplicatesViewModel()
    @StateObject private var downloadsVM = DownloadsViewModel()
    @StateObject private var appsVM = AppsViewModel()
    @StateObject private var updaterVM = UpdaterViewModel()
    @StateObject private var loginItemsVM = LoginItemsViewModel()
    @StateObject private var maintenanceVM = MaintenanceViewModel()
    @StateObject private var privacyVM = PrivacyViewModel()
    @StateObject private var shredderVM = ShredderViewModel()
    @StateObject private var historyStore = CleanupHistoryStore.shared
    @StateObject private var exclusionStore = ExclusionStore.shared
    @StateObject private var undoStore = TrashUndoStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 235, ideal: 250)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard:
                    DashboardView(vm: dashboardVM, selection: $selection) {
                        selection = .smartScan
                        smartScanVM.scan()
                    }
                case .smartScan:
                    SmartScanView(vm: smartScanVM)
                case .permissions:
                    PermissionsView(vm: permissionsVM)
                case .junk:
                    JunkView(vm: junkVM)
                case .largeFiles:
                    LargeFilesView(vm: largeFilesVM)
                case .duplicates:
                    DuplicatesView(vm: duplicatesVM)
                case .downloads:
                    DownloadsView(vm: downloadsVM)
                case .apps:
                    AppsView(vm: appsVM)
                case .updater:
                    UpdaterView(vm: updaterVM)
                case .loginItems:
                    LoginItemsView(vm: loginItemsVM)
                case .maintenance:
                    MaintenanceView(vm: maintenanceVM)
                case .privacy:
                    PrivacyView(vm: privacyVM)
                case .shredder:
                    ShredderView(vm: shredderVM)
                case .settings:
                    SettingsView(history: historyStore, exclusions: exclusionStore)
                }
            }
            .background(TossColor.bg)
        }
        .frame(minWidth: 980, minHeight: 680)
        .navigationTitle("MacCleaner")
        // 토스 디자인 시스템 전역 적용
        .tint(TossColor.blue)
        .buttonStyle(TossButtonStyle())
        .groupBoxStyle(TossGroupBoxStyle())
        .toggleStyle(TossCheckboxStyle())
        .overlay(alignment: .bottomTrailing) {
            if let session = undoStore.latest {
                undoBanner(session)
                    .padding(18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: undoStore.latest?.id)
        .alert(
            "복원 결과",
            isPresented: Binding(
                get: { undoStore.resultMessage != nil },
                set: { if !$0 { undoStore.resultMessage = nil } }
            )
        ) {
            Button("확인") { undoStore.resultMessage = nil }
        } message: {
            Text(undoStore.resultMessage ?? "")
        }
    }

    // MARK: - 사이드바

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sidebarGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(TossColor.grey400)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 5)
                            ForEach(group.sections) { section in
                                navItem(section)
                            }
                        }
                    }

                    monitorSection
                }
                .padding(12)
            }
            deviceCard
                .padding(12)
        }
        .background(TossColor.card)
    }

    private func undoBanner(_ session: TrashUndoSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(TossColor.blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.action)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TossColor.grey900)
                Text("\(session.moves.count)개 항목을 휴지통으로 이동했습니다")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
            }
            Button(undoStore.isRestoring ? "복원 중" : "되돌리기") {
                undoStore.undoLatest()
            }
            .disabled(undoStore.isRestoring)
            Button {
                undoStore.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("닫기")
            .accessibilityLabel("되돌리기 알림 닫기")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TossColor.grey200)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func navItem(_ section: AppSection) -> some View {
        let active = (selection ?? .dashboard) == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? TossColor.blue : TossColor.grey400)
                    .frame(width: 20)
                Text(section.rawValue)
                    .font(.system(size: 13.5, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? TossColor.blue : TossColor.grey700)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(active ? TossColor.blueLight : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var monitorSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle()
                .fill(TossColor.grey100)
                .frame(height: 1)
                .padding(.bottom, 10)
            Text("실시간 도구")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TossColor.grey400)
                .padding(.horizontal, 12)
                .padding(.bottom, 5)
            Button {
                openWindow(id: "monitor")
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(TossColor.mint)
                        .frame(width: 8, height: 8)
                    Text("실시간 플로팅 창")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TossColor.grey700)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TossColor.grey400)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(TossColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TossColor.grey200)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var deviceCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(TossColor.mint)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(machineChipName())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TossColor.grey700)
                    .lineLimit(1)
                Text("정밀 진단 활성화됨")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TossColor.grey400)
            }
            Spacer()
        }
        .padding(12)
        .background(TossColor.grey50)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TossColor.grey200.opacity(0.6))
        )
    }
}

/// 화면 상단 공통 헤더
struct SectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(TossColor.grey900)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}
