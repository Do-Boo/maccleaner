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
    BrandSidebarGroup(title: "개요", sections: [.dashboard, .smartScan, .permissions]),
    BrandSidebarGroup(title: "저장 공간", sections: [.junk, .largeFiles, .duplicates, .downloads]),
    BrandSidebarGroup(title: "응용 프로그램", sections: [.apps, .updater]),
    BrandSidebarGroup(title: "성능", sections: [.loginItems, .maintenance]),
    BrandSidebarGroup(title: "개인정보", sections: [.privacy, .shredder]),
    BrandSidebarGroup(title: "환경", sections: [.settings]),
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
        window.title = " "
        window.styleMask.remove(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
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
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(selection == .dashboard ? TossColor.canvas : TossColor.chrome)
        .overlay(alignment: .bottom) {
            if selection != .dashboard {
                Rectangle().fill(TossColor.line).frame(height: 1)
            }
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

struct WorkspaceCommandDeck: View {
    @Binding var selection: AppSection
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var dashboard: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(brandSidebarGroups.enumerated()), id: \.element.id) { index, group in
                        HStack(spacing: 3) {
                            ForEach(group.sections) { section in
                                commandButton(section)
                            }
                        }

                        if index < brandSidebarGroups.count - 1 {
                            Rectangle()
                                .fill(TossColor.line)
                                .frame(width: 1, height: 20)
                                .padding(.horizontal, 3)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            deckMetric(title: "CPU", value: "\(Int(monitor.cpu))%")
            deckDivider
            deckMetric(title: "메모리", value: "\(Int(monitor.memRatio * 100))%")
            deckDivider
            deckMetric(title: "남은 공간", value: formatBytes(dashboard.status.diskFree))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(TossColor.chrome)
        .overlay(alignment: .top) {
            Rectangle().fill(TossColor.line).frame(height: 1)
        }
        .onAppear {
            monitor.start()
            dashboard.refresh()
        }
    }

    private func commandButton(_ section: AppSection) -> some View {
        let active = selection == section
        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                selection = section
            }
        } label: {
            Image(systemName: section.icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(active ? .white : TossColor.grey400)
                .frame(width: 31, height: 30)
                .background(active ? TossColor.blue : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.rawValue)
        .accessibilityLabel(section.rawValue)
        .accessibilityValue(active ? "선택됨" : "")
    }

    private func deckMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(TossColor.grey400)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(TossColor.grey700)
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var deckDivider: some View {
        Rectangle()
            .fill(TossColor.line)
            .frame(width: 1, height: 24)
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
