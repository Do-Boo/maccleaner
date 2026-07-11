import SwiftUI

struct AppsView: View {
    @ObservedObject var vm: AppsViewModel
    @State private var searchText = ""
    @State private var sort = AppSort.size
    @State private var detailApp: AppInfo?

    private var filteredApps: [AppInfo] {
        let filtered = searchText.isEmpty ? vm.apps : vm.apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.bundleID?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        switch sort {
        case .size: return filtered.sorted { $0.size > $1.size }
        case .name: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent: return filtered.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "앱 및 관련 파일 삭제",
                subtitle: "앱과 선택한 설정·캐시 잔여 파일을 휴지통으로 이동합니다"
            ) {
                HStack(spacing: 10) {
                    searchField
                    Picker("정렬", selection: $sort) {
                        ForEach(AppSort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .frame(width: 105)
                    Button {
                        vm.scan()
                    } label: {
                        Label("불러오기", systemImage: "arrow.clockwise")
                    }
                    .disabled(vm.isScanning)
                }
            }

            if vm.isUninstalling {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("삭제 대상과 권한을 확인하는 중...")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 10)
                .accessibilityElement(children: .combine)
            }

            if vm.isScanning {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(vm.scanProgress.phase.isEmpty ? "설치된 앱을 확인하는 중..." : vm.scanProgress.phase)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TossColor.grey700)
                    Text("검사 \(vm.scanProgress.scanned)개 · 발견 \(vm.scanProgress.found)개")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                        .monospacedDigit()
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
                emptyState(
                    icon: "square.grid.2x2",
                    message: "'불러오기'를 눌러 설치된 앱을 확인하세요"
                )
            } else {
                HStack {
                    Text("총 설치된 프로그램 ")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TossColor.grey400)
                    + Text("\(filteredApps.count)개")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TossColor.blue)
                    + Text(" 발견")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TossColor.grey400)
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredApps) { app in
                            appCard(app)
                        }
                        if filteredApps.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 40))
                                    .foregroundStyle(TossColor.grey400)
                                Text("검색된 응용 프로그램이 없습니다.")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(TossColor.grey400)
                            }
                            .padding(.vertical, 60)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(item: $vm.pendingRemovalPlan) { plan in
            UninstallSheet(vm: vm, plan: plan)
        }
        .sheet(item: $detailApp) { app in
            AppDetailSheet(app: app)
        }
        .alert(
            "앱 관리",
            isPresented: Binding(
                get: { vm.resultMessage != nil },
                set: { if !$0 { vm.resultMessage = nil } }
            )
        ) {
            if vm.canRetryFailures {
                Button("실패 항목 재시도") { vm.retryFailedUninstall() }
            }
            Button("확인") { vm.resultMessage = nil }
        } message: {
            Text(vm.resultMessage ?? "")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TossColor.grey400)
            TextField("삭제할 앱 검색...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 13)
        .frame(width: 230, height: 38)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(TossColor.grey200)
        )
    }

    private func appCard(_ app: AppInfo) -> some View {
        HStack(spacing: 15) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TossColor.grey900)
                Text(app.bundleID ?? app.url.path)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(TossColor.grey400)
                    .lineLimit(1)
            }
            Spacer()
            Text(formatBytes(app.size))
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(TossColor.grey700)
            if vm.preparingAppID == app.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    detailApp = app
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help("앱 상세 정보")
                .accessibilityLabel("\(app.name) 상세 정보")
                Button("앱 및 파일 삭제", role: .destructive) {
                    vm.prepareUninstall(app)
                }
                .disabled(vm.preparingAppID != nil || vm.isUninstalling)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }
}

// MARK: - 토스 스타일 삭제 확인 모달

private struct UninstallSheet: View {
    @ObservedObject var vm: AppsViewModel
    let plan: AppRemovalPlan
    @State private var selectedPaths: Set<String>

    init(vm: AppsViewModel, plan: AppRemovalPlan) {
        self.vm = vm
        self.plan = plan
        _selectedPaths = State(initialValue: Set(plan.leftovers.map { $0.url.standardizedFileURL.path }))
    }

    private var selectedSize: Int64 {
        plan.app.size + plan.leftovers
            .filter { selectedPaths.contains($0.url.standardizedFileURL.path) }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TossColor.redLight)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "trash")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(TossColor.red)
                )
                .padding(.bottom, 18)

            Text("앱과 관련 파일을 삭제할까요?")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(TossColor.grey900)

            (
                Text("'\(plan.app.name)' 앱과 선택한 관련 항목, 총 ")
                    .foregroundColor(TossColor.grey500)
                + Text(formatBytes(selectedSize))
                    .foregroundColor(TossColor.red)
                    .fontWeight(.heavy)
                + Text("를 휴지통으로 이동합니다.")
                    .foregroundColor(TossColor.grey500)
            )
            .font(.system(size: 14, weight: .medium))
            .multilineTextAlignment(.center)
            .padding(.top, 10)

            if !plan.runningAppNames.isEmpty {
                noticeBox(
                    icon: "exclamationmark.triangle.fill",
                    title: "앱이 실행 중입니다",
                    text: "\(plan.runningAppNames.joined(separator: ", "))을(를) 종료한 뒤 삭제할 수 있습니다.",
                    tint: TossColor.orange,
                    background: TossColor.orangeLight
                )
                .padding(.top, 16)
            }

            if !plan.warnings.isEmpty {
                VStack(spacing: 8) {
                    ForEach(plan.warnings.prefix(4), id: \.self) { warning in
                        noticeBox(
                            icon: "info.circle.fill",
                            title: "확인 필요",
                            text: warning,
                            tint: TossColor.grey500,
                            background: TossColor.grey100
                        )
                    }
                }
                .padding(.top, 12)
            }

            // 삭제 대상 목록
            ScrollView {
                VStack(spacing: 0) {
                    sheetRow(name: plan.app.url.lastPathComponent, path: plan.app.url.path, size: plan.app.size)
                    ForEach(plan.leftovers) { item in
                        Divider().overlay(TossColor.grey200.opacity(0.5))
                        Toggle(isOn: Binding(
                            get: { selectedPaths.contains(item.url.standardizedFileURL.path) },
                            set: { isOn in
                                let path = item.url.standardizedFileURL.path
                                if isOn { selectedPaths.insert(path) } else { selectedPaths.remove(path) }
                            }
                        )) {
                            sheetRow(name: item.name, path: item.detail, size: item.size)
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            .padding(14)
            .background(TossColor.grey100)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 20)

            HStack(spacing: 12) {
                Button("취소") { vm.dismissRemovalPlan() }
                    .buttonStyle(TossNeutralProminentButtonStyle())
                if !plan.runningAppNames.isEmpty {
                    Button("앱 종료 요청") { vm.requestTerminatePendingApp() }
                        .buttonStyle(TossNeutralProminentButtonStyle())
                }
                Button("휴지통으로 이동") { vm.confirmUninstall(selectedLeftoverPaths: selectedPaths) }
                    .buttonStyle(TossDangerProminentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!plan.canUninstall || vm.isUninstalling)
            }
            .padding(.top, 24)
        }
        .padding(28)
        .frame(width: 500)
        .background(TossColor.card)
    }

    private func noticeBox(
        icon: String,
        title: String,
        text: String,
        tint: Color,
        background: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TossColor.grey700)
                Text(text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sheetRow(name: String, path: String, size: Int64) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(TossColor.grey700)
                Text(path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(TossColor.grey400)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(formatBytes(size))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(TossColor.grey500)
        }
        .padding(.vertical, 7)
    }
}

private enum AppSort: String, CaseIterable, Identifiable {
    case size = "크기순"
    case name = "이름순"
    case recent = "최근 사용"

    var id: String { rawValue }
}

private struct AppDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let app: AppInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(TossColor.grey900)
                    Text(app.bundleID ?? "번들 식별자 없음")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(TossColor.grey500)
                }
                Spacer()
            }

            VStack(spacing: 0) {
                detailRow("버전", app.version ?? "알 수 없음")
                Divider()
                detailRow("크기", formatBytes(app.size))
                Divider()
                detailRow("최근 접근", dateText(app.lastOpenedAt))
                Divider()
                detailRow("수정일", dateText(app.modifiedAt))
                Divider()
                detailRow("삭제 권한", app.isWritable ? "현재 사용자로 가능" : "관리자 권한 필요 가능")
                Divider()
                detailRow("위치", app.url.path)
            }
            .padding(14)
            .background(TossColor.grey100)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
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

    private func detailRow(_ title: String, _ value: String) -> some View {
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
