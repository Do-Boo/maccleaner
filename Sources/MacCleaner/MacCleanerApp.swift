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
        WindowGroup("MacCleaner", id: "main") {
            ContentView()
        }
        .windowStyle(.automatic)

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
