import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: DashboardViewModel
    @Binding var selection: AppSection
    var onQuickOptimize: () -> Void = {}
    @State private var confirmEmptyTrash = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mac 상태")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(TossColor.grey900)
                        Text("저장 공간과 메모리 상태를 확인하고 필요한 작업을 실행합니다")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(TossColor.grey500)
                    }
                    Spacer()
                    Button {
                        onQuickOptimize()
                    } label: {
                        Label("빠른 최적화", systemImage: "bolt.fill")
                    }
                    .buttonStyle(TossPillButtonStyle())
                }

                systemOverview

                sectionTitle("권장 작업")
                VStack(spacing: 0) {
                    actionCard(
                        icon: "memorychip",
                        tint: TossColor.blue,
                        tintBG: TossColor.blueLight,
                        title: "비활성 앱 정리 및 램 해제",
                        description: "안 쓰는 시스템 캐시 메모리를 모아 해제합니다. (관리자 암호 필요)"
                    ) {
                        Button("메모리 확보하기") { vm.freeMemory() }
                            .buttonStyle(TossPillButtonStyle())
                    }

                    actionDivider

                    actionCard(
                        icon: "trash",
                        tint: TossColor.orange,
                        tintBG: TossColor.orangeLight,
                        title: "휴지통 임시 정크 비우기",
                        badge: vm.status.trashSize > 0 ? formatBytes(vm.status.trashSize) : "깨끗함",
                        badgeTint: vm.status.trashSize > 0 ? TossColor.orange : TossColor.mint,
                        badgeBG: vm.status.trashSize > 0 ? TossColor.orangeLight : TossColor.mintLight,
                        description: "휴지통에 쌓인 파일을 완전히 지웁니다. 이 작업은 되돌릴 수 없어요."
                    ) {
                        Button(vm.status.trashSize > 0 ? "비우기 실행" : "비우기 완료") {
                            confirmEmptyTrash = true
                        }
                        .buttonStyle(TossPillButtonStyle(
                            foreground: vm.status.trashSize > 0 ? TossColor.orange : TossColor.grey400,
                            background: vm.status.trashSize > 0 ? TossColor.orangeLight : TossColor.grey100
                        ))
                        .disabled(vm.status.trashSize == 0)
                    }

                    actionDivider

                    actionCard(
                        icon: "power",
                        tint: TossColor.mint,
                        tintBG: TossColor.mintLight,
                        title: "로그인 시 자동 시작",
                        description: "맥을 켜면 메뉴바 모니터가 자동으로 실행됩니다."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { vm.launchAtLogin },
                            set: { vm.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(BrandSwitchToggleStyle())
                        .labelsHidden()
                    }
                }
                .background(TossColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TossColor.line)
                )

                sectionTitle("빠른 실행")
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                    spacing: 10
                ) {
                    quickButton(.junk, description: "캐시·로그 정리")
                    quickButton(.largeFiles, description: "큰 파일 찾기")
                    quickButton(.duplicates, description: "같은 파일 정리")
                    quickButton(.apps, description: "앱 완전 삭제")
                    quickButton(.downloads, description: "묵은 다운로드")
                    quickButton(.loginItems, description: "자동 실행 관리")
                    quickButton(.maintenance, description: "관리 도구")
                    quickButton(.privacy, description: "브라우저 정리")
                }

                Spacer(minLength: 8)
            }
            .padding(28)
        }
        .onAppear {
            vm.refresh()
            vm.refreshLaunchAtLogin()
        }
        .confirmationDialog(
            "휴지통을 완전히 비울까요? 이 작업은 되돌릴 수 없습니다.",
            isPresented: $confirmEmptyTrash
        ) {
            Button("휴지통 비우기", role: .destructive) { vm.emptyTrash() }
            Button("취소", role: .cancel) {}
        }
        .alert(
            "알림",
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

    // MARK: - 컴포넌트

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(TossColor.grey700)
            .padding(.leading, 4)
            .padding(.top, 4)
    }

    private var systemOverview: some View {
        HStack(spacing: 0) {
            overviewMetric(
                title: "저장 공간",
                ratio: vm.status.diskUsageRatio,
                value: formatBytes(vm.status.diskFree),
                caption: "사용 가능"
            )
            overviewDivider
            overviewMetric(
                title: "메모리",
                ratio: vm.status.memUsageRatio,
                value: formatBytes(max(vm.status.memTotal - vm.status.memUsed, 0)),
                caption: "사용 가능"
            )
            overviewDivider
            VStack(alignment: .leading, spacing: 7) {
                Text("휴지통")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(TossColor.grey400)
                Text(vm.status.trashSize == 0 ? "정상" : formatBytes(vm.status.trashSize))
                    .font(.system(size: 19, weight: .heavy, design: .monospaced))
                    .foregroundStyle(vm.status.trashSize == 0 ? TossColor.mint : TossColor.orange)
                Text(vm.status.trashSize == 0 ? "정리할 항목 없음" : "정리 가능")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TossColor.grey500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TossColor.line)
        )
    }

    private func overviewMetric(title: String, ratio: Double, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(TossColor.grey400)
                Spacer()
                Text("\(Int(min(max(ratio, 0), 1) * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(TossColor.blue)
            }
            Text(value)
                .font(.system(size: 19, weight: .heavy, design: .monospaced))
                .foregroundStyle(TossColor.grey900)
            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(TossColor.grey200)
                        Rectangle()
                            .fill(TossColor.blue)
                            .frame(width: geometry.size.width * min(max(ratio, 0), 1))
                    }
                }
                .frame(height: 4)
                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TossColor.grey500)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var overviewDivider: some View {
        Rectangle()
            .fill(TossColor.line)
            .frame(width: 1, height: 72)
    }

    private func actionCard<Trailing: View>(
        icon: String, tint: Color, tintBG: Color,
        title: String,
        badge: String? = nil, badgeTint: Color = TossColor.orange, badgeBG: Color = TossColor.orangeLight,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tintBG)
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(tint)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TossColor.grey900)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(badgeBG)
                            .foregroundStyle(badgeTint)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                Text(description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TossColor.grey400)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(TossColor.line)
            .frame(height: 1)
            .padding(.leading, 86)
    }

    private func quickButton(_ section: AppSection, description: String) -> some View {
        Button {
            selection = section
        } label: {
            VStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.title3)
                    .foregroundStyle(TossColor.blue)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TossColor.grey900)
                    .lineLimit(1)
                Text(description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TossColor.grey400)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(TossTileButtonStyle())
    }
}
