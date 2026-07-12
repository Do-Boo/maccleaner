import SwiftUI

// MARK: - 시작 프로그램 (LaunchAgents)

struct LoginItem: Identifiable {
    let id = UUID()
    let label: String
    let plist: URL
    let program: String
    let isUserScope: Bool // true면 사용자 영역이라 켜고 끌 수 있음
    var enabled: Bool
}

enum LoginItemsScanner {
    static func scan() -> [LoginItem] {
        let uid = getuid()
        let disabledOutput = Shell.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"]).output
        let home = FileManager.default.homeDirectoryForCurrentUser

        let dirs: [(URL, Bool)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), true),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), false),
        ]

        var items: [LoginItem] = []
        for (dir, userScope) in dirs {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for url in children where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(
                          from: data, format: nil
                      ) as? [String: Any] else { continue }

                let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = (plist["Program"] as? String)
                    ?? (plist["ProgramArguments"] as? [String])?.first
                    ?? url.path
                let disabled = disabledOutput.contains("\"\(label)\" => disabled")
                    || disabledOutput.contains("\"\(label)\" => true")
                items.append(LoginItem(
                    label: label, plist: url, program: program,
                    isUserScope: userScope, enabled: !disabled
                ))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    static func setEnabled(_ item: LoginItem, enabled: Bool) {
        let uid = getuid()
        let target = "gui/\(uid)/\(item.label)"
        if enabled {
            Shell.run("/bin/launchctl", ["enable", target])
            Shell.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", item.plist.path])
        } else {
            Shell.run("/bin/launchctl", ["disable", target])
            Shell.run("/bin/launchctl", ["bootout", target])
        }
    }
}

@MainActor
final class LoginItemsViewModel: ObservableObject {
    @Published var items: [LoginItem] = []
    @Published var isScanning = false
    @Published var hasScanned = false

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { LoginItemsScanner.scan() }.value
            self.items = result
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func toggle(_ item: LoginItem, enabled: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].enabled = enabled
        Task.detached(priority: .userInitiated) {
            LoginItemsScanner.setEnabled(item, enabled: enabled)
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct LoginItemsView: View {
    @ObservedObject var vm: LoginItemsViewModel

    private var userItems: [LoginItem] { vm.items.filter(\.isUserScope) }
    private var globalItems: [LoginItem] { vm.items.filter { !$0.isUserScope } }

    var body: some View {
        VStack(spacing: 0) {
            PageToolbar(
                subtitle: "로그인할 때 자동 실행되는 백그라운드 항목(LaunchAgents)을 관리합니다"
            ) {
                HStack {
                    Button {
                        vm.openSystemSettings()
                    } label: {
                        Label("시스템 설정의 로그인 항목", systemImage: "gearshape")
                    }
                    Button {
                        vm.scan()
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                    .disabled(vm.isScanning)
                }
            }

            if vm.isScanning {
                Spacer()
                ProgressView("시작 프로그램을 확인하는 중...")
                Spacer()
            } else if !vm.hasScanned {
                emptyState(icon: "power", message: "새로고침을 눌러 시작 프로그램을 확인하세요")
                    .onAppear { vm.scan() }
            } else if vm.items.isEmpty {
                emptyState(icon: "checkmark.circle", message: "등록된 LaunchAgent가 없습니다")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if !userItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                TossSectionTitle(text: "내 계정 (끄고 켤 수 있음)")
                                TossList(items: userItems) { item in
                                    row(item, editable: true)
                                }
                            }
                        }
                        if !globalItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                TossSectionTitle(text: "전체 시스템 (읽기 전용 · 관리자 영역)")
                                TossList(items: globalItems) { item in
                                    row(item, editable: false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    Text("끄면 다음 로그인부터 자동 실행되지 않습니다. 앱 자체가 삭제되는 것은 아닙니다.")
                        .font(.caption)
                        .foregroundStyle(TossColor.grey500)
                    Spacer()
                }
            }
        }
    }

    private func row(_ item: LoginItem, editable: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                Text(item.program)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if editable {
                Toggle("", isOn: Binding(
                    get: { item.enabled },
                    set: { vm.toggle(item, enabled: $0) }
                ))
                .toggleStyle(BrandSwitchToggleStyle())
                .labelsHidden()
            } else {
                Text(item.enabled ? "켜짐" : "꺼짐")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
