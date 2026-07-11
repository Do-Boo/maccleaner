import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: DashboardViewModel
    @Binding var selection: AppSection?
    var onQuickOptimize: () -> Void = {}
    @State private var confirmEmptyTrash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 헤더
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("내 맥을 쉽고 가볍게")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(TossColor.grey900)
                        Text("안전하게 디바이스 자원을 정리하고 기기 수명을 늘려보세요.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TossColor.grey500)
                    }
                    Spacer()
                    Button {
                        onQuickOptimize()
                    } label: {
                        Label("원클릭 퀵 최적화", systemImage: "bolt.fill")
                    }
                    .buttonStyle(TossProminentButtonStyle())
                }

                // 자원 점유 카드
                HStack(spacing: 16) {
                    statCard(
                        title: "MACINTOSH HD",
                        ratio: vm.status.diskUsageRatio,
                        freeLabel: "여유 공간",
                        freeValue: formatBytes(vm.status.diskFree),
                        totalText: "/ \(formatBytes(vm.status.diskTotal))"
                    )
                    statCard(
                        title: "UNIFIED MEMORY",
                        ratio: vm.status.memUsageRatio,
                        freeLabel: "사용 가능",
                        freeValue: formatBytes(max(vm.status.memTotal - vm.status.memUsed, 0)),
                        totalText: "/ \(formatBytes(vm.status.memTotal))"
                    )
                }

                // 정리 액션 리스트
                sectionTitle("지금 정리가 필요한 서비스")
                VStack(spacing: 12) {
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
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }

                // 빠른 실행
                sectionTitle("빠른 실행")
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        quickButton(.junk, description: "캐시·로그 정리")
                        quickButton(.largeFiles, description: "큰 파일 찾기")
                        quickButton(.duplicates, description: "같은 파일 정리")
                        quickButton(.apps, description: "앱 완전 삭제")
                    }
                    HStack(spacing: 12) {
                        quickButton(.downloads, description: "묵은 다운로드")
                        quickButton(.loginItems, description: "자동 실행 관리")
                        quickButton(.maintenance, description: "관리 도구")
                        quickButton(.privacy, description: "브라우저 정리")
                    }
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

    private func statCard(
        title: String, ratio: Double,
        freeLabel: String, freeValue: String, totalText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TossColor.grey400)
                    .kerning(0.5)
                Spacer()
                Text("\(Int(min(max(ratio, 0), 1) * 100))%")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(TossColor.blue)
                    .monospacedDigit()
            }
            .padding(.bottom, 18)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(TossColor.grey200)
                    Capsule()
                        .fill(TossColor.blue)
                        .frame(width: max(geo.size.width * min(max(ratio, 0), 1), 10))
                        .animation(.easeOut(duration: 0.8), value: ratio)
                }
            }
            .frame(height: 10)
            .padding(.bottom, 18)

            HStack(spacing: 5) {
                Text(freeLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TossColor.grey700)
                Text(freeValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TossColor.blue)
                Spacer()
                Text(totalText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TossColor.grey400)
                    .monospacedDigit()
            }
        }
        .padding(24)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }

    private func actionCard<Trailing: View>(
        icon: String, tint: Color, tintBG: Color,
        title: String,
        badge: String? = nil, badgeTint: Color = TossColor.orange, badgeBG: Color = TossColor.orangeLight,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                            .clipShape(Capsule())
                    }
                }
                Text(description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TossColor.grey400)
            }
            Spacer()
            trailing()
        }
        .padding(20)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
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
