import SwiftUI

// MARK: - 업데이터 (Homebrew 기반)

struct OutdatedPackage: Identifiable {
    let id = UUID()
    let name: String
    let installed: String
    let latest: String
    let isCask: Bool
}

enum BrewUpdater {
    static func brewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// 업데이트 가능한 패키지 목록. 실패 시 오류 메시지 반환.
    static func outdated() -> (packages: [OutdatedPackage], error: String?) {
        guard let brew = brewPath() else {
            return ([], "Homebrew가 설치되어 있지 않습니다.\nbrew.sh 에서 설치하면 이 기능으로 앱·도구 업데이트를 관리할 수 있습니다.")
        }

        Shell.run(brew, ["update", "--quiet"])
        let result = Shell.run(brew, ["outdated", "--json=v2"])
        guard result.status == 0,
              let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], "업데이트 확인 실패: \(result.output.prefix(200))")
        }

        var packages: [OutdatedPackage] = []
        for (key, isCask) in [("formulae", false), ("casks", true)] {
            guard let entries = json[key] as? [[String: Any]] else { continue }
            for entry in entries {
                guard let name = entry["name"] as? String else { continue }
                let installed = (entry["installed_versions"] as? [String])?.last
                    ?? entry["installed_versions"] as? String
                    ?? "?"
                let latest = entry["current_version"] as? String ?? "?"
                packages.append(OutdatedPackage(
                    name: name, installed: installed, latest: latest, isCask: isCask
                ))
            }
        }
        return (packages, nil)
    }

    static func upgrade(_ package: OutdatedPackage) -> Shell.Result {
        guard let brew = brewPath() else { return Shell.Result(status: -1, output: "brew 없음") }
        var args = ["upgrade"]
        if package.isCask { args.append("--cask") }
        args.append(package.name)
        return Shell.run(brew, args)
    }
}

@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published var packages: [OutdatedPackage] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var upgradingID: UUID?
    @Published var errorMessage: String?
    @Published var resultMessage: String?

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { BrewUpdater.outdated() }.value
            self.packages = result.packages
            self.errorMessage = result.error
            self.isScanning = false
            self.hasScanned = true
        }
    }

    func upgrade(_ package: OutdatedPackage) {
        guard upgradingID == nil else { return }
        upgradingID = package.id
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                BrewUpdater.upgrade(package)
            }.value
            if result.status == 0 {
                self.resultMessage = "'\(package.name)' 업그레이드 완료!"
                self.packages.removeAll { $0.id == package.id }
            } else {
                self.resultMessage = "'\(package.name)' 업그레이드 실패:\n\(result.output.suffix(300))"
            }
            self.upgradingID = nil
        }
    }
}

struct UpdaterView: View {
    @ObservedObject var vm: UpdaterViewModel

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "업데이터",
                subtitle: "Homebrew로 설치한 앱과 도구의 업데이트를 확인합니다"
            ) {
                Button {
                    vm.scan()
                } label: {
                    Label("업데이트 확인", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(vm.isScanning || vm.upgradingID != nil)
            }

            if vm.isScanning {
                Spacer()
                ProgressView("업데이트를 확인하는 중... (brew update 포함, 다소 걸립니다)")
                Spacer()
            } else if !vm.hasScanned {
                emptyState(icon: "arrow.triangle.2.circlepath", message: "'업데이트 확인'을 눌러보세요")
            } else if let error = vm.errorMessage {
                emptyState(icon: "exclamationmark.triangle", message: error)
            } else if vm.packages.isEmpty {
                emptyState(icon: "checkmark.circle", message: "모든 패키지가 최신 버전입니다")
            } else {
                ScrollView(showsIndicators: false) {
                    TossList(items: vm.packages) { package in
                        HStack {
                        Image(systemName: package.isCask ? "app.badge" : "terminal")
                            .foregroundStyle(TossColor.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(package.name)
                            Text("\(package.installed) → \(package.latest)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if vm.upgradingID == package.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("업그레이드") { vm.upgrade(package) }
                                .disabled(vm.upgradingID != nil)
                        }
                    }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    Text("App Store 앱은 App Store의 업데이트 탭에서, macOS 자체 업데이트는 시스템 설정에서 확인하세요.")
                        .font(.caption)
                        .foregroundStyle(TossColor.grey500)
                    Spacer()
                }
            }
        }
        .alert(
            "업데이터",
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
