import SwiftUI

@main
struct MacCleanerMobileApp: App {
    @State private var deviceStore = DeviceStatusStore()
    @State private var mediaStore = MediaLibraryStore()
    @State private var importStore = ImportedFileStore()

    var body: some Scene {
        WindowGroup {
            MobileRootView(
                deviceStore: deviceStore,
                mediaStore: mediaStore,
                importStore: importStore
            )
        }
    }
}
