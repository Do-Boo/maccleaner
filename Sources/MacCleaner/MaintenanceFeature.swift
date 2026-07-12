import SwiftUI

// MARK: - 유지보수 도구

struct MaintenanceTask: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let icon: String
    let command: String
    let needsAdmin: Bool
}

enum MaintenanceTasks {
    static let all: [MaintenanceTask] = [
        MaintenanceTask(
            name: "메모리 해제",
            description: "비활성 메모리를 정리해 여유 메모리를 확보합니다",
            icon: "memorychip",
            command: "purge",
            needsAdmin: true
        ),
        MaintenanceTask(
            name: "DNS 캐시 초기화",
            description: "웹사이트 접속 문제가 있을 때 DNS 캐시를 비웁니다",
            icon: "network",
            command: "dscacheutil -flushcache; killall -HUP mDNSResponder",
            needsAdmin: true
        ),
        MaintenanceTask(
            name: "Spotlight 재색인",
            description: "검색이 이상할 때 Spotlight 인덱스를 다시 만듭니다 (시간이 걸립니다)",
            icon: "magnifyingglass",
            command: "mdutil -E /",
            needsAdmin: true
        ),
        MaintenanceTask(
            name: "Launch Services 재구축",
            description: "'다음으로 열기' 목록이 중복되거나 꼬였을 때 초기화합니다",
            icon: "square.grid.3x3",
            command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user",
            needsAdmin: false
        ),
        MaintenanceTask(
            name: "Finder 재실행",
            description: "Finder가 느리거나 멈췄을 때 다시 시작합니다",
            icon: "faceid",
            command: "killall Finder",
            needsAdmin: false
        ),
        MaintenanceTask(
            name: "Dock 재실행",
            description: "Dock 표시가 이상할 때 다시 시작합니다",
            icon: "dock.rectangle",
            command: "killall Dock",
            needsAdmin: false
        ),
    ]
}

@MainActor
final class MaintenanceViewModel: ObservableObject {
    @Published var runningTaskID: UUID?
    @Published var resultMessage: String?

    func run(_ task: MaintenanceTask) {
        guard runningTaskID == nil else { return }
        runningTaskID = task.id
        Task {
            let error: String? = await Task.detached(priority: .userInitiated) {
                if task.needsAdmin {
                    return Shell.runAsAdmin(task.command)
                }
                let result = Shell.runShell(task.command)
                // killall은 대상 프로세스가 없어도 실패로 나오므로 무시
                return (result.status == 0 || task.command.hasPrefix("killall"))
                    ? nil : result.output
            }.value

            if let error, !error.contains("User canceled") {
                self.resultMessage = "'\(task.name)' 실패: \(error)"
            } else if error == nil {
                self.resultMessage = "'\(task.name)' 완료!"
            }
            self.runningTaskID = nil
        }
    }
}

struct MaintenanceView: View {
    @ObservedObject var vm: MaintenanceViewModel

    var body: some View {
        VStack(spacing: 0) {
            PageToolbar(
                subtitle: "맥이 느리거나 이상할 때 쓰는 관리 도구 모음"
            ) {
                EmptyView()
            }

            ScrollView(showsIndicators: false) {
                TossList(items: MaintenanceTasks.all) { task in
                    HStack(spacing: 12) {
                    Image(systemName: task.icon)
                        .font(.title3)
                        .foregroundStyle(TossColor.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(task.name).font(.headline)
                            if task.needsAdmin {
                                Text("관리자 암호 필요")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.orange.opacity(0.2), in: Capsule())
                            }
                        }
                        Text(task.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if vm.runningTaskID == task.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("실행") { vm.run(task) }
                            .disabled(vm.runningTaskID != nil)
                    }
                }
                    .padding(.vertical, 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .alert(
            "유지보수",
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
