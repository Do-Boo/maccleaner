import SwiftUI

struct MobileRootView: View {
    let deviceStore: DeviceStatusStore
    let mediaStore: MediaLibraryStore
    let importStore: ImportedFileStore
    @State private var selection: MobileSection

    init(
        deviceStore: DeviceStatusStore,
        mediaStore: MediaLibraryStore,
        importStore: ImportedFileStore
    ) {
        self.deviceStore = deviceStore
        self.mediaStore = mediaStore
        self.importStore = importStore

        let arguments = ProcessInfo.processInfo.arguments
        let launchSection: MobileSection
        if let index = arguments.firstIndex(of: "--ui-section"),
           arguments.indices.contains(index + 1),
           let section = MobileSection(launchValue: arguments[index + 1]) {
            launchSection = section
        } else {
            launchSection = .status
        }
        _selection = State(initialValue: launchSection)
    }

    var body: some View {
        ZStack {
            MobilePalette.background.ignoresSafeArea()

            Group {
                switch selection {
                case .status:
                    DeviceStatusView(store: deviceStore, selection: $selection)
                case .photos:
                    PhotosHomeView(store: mediaStore)
                case .files:
                    ImportedFilesView(store: importStore)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MobileCommandDeck(selection: $selection)
        }
        .tint(MobilePalette.blue)
    }
}

private struct MobileCommandDeck: View {
    @Binding var selection: MobileSection

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MobileSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = section
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(section.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selection == section ? MobilePalette.blue : MobilePalette.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
                .accessibilityValue(selection == section ? "선택됨" : "")
                .accessibilityIdentifier("mobile-tab-\(section.id)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .background(MobilePalette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(MobilePalette.line).frame(height: 1)
        }
    }
}
