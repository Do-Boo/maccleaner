import SwiftUI

@main
struct MacCleanerApp: App {
    init() {
        // `swift run`으로 실행해도 Dock 아이콘과 창이 뜨도록 설정
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        // 빈 문자열은 앱 이름으로 대체되므로 공백으로 네이티브 창 제목을 숨깁니다.
        WindowGroup(" ", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 840)
        .commands {
            CommandMenu("탐색") {
                Button("기능 검색") {
                    NotificationCenter.default.post(name: .focusBrandSearch, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        // 실시간 플로팅 모니터 창 (사이드바 '실시간 플로팅 창' 버튼으로 열기)
        Window("Mac 실시간 상태", id: "monitor") {
            MonitorPanelView(model: MonitorModel.shared)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        // 메뉴바 실시간 모니터 — 창을 닫아도 메뉴바에 계속 표시됨
        MenuBarExtra {
            MenuBarView(model: MonitorModel.shared)
        } label: {
            MenuBarLabel(model: MonitorModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
