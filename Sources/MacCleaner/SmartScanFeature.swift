import SwiftUI

// MARK: - 스마트 스캔 (원클릭 전체 정리)

@MainActor
final class SmartScanViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var hasScanned = false
    @Published var stage = ""
    @Published var progress: Double = 0
    @Published var resultMessage: String?

    @Published var junkCategories: [JunkCategory] = []
    @Published var oldDownloads: [CleanableItem] = []
    @Published var browserCaches: [BrowserDataItem] = []

    @Published var includeJunk = true
    @Published var includeDownloads = false // 사용자 파일이라 기본은 꺼둠
    @Published var includeBrowser = true

    var junkSize: Int64 { junkCategories.reduce(0) { $0 + $1.totalSize } }
    var junkCount: Int { junkCategories.reduce(0) { $0 + $1.items.count } }
    var downloadsSize: Int64 { oldDownloads.reduce(0) { $0 + $1.size } }
    var browserSize: Int64 { browserCaches.reduce(0) { $0 + $1.size } }

    var selectedSize: Int64 {
        (includeJunk ? junkSize : 0)
            + (includeDownloads ? downloadsSize : 0)
            + (includeBrowser ? browserSize : 0)
    }

    func scan() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        hasScanned = false
        progress = 0.05
        Task {
            stage = "시스템 정크 확인 중..."
            self.junkCategories = await Task.detached(priority: .userInitiated) {
                JunkScanner.scan()
            }.value
            self.progress = 0.45

            stage = "오래된 다운로드 확인 중..."
            self.oldDownloads = await Task.detached(priority: .userInitiated) {
                DownloadsScanner.scan(olderThanMonths: 6)
            }.value
            self.progress = 0.75

            stage = "브라우저 캐시 확인 중..."
            let browserData = await Task.detached(priority: .userInitiated) {
                PrivacyScanner.scan()
            }.value
            self.browserCaches = browserData.filter { $0.kind == "캐시" }
            self.progress = 1.0

            try? await Task.sleep(nanoseconds: 500_000_000)
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func reset() {
        guard !isScanning, !isCleaning else { return }
        hasScanned = false
        progress = 0
    }

    func clean() {
        var urls: [URL] = []
        if includeJunk { urls += junkCategories.flatMap { $0.items.map(\.url) } }
        if includeDownloads { urls += oldDownloads.map(\.url) }

        var skippedBrowsers: Set<String> = []
        if includeBrowser {
            let running = PrivacyScanner.runningBrowserIDs()
            for item in browserCaches {
                if running.contains(item.bundleID) {
                    skippedBrowsers.insert(item.browser)
                } else {
                    urls += item.urls
                }
            }
        }
        guard !urls.isEmpty else {
            if !skippedBrowsers.isEmpty {
                resultMessage = "\(skippedBrowsers.sorted().joined(separator: ", "))은(는) 실행 중이라 브라우저 캐시를 정리하지 못했습니다. 브라우저를 완전히 종료한 뒤 다시 시도하세요."
            } else {
                resultMessage = "정리할 항목이 선택되지 않았습니다."
            }
            return
        }

        isCleaning = true
        stage = "휴지통으로 안전하게 이동하는 중..."
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Cleaner.trash(urls) }.value
            var message = "\(outcome.succeeded)개 항목을 휴지통으로 이동했습니다 (\(formatBytes(outcome.freed)) 확보)."
            if !skippedBrowsers.isEmpty {
                message += "\n\(skippedBrowsers.joined(separator: ", "))은(는) 실행 중이라 건너뛰었습니다."
            }
            if !outcome.errors.isEmpty {
                message += "\n실패 \(outcome.errors.count)건"
            }
            CleanupRecorder.record(action: "스마트 스캔", outcome: outcome)
            self.resultMessage = message
            self.isCleaning = false
            self.scan() // 정리 후 다시 스캔
        }
    }
}

struct SmartScanView: View {
    @ObservedObject var vm: SmartScanViewModel
    @State private var confirmClean = false

    var body: some View {
        Group {
            if vm.isScanning || vm.isCleaning {
                loadingState
            } else if !vm.hasScanned {
                readyState
            } else {
                finishedState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "선택한 항목(\(formatBytes(vm.selectedSize)))을 휴지통으로 이동할까요?",
            isPresented: $confirmClean
        ) {
            Button("안전 정리", role: .destructive) { vm.clean() }
            Button("취소", role: .cancel) {}
        }
        .alert(
            "스마트 스캔",
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

    // MARK: - 스캔 전 대기 상태

    private var readyState: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TossColor.blueLight)
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(TossColor.blue)
                )
                .padding(.bottom, 30)

            Text("정리 가능한 항목을 찾습니다")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(TossColor.grey900)
            Text("캐시, 오래된 다운로드, 브라우저 캐시를 한 번에 확인합니다.\n선택한 항목만 휴지통으로 이동합니다.")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(TossColor.grey500)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 12)

            Button {
                vm.scan()
            } label: {
                Text("스캔 시작")
                    .padding(.horizontal, 16)
            }
            .buttonStyle(TossProminentButtonStyle())
            .padding(.top, 36)
        }
    }

    // MARK: - 스캔 진행 중 (원형 링 게이지)

    private var loadingState: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(TossColor.grey200, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: vm.progress)
                    .stroke(TossColor.blue, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: vm.progress)
                Text("\(Int(vm.progress * 100))%")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(TossColor.blue)
                    .monospacedDigit()
            }
            .frame(width: 124, height: 124)
            .padding(.bottom, 36)

            Text(vm.stage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TossColor.grey900)
            Text("삭제 전 결과를 확인하고 포함 여부를 선택할 수 있습니다")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TossColor.grey400)
                .padding(.top, 8)
        }
    }

    // MARK: - 스캔 완료 결과

    private var finishedState: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(TossColor.mintLight)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(TossColor.mint)
                )
                .padding(.bottom, 18)

            Text("정리 가능한 항목을 찾았습니다")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(TossColor.grey900)
            Text("선택한 항목만 휴지통으로 이동합니다.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TossColor.grey500)
                .padding(.top, 8)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    resultCards
                }
                VStack(spacing: 12) {
                    resultCards
                }
            }
            .frame(maxWidth: 860)
            .padding(.top, 28)

            // 하단 액션
            HStack(spacing: 14) {
                Button("처음으로") { vm.reset() }
                    .buttonStyle(TossPillButtonStyle(
                        foreground: TossColor.grey700, background: TossColor.grey100
                    ))
                Button {
                    confirmClean = true
                } label: {
                    Text("정리하고 \(formatBytes(vm.selectedSize)) 확보")
                        .padding(.horizontal, 12)
                }
                .buttonStyle(TossProminentButtonStyle())
                .disabled(vm.selectedSize == 0)
            }
            .padding(.top, 36)
        }
        .padding(24)
    }

    @ViewBuilder
    private var resultCards: some View {
        resultCard(
            include: $vm.includeJunk,
            name: "캐시 및 로그",
            size: vm.junkSize,
            description: "사용자 캐시, 로그, 메일 첨부 등 \(vm.junkCount)개 항목"
        )
        resultCard(
            include: $vm.includeDownloads,
            name: "오래된 다운로드",
            size: vm.downloadsSize,
            description: "6개월 이상 수정되지 않은 다운로드 항목 \(vm.oldDownloads.count)개. 기본값은 제외입니다"
        )
        resultCard(
            include: $vm.includeBrowser,
            name: "브라우저 캐시",
            size: vm.browserSize,
            description: "방문 기록과 쿠키는 제외합니다. 실행 중인 브라우저는 건너뜁니다"
        )
    }

    private func resultCard(
        include: Binding<Bool>, name: String, size: Int64, description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TossColor.grey400)
                Spacer()
                Text(formatBytes(size))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(size > 0 ? TossColor.blue : TossColor.grey400)
                    .monospacedDigit()
            }
            Text(description)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TossColor.grey700)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Spacer(minLength: 14)
            HStack {
                Text("정리에 포함")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TossColor.grey500)
                Spacer()
                Toggle("", isOn: include)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}
