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

struct ContentView: View {
    @State private var selection: AppSection = .dashboard
    @State private var searchText = ""
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
        VStack(spacing: 0) {
            BrandTopBar(
                selection: selection,
                searchText: $searchText,
                onOpenMonitor: { openWindow(id: "monitor") },
                onSelect: { selection = $0 }
            )

            VStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TossColor.canvas)
                    .scrollIndicators(.hidden)

                WorkspaceCommandDeck(
                    selection: $selection,
                    monitor: MonitorModel.shared,
                    dashboard: dashboardVM
                )
            }
        }
        .frame(minWidth: 1040, minHeight: 720)
        .background(TossColor.canvas)
        .overlay {
            MacCleanerWindowConfigurator()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
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

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TossColor.grey200)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

}

/// 현재 화면의 설명과 주요 작업만 제공하는 공통 툴바
struct PageToolbar<Trailing: View>: View {
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            Text(subtitle)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(TossColor.grey500)
                .lineLimit(2)
            Spacer()
            trailing
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TossColor.line).frame(height: 1)
                .padding(.horizontal, 24)
        }
    }
}
