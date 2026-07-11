import AppKit
import SwiftUI

extension Notification.Name {
    static let focusBrandSearch = Notification.Name("MacCleaner.focusBrandSearch")
}

struct BrandSidebarGroup: Identifiable {
    let title: String
    let sections: [AppSection]
    var id: String { title }
}

let brandSidebarGroups = [
    BrandSidebarGroup(title: "OVERVIEW", sections: [.dashboard, .smartScan, .permissions]),
    BrandSidebarGroup(title: "STORAGE", sections: [.junk, .largeFiles, .duplicates, .downloads]),
    BrandSidebarGroup(title: "APPLICATIONS", sections: [.apps, .updater]),
    BrandSidebarGroup(title: "PERFORMANCE", sections: [.loginItems, .maintenance]),
    BrandSidebarGroup(title: "PRIVACY", sections: [.privacy, .shredder]),
    BrandSidebarGroup(title: "SYSTEM", sections: [.settings]),
]

extension AppSection {
    var summary: String {
        switch self {
        case .dashboard: "저장 공간과 시스템 상태를 한눈에 확인합니다"
        case .smartScan: "여러 정리 항목을 한 번에 분석합니다"
        case .permissions: "기능별 macOS 접근 권한을 점검합니다"
        case .junk: "캐시, 로그, 개발 데이터를 정리합니다"
        case .largeFiles: "공간을 많이 차지하는 파일을 찾습니다"
        case .duplicates: "내용이 같은 파일을 비교합니다"
        case .downloads: "오래 사용하지 않은 다운로드를 찾습니다"
        case .apps: "앱과 사용자가 선택한 관련 파일을 제거합니다"
        case .updater: "Homebrew 패키지 업데이트를 확인합니다"
        case .loginItems: "로그인 시 실행되는 항목을 관리합니다"
        case .maintenance: "DNS, Spotlight, Finder 작업을 실행합니다"
        case .privacy: "브라우저 데이터와 캐시를 정리합니다"
        case .shredder: "민감한 파일의 복구 가능성을 낮춥니다"
        case .settings: "제외 목록과 정리 기록을 관리합니다"
        }
    }
}

struct MacCleanerWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.backgroundColor = .windowBackgroundColor
        window.setFrameAutosaveName("MacCleanerMainWindow")

        hideScrollIndicators(in: window.contentView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hideScrollIndicators(in: window.contentView)
        }
    }

    private func hideScrollIndicators(in view: NSView?) {
        guard let view else { return }
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
        for subview in view.subviews {
            hideScrollIndicators(in: subview)
        }
    }
}

struct BrandTopBar: View {
    let selection: AppSection
    @Binding var searchText: String
    let sidebarCollapsed: Bool
    let inspectorVisible: Bool
    let onToggleSidebar: () -> Void
    let onToggleInspector: () -> Void
    let onOpenMonitor: () -> Void
    let onSelect: (AppSection) -> Void

    @FocusState private var searchFocused: Bool

    private var searchResults: [AppSection] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return AppSection.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(searchText)
                || $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 66)

            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(TossColor.blue)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            Text("MacCleaner")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TossColor.grey900)

            Rectangle()
                .fill(TossColor.line)
                .frame(width: 1, height: 18)

            Text(selection.rawValue)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(TossColor.grey500)

            Spacer(minLength: 20)

            searchField

            BrandIconButton(
                icon: "waveform.path.ecg",
                help: "실시간 모니터 열기",
                action: onOpenMonitor
            )
            BrandIconButton(
                icon: inspectorVisible ? "sidebar.trailing" : "sidebar.trailing",
                help: inspectorVisible ? "상태 패널 닫기" : "상태 패널 열기",
                isActive: inspectorVisible,
                action: onToggleInspector
            )
            BrandIconButton(
                icon: sidebarCollapsed ? "sidebar.left" : "sidebar.left",
                help: sidebarCollapsed ? "사이드바 펼치기" : "사이드바 접기",
                isActive: !sidebarCollapsed,
                action: onToggleSidebar
            )
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(TossColor.chrome)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TossColor.line).frame(height: 1)
        }
        .overlay(alignment: .topTrailing) {
            if searchFocused && !searchText.isEmpty {
                searchResultsPanel
                    .offset(x: -142, y: 50)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusBrandSearch)) { _ in
            searchFocused = true
        }
        .zIndex(20)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TossColor.grey400)
            TextField("기능 검색", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .focused($searchFocused)
                .onSubmit {
                    if let first = searchResults.first {
                        onSelect(first)
                        searchText = ""
                        searchFocused = false
                    }
                }
            Text("⌘K")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(TossColor.grey400)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(TossColor.grey100)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .padding(.horizontal, 11)
        .frame(width: 232, height: 34)
        .background(TossColor.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(searchFocused ? TossColor.blue : TossColor.line, lineWidth: 1)
        )
    }

    private var searchResultsPanel: some View {
        VStack(spacing: 0) {
            if searchResults.isEmpty {
                Text("일치하는 기능이 없습니다")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ForEach(searchResults.prefix(6)) { section in
                    Button {
                        onSelect(section)
                        searchText = ""
                        searchFocused = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .foregroundStyle(TossColor.blue)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.rawValue)
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(TossColor.grey900)
                                Text(section.summary)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(TossColor.grey500)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.turn.down.left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(TossColor.grey400)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 310)
        .background(TossColor.chrome)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(TossColor.line)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }
}

struct BrandSidebar: View {
    @Binding var selection: AppSection
    let collapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: collapsed ? 14 : 20) {
                    ForEach(brandSidebarGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            if collapsed {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 28, height: 1)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(group.title)
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.36))
                                    .tracking(0.8)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 2)
                            }

                            ForEach(group.sections) { section in
                                navigationItem(section)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 16)
            }

            deviceStatus
                .padding(10)
        }
        .frame(width: collapsed ? 68 : 224)
        .background(TossColor.sidebar)
        .animation(.easeInOut(duration: 0.18), value: collapsed)
    }

    private func navigationItem(_ section: AppSection) -> some View {
        let active = selection == section
        return Button {
            withAnimation(.easeOut(duration: 0.14)) {
                selection = section
            }
        } label: {
            HStack(spacing: 11) {
                Rectangle()
                    .fill(active ? TossColor.blue : .clear)
                    .frame(width: 3, height: 22)

                Image(systemName: section.icon)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(active ? .white : Color.white.opacity(0.52))
                    .frame(width: 20)

                if !collapsed {
                    Text(section.rawValue)
                        .font(.system(size: 12.5, weight: active ? .bold : .medium))
                        .foregroundStyle(active ? .white : Color.white.opacity(0.68))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 10)
            .frame(height: 36)
            .background(active ? Color.white.opacity(0.11) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? section.rawValue : "")
        .accessibilityLabel(section.rawValue)
    }

    private var deviceStatus: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                Circle().fill(TossColor.mint).frame(width: 8, height: 8)
            }
            .frame(width: 30, height: 30)

            if !collapsed {
                VStack(alignment: .leading, spacing: 2) {
                    Text(machineChipName())
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("실시간 진단 중")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(collapsed ? 8 : 10)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SystemPulsePanel: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var dashboard: DashboardViewModel
    @ObservedObject var history: CleanupHistoryStore
    let selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(TossColor.mint).frame(width: 7, height: 7)
                Text("SYSTEM PULSE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TossColor.grey500)
                    .tracking(0.8)
                Spacer()
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(TossColor.mint)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)

            panelDivider

            VStack(spacing: 16) {
                metric(title: "CPU", value: monitor.cpu / 100, text: "\(Int(monitor.cpu))%", tint: TossColor.blue)
                metric(title: "MEMORY", value: monitor.memRatio, text: "\(Int(monitor.memRatio * 100))%", tint: TossColor.mint)

                HStack {
                    Text("DISK FREE")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(TossColor.grey400)
                        .tracking(0.5)
                    Spacer()
                    Text(formatBytes(dashboard.status.diskFree))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(TossColor.orange)
                }
            }
            .padding(18)

            panelDivider

            VStack(alignment: .leading, spacing: 10) {
                panelLabel("CURRENT WORKSPACE")
                HStack(spacing: 10) {
                    Image(systemName: selection.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(TossColor.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selection.rawValue)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(TossColor.grey900)
                        Text(selection.summary)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(TossColor.grey500)
                            .lineLimit(2)
                    }
                }
            }
            .padding(18)

            panelDivider

            VStack(alignment: .leading, spacing: 12) {
                panelLabel("RECENT ACTIVITY")
                if history.records.isEmpty {
                    Text("정리 기록이 아직 없습니다")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TossColor.grey400)
                } else {
                    ForEach(history.records.prefix(3)) { record in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(record.failedCount == 0 ? TossColor.mint : TossColor.orange)
                                .frame(width: 6, height: 6)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.action)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(TossColor.grey700)
                                    .lineLimit(1)
                                Text("\(record.itemCount)개 · \(formatBytes(record.freedBytes))")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(TossColor.grey400)
                            }
                        }
                    }
                }
            }
            .padding(18)

            Spacer()
        }
        .frame(width: 252)
        .background(TossColor.inspector)
        .overlay(alignment: .leading) {
            Rectangle().fill(TossColor.line).frame(width: 1)
        }
        .onAppear {
            monitor.start()
            dashboard.refresh()
        }
    }

    private func metric(title: String, value: Double, text: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(TossColor.grey400)
                    .tracking(0.5)
                Spacer()
                Text(text)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(TossColor.grey700)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(TossColor.grey200)
                    Rectangle()
                        .fill(tint)
                        .frame(width: geometry.size.width * min(max(value, 0), 1))
                        .animation(.easeOut(duration: 0.5), value: value)
                }
            }
            .frame(height: 4)
        }
    }

    private func panelLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(TossColor.grey400)
            .tracking(0.7)
    }

    private var panelDivider: some View {
        Rectangle().fill(TossColor.line).frame(height: 1)
    }
}

struct BrandIconButton: View {
    let icon: String
    let help: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isActive ? TossColor.blue : TossColor.grey500)
                .frame(width: 32, height: 32)
                .background(isActive ? TossColor.blueLight : TossColor.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isActive ? TossColor.blue.opacity(0.25) : TossColor.line)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct BrandMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    private var selectedTitle: String {
        options.first { $0.value == selection }?.title ?? title
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TossColor.grey700)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(TossColor.grey400)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(TossColor.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TossColor.line)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(title)
        .accessibilityValue(selectedTitle)
    }
}

struct BrandSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? TossColor.blue : TossColor.grey200)
                        .frame(width: 38, height: 22)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "켬" : "끔")
    }
}
