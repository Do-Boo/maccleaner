import SwiftUI

// MARK: - 개인정보 정리 (브라우저 데이터)

struct BrowserDataItem: Identifiable {
    let id = UUID()
    let browser: String
    let bundleID: String
    let kind: String // 캐시 / 방문 기록 / 쿠키
    let urls: [URL]
    let size: Int64
}

enum PrivacyScanner {
    private struct BrowserSpec {
        let name: String
        let bundleID: String
        let cache: [String]
        let history: [String]
        let cookies: [String]
    }

    private struct ChromiumBrowserSpec {
        let name: String
        let bundleID: String
        let supportRoot: String
        let cacheRoot: String
    }

    private static let browsers: [BrowserSpec] = [
        BrowserSpec(
            name: "Safari", bundleID: "com.apple.Safari",
            cache: ["Library/Caches/com.apple.Safari"],
            history: ["Library/Safari/History.db", "Library/Safari/History.db-wal", "Library/Safari/History.db-shm"],
            cookies: ["Library/Cookies/Cookies.binarycookies"]
        ),
    ]

    private static let chromiumBrowsers: [ChromiumBrowserSpec] = [
        ChromiumBrowserSpec(
            name: "Chrome", bundleID: "com.google.Chrome",
            supportRoot: "Library/Application Support/Google/Chrome",
            cacheRoot: "Library/Caches/Google/Chrome"
        ),
        ChromiumBrowserSpec(
            name: "Edge", bundleID: "com.microsoft.edgemac",
            supportRoot: "Library/Application Support/Microsoft Edge",
            cacheRoot: "Library/Caches/Microsoft Edge"
        ),
        ChromiumBrowserSpec(
            name: "Brave", bundleID: "com.brave.Browser",
            supportRoot: "Library/Application Support/BraveSoftware/Brave-Browser",
            cacheRoot: "Library/Caches/BraveSoftware/Brave-Browser"
        ),
        ChromiumBrowserSpec(
            name: "웨일", bundleID: "com.naver.whale",
            supportRoot: "Library/Application Support/Naver/Whale",
            cacheRoot: "Library/Caches/Naver/Whale"
        ),
    ]

    static func scan() -> [BrowserDataItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var items: [BrowserDataItem] = []

        func addItem(browser: String, bundleID: String, kind: String, paths: [URL]) {
            let existing = paths.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { return }
            let size = existing.reduce(Int64(0)) { $0 + FileSizer.itemSize($1) }
            items.append(BrowserDataItem(
                browser: browser, bundleID: bundleID, kind: kind, urls: existing, size: size
            ))
        }

        for spec in browsers {
            addItem(browser: spec.name, bundleID: spec.bundleID, kind: "캐시",
                    paths: spec.cache.map(home.appendingPathComponent))
            addItem(browser: spec.name, bundleID: spec.bundleID, kind: "방문 기록",
                    paths: spec.history.map(home.appendingPathComponent))
            addItem(browser: spec.name, bundleID: spec.bundleID, kind: "쿠키",
                    paths: spec.cookies.map(home.appendingPathComponent))
        }

        for spec in chromiumBrowsers {
            let supportRoot = home.appendingPathComponent(spec.supportRoot)
            let profiles = chromiumProfiles(in: supportRoot)
            let history = profiles.flatMap {
                [
                    $0.appendingPathComponent("History"),
                    $0.appendingPathComponent("History-journal"),
                ]
            }
            let cookies = profiles.flatMap {
                [
                    $0.appendingPathComponent("Cookies"),
                    $0.appendingPathComponent("Network/Cookies"),
                ]
            }

            addItem(browser: spec.name, bundleID: spec.bundleID, kind: "캐시",
                    paths: [home.appendingPathComponent(spec.cacheRoot)])
            addItem(browser: spec.name, bundleID: spec.bundleID, kind: "방문 기록", paths: history)
            addItem(browser: spec.name, bundleID: spec.bundleID, kind: "쿠키", paths: cookies)
        }

        // Firefox는 프로파일 폴더 구조가 달라서 별도 처리
        let firefoxProfiles = home.appendingPathComponent("Library/Application Support/Firefox/Profiles")
        if let profiles = try? FileManager.default.contentsOfDirectory(
            at: firefoxProfiles, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            let history = profiles.map { $0.appendingPathComponent("places.sqlite") }
            let cookies = profiles.map { $0.appendingPathComponent("cookies.sqlite") }
            addItem(browser: "Firefox", bundleID: "org.mozilla.firefox", kind: "캐시",
                    paths: [home.appendingPathComponent("Library/Caches/Firefox")])
            addItem(browser: "Firefox", bundleID: "org.mozilla.firefox", kind: "방문 기록", paths: history)
            addItem(browser: "Firefox", bundleID: "org.mozilla.firefox", kind: "쿠키", paths: cookies)
        }

        return items
    }

    private static func chromiumProfiles(in root: URL) -> [URL] {
        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [root.appendingPathComponent("Default")] }

        let profileDirs = profiles.filter { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return false
            }
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ") || name == "Guest Profile"
        }

        return profileDirs.isEmpty ? [root.appendingPathComponent("Default")] : profileDirs
    }

    /// 실행 중인 브라우저의 bundleID 집합
    static func runningBrowserIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

@MainActor
final class PrivacyViewModel: ObservableObject {
    @Published var items: [BrowserDataItem] = []
    @Published var selected: Set<UUID> = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var resultMessage: String?

    var selectedItems: [BrowserDataItem] { items.filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { PrivacyScanner.scan() }.value
            self.items = result
            self.selected = []
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func clean() {
        let targets = selectedItems
        guard !targets.isEmpty else { return }

        // 실행 중인 브라우저는 데이터 파일이 잠겨 있어 건너뜀
        let running = PrivacyScanner.runningBrowserIDs()
        let blocked = targets.filter { running.contains($0.bundleID) }
        let cleanable = targets.filter { !running.contains($0.bundleID) }

        isScanning = true
        Task {
            let urls = cleanable.flatMap(\.urls)
            let outcome = await Task.detached(priority: .userInitiated) { Cleaner.trash(urls) }.value

            var message = ""
            if outcome.succeeded > 0 {
                message += "\(outcome.succeeded)개 항목을 정리했습니다 (\(formatBytes(outcome.freed)) 확보)."
            }
            if !blocked.isEmpty {
                let names = Set(blocked.map(\.browser)).joined(separator: ", ")
                message += "\n\(names)은(는) 실행 중이라 건너뛰었습니다. 브라우저를 종료한 뒤 다시 시도하세요."
            }
            if !outcome.errors.isEmpty {
                message += "\n실패 \(outcome.errors.count)건 (Safari 데이터는 '전체 디스크 접근 권한'이 필요할 수 있습니다)"
            }
            CleanupRecorder.record(action: "개인정보 정리", outcome: outcome)
            self.resultMessage = message.isEmpty ? "정리할 항목이 없습니다." : message
            self.isScanning = false
            self.scan()
        }
    }
}

struct PrivacyView: View {
    @ObservedObject var vm: PrivacyViewModel
    @State private var confirmClean = false

    private var groupedByBrowser: [(String, [BrowserDataItem])] {
        Dictionary(grouping: vm.items, by: \.browser)
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageToolbar(
                subtitle: "브라우저의 캐시, 방문 기록, 쿠키를 정리합니다"
            ) {
                HStack {
                    Button {
                        vm.scan()
                    } label: {
                        Label("스캔", systemImage: "magnifyingglass")
                    }
                    .disabled(vm.isScanning)
                    Button(role: .destructive) {
                        confirmClean = true
                    } label: {
                        Label("정리 (\(formatBytes(vm.selectedSize)))", systemImage: "hand.raised")
                    }
                    .disabled(vm.isScanning || vm.selectedItems.isEmpty)
                }
            }

            if vm.isScanning {
                Spacer()
                ProgressView("브라우저 데이터를 확인하는 중...")
                Spacer()
            } else if !vm.hasScanned {
                emptyState(icon: "hand.raised", message: "스캔을 눌러 브라우저 데이터를 확인하세요")
            } else if vm.items.isEmpty {
                emptyState(icon: "checkmark.circle", message: "정리할 브라우저 데이터가 없습니다")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedByBrowser, id: \.0) { browser, items in
                            VStack(alignment: .leading, spacing: 8) {
                                TossSectionTitle(text: browser)
                                TossList(items: items) { item in
                                    HStack {
                                        Toggle(isOn: Binding(
                                            get: { vm.selected.contains(item.id) },
                                            set: { on in
                                                if on { vm.selected.insert(item.id) } else { vm.selected.remove(item.id) }
                                            }
                                        )) {
                                            Text(item.kind)
                                        }
                                        Spacer()
                                        Text(formatBytes(item.size))
                                            .monospacedDigit()
                                            .foregroundStyle(TossColor.grey500)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TossColor.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("정리 전 해당 브라우저를 완전히 종료하세요. 실행 중인 브라우저는 자동으로 건너뜁니다.")
                            Text("방문 기록·쿠키를 지우면 자동 로그인이 풀립니다. Safari는 '전체 디스크 접근 권한'이 필요할 수 있습니다.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(TossColor.grey500)
                    Spacer()
                }
            }
        }
        .confirmationDialog(
            "선택한 브라우저 데이터(\(formatBytes(vm.selectedSize)))를 정리할까요? 쿠키를 지우면 사이트 자동 로그인이 풀립니다.",
            isPresented: $confirmClean
        ) {
            Button("정리", role: .destructive) { vm.clean() }
            Button("취소", role: .cancel) {}
        }
        .alert(
            "개인정보 정리",
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
}
