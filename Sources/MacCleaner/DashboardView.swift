import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: DashboardViewModel
    @Binding var selection: AppSection
    var onQuickOptimize: () -> Void = {}
    @State private var confirmEmptyTrash = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TossColor.canvas

                StorageTerrainView(
                    diskRatio: vm.status.diskUsageRatio,
                    memoryRatio: vm.status.memUsageRatio
                )
                .padding(.horizontal, 26)
                .padding(.vertical, 54)

                VStack(spacing: 0) {
                    header

                    Spacer(minLength: 12)

                    HStack(alignment: .center, spacing: 28) {
                        VStack(alignment: .leading, spacing: 28) {
                            spatialMetric(
                                title: "메모리 여유",
                                value: formatBytes(max(vm.status.memTotal - vm.status.memUsed, 0)),
                                caption: "전체 \(formatBytes(vm.status.memTotal))",
                                tint: TossColor.mint
                            )
                            spatialMetric(
                                title: "휴지통",
                                value: vm.status.trashSize == 0 ? "정상" : formatBytes(vm.status.trashSize),
                                caption: vm.status.trashSize == 0 ? "정리할 항목 없음" : "비우기 가능",
                                tint: vm.status.trashSize == 0 ? TossColor.mint : TossColor.orange
                            )
                        }
                        .frame(width: 190, alignment: .leading)

                        Spacer(minLength: 12)

                        primaryReadout

                        Spacer(minLength: 12)

                        VStack(alignment: .leading, spacing: 28) {
                            spatialMetric(
                                title: "전체 저장 공간",
                                value: formatBytes(vm.status.diskTotal),
                                caption: "내장 디스크",
                                tint: TossColor.blue
                            )
                            spatialMetric(
                                title: "사용 중",
                                value: formatBytes(max(vm.status.diskTotal - vm.status.diskFree, 0)),
                                caption: "\(Int(vm.status.diskUsageRatio * 100))% 사용",
                                tint: TossColor.blue
                            )
                        }
                        .frame(width: 190, alignment: .leading)
                    }
                    .padding(.horizontal, 44)

                    Spacer(minLength: 18)

                    recommendationStrip
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("저장 공간 지도")
                    .font(.system(size: 25, weight: .heavy))
                    .foregroundStyle(TossColor.grey900)
                Text("현재 시스템 수치가 데이터 지형에 실시간으로 반영됩니다")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(TossColor.mint)
                    .frame(width: 7, height: 7)
                Text("실시간 진단")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TossColor.grey500)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
    }

    private var primaryReadout: some View {
        VStack(spacing: 9) {
            Text("사용 가능한 저장 공간")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TossColor.grey500)

            Text(formatBytes(vm.status.diskFree))
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .foregroundStyle(TossColor.grey900)
                .monospacedDigit()

            HStack(spacing: 8) {
                Rectangle()
                    .fill(TossColor.blue)
                    .frame(width: 38, height: 2)
                Text("\(Int(vm.status.diskUsageRatio * 100))% 사용 중")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TossColor.grey500)
            }

            Button {
                onQuickOptimize()
            } label: {
                Label("전체 스캔", systemImage: "viewfinder")
            }
            .buttonStyle(TossProminentButtonStyle())
            .padding(.top, 6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(TossColor.canvas.opacity(0.92))
    }

    private func spatialMetric(title: String, value: String, caption: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Rectangle()
                .fill(tint)
                .frame(width: 2, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(TossColor.grey400)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(TossColor.grey900)
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(TossColor.grey500)
            }
        }
    }

    private var recommendationStrip: some View {
        HStack(spacing: 0) {
            recommendation(
                icon: "memorychip",
                title: "메모리 확보",
                subtitle: "비활성 캐시 해제",
                tint: TossColor.blue
            ) {
                vm.freeMemory()
            }

            stripDivider

            recommendation(
                icon: "trash",
                title: vm.status.trashSize > 0 ? "휴지통 비우기" : "휴지통 정상",
                subtitle: vm.status.trashSize > 0 ? formatBytes(vm.status.trashSize) : "정리할 항목 없음",
                tint: vm.status.trashSize > 0 ? TossColor.orange : TossColor.mint,
                disabled: vm.status.trashSize == 0
            ) {
                confirmEmptyTrash = true
            }

            stripDivider

            HStack(spacing: 11) {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TossColor.mint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("로그인 시 자동 시작")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TossColor.grey700)
                    Text("메뉴바 모니터 실행")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(TossColor.grey400)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.launchAtLogin },
                    set: { vm.setLaunchAtLogin($0) }
                ))
                .toggleStyle(BrandSwitchToggleStyle())
                .labelsHidden()
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 74)
        .background(TossColor.chrome.opacity(0.96))
        .overlay(alignment: .top) {
            Rectangle().fill(TossColor.line).frame(height: 1)
        }
    }

    private func recommendation(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TossColor.grey700)
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(TossColor.grey400)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(TossColor.grey400)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(TossColor.line)
            .frame(width: 1, height: 38)
    }
}

private struct StorageTerrainView: View {
    let diskRatio: Double
    let memoryRatio: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                let phase = timeline.date.timeIntervalSinceReferenceDate * 0.1
                let lineCount = 17
                let horizontalInset = size.width * 0.05
                let usableWidth = max(size.width - horizontalInset * 2, 1)
                let usableHeight = size.height * 0.72
                let top = size.height * 0.14

                for index in 0..<lineCount {
                    let depth = Double(index) / Double(lineCount - 1)
                    let baseY = top + usableHeight * depth
                    let amplitude = 6 + diskRatio * 16 + depth * memoryRatio * 10
                    var path = Path()

                    for step in 0...56 {
                        let progress = Double(step) / 56
                        let x = horizontalInset + usableWidth * progress
                        let centerDistance = abs(progress - 0.5) * 2
                        let envelope = max(0.12, 1 - centerDistance * 0.82)
                        let firstWave = sin(progress * 12 + Double(index) * 0.52 + phase)
                        let secondWave = cos(progress * 21 - Double(index) * 0.31 - phase * 0.7)
                        let y = baseY + (firstWave * 0.68 + secondWave * 0.32) * amplitude * envelope

                        if step == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }

                    let color: Color
                    let width: CGFloat
                    if index == 5 {
                        color = TossColor.blue.opacity(0.55)
                        width = 1.5
                    } else if index == 10 {
                        color = TossColor.mint.opacity(0.48)
                        width = 1.4
                    } else if index == 14 {
                        color = TossColor.orange.opacity(0.38)
                        width = 1.2
                    } else {
                        color = TossColor.grey400.opacity(0.13)
                        width = 1
                    }

                    context.stroke(path, with: .color(color), lineWidth: width)
                }

                for marker in 1..<10 {
                    let x = horizontalInset + usableWidth * Double(marker) / 10
                    var markerPath = Path()
                    markerPath.move(to: CGPoint(x: x, y: top - 12))
                    markerPath.addLine(to: CGPoint(x: x, y: top + usableHeight + 12))
                    context.stroke(
                        markerPath,
                        with: .color(TossColor.grey400.opacity(0.055)),
                        lineWidth: 1
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
