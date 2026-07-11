import Photos
import SwiftUI
import UIKit

private enum PhotoRoute: String, Hashable, Identifiable {
    case screenshots
    case longVideos
    case similar

    var id: String { rawValue }
}

struct PhotosHomeView: View {
    let store: MediaLibraryStore

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    MobileScreenHeader(
                        title: "사진 정리",
                        subtitle: "직접 확인할 수 있는 후보만 분류합니다"
                    )

                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(MobilePalette.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PhotoRoute.self) { route in
                switch route {
                case .screenshots:
                    MediaCandidateGrid(
                        title: "스크린샷",
                        subtitle: "스크린샷으로 인식된 사진",
                        candidates: store.result.screenshotCandidates,
                        store: store
                    )
                case .longVideos:
                    MediaCandidateGrid(
                        title: "긴 동영상",
                        subtitle: "재생 시간이 60초 이상인 동영상",
                        candidates: store.result.longVideoCandidates,
                        store: store
                    )
                case .similar:
                    SimilarCandidateGroups(store: store)
                }
            }
        }
        .alert(
            "사진 정리",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("확인") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.canReadLibrary {
            authorizedContent
        } else {
            permissionContent
        }
    }

    private var authorizedContent: some View {
        VStack(spacing: 0) {
            if store.isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("사진 보관함을 확인하는 중")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MobilePalette.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                candidateLink(
                    route: .screenshots,
                    icon: "rectangle.on.rectangle",
                    title: "스크린샷",
                    detail: "\(store.result.screenshotCandidates.count)개",
                    tint: MobilePalette.blue
                )
                rowDivider
                candidateLink(
                    route: .longVideos,
                    icon: "video",
                    title: "긴 동영상",
                    detail: "\(store.result.longVideoCandidates.count)개",
                    tint: MobilePalette.amber
                )
                rowDivider
                candidateLink(
                    route: .similar,
                    icon: "square.on.square",
                    title: "유사 촬영 후보",
                    detail: "\(store.result.similarGroups.count)그룹",
                    tint: MobilePalette.teal
                )

                Button {
                    Task { await store.scan() }
                } label: {
                    Label("다시 분석", systemImage: "arrow.clockwise")
                }
                .buttonStyle(MobilePrimaryButtonStyle())
                .padding(.top, 22)
                .task {
                    if store.result.screenshotCandidates.isEmpty,
                       store.result.longVideoCandidates.isEmpty,
                       store.result.similarGroups.isEmpty {
                        await store.scan()
                    }
                }
            }
        }
    }

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(MobilePalette.blue)

            Text("사진 접근이 필요합니다")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(MobilePalette.text)

            Text("스크린샷과 긴 동영상, 유사 촬영 후보를 기기 안에서 분류합니다. 선택하지 않은 항목은 변경하지 않습니다.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MobilePalette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if store.authorizationStatus == .denied || store.authorizationStatus == .restricted {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                } else {
                    Task { await store.requestAccessAndScan() }
                }
            } label: {
                Text(store.authorizationStatus == .denied ? "설정 열기" : "사진 접근 허용")
            }
            .buttonStyle(MobilePrimaryButtonStyle())
        }
        .padding(.top, 34)
    }

    private func candidateLink(
        route: PhotoRoute,
        icon: String,
        title: String,
        detail: String,
        tint: Color
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MobilePalette.text)
                Spacer()
                Text(detail)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MobilePalette.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MobilePalette.muted)
            }
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle().fill(MobilePalette.line).frame(height: 1).padding(.leading, 39)
    }
}

private struct SimilarCandidateGroups: View {
    let store: MediaLibraryStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                MobileScreenHeader(
                    title: "유사 촬영 후보",
                    subtitle: "같은 해상도와 가까운 촬영 시간으로 묶은 참고 후보입니다"
                )

                if store.result.similarGroups.isEmpty {
                    EmptyMediaState(text: "유사한 촬영 후보가 없습니다")
                } else {
                    ForEach(Array(store.result.similarGroups.enumerated()), id: \.offset) { index, group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("그룹 \(index + 1) · \(group.count)개")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(MobilePalette.secondary)
                            MediaCandidateGridBody(candidates: group, store: store)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(MobilePalette.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MediaCandidateGrid: View {
    let title: String
    let subtitle: String
    let candidates: [MediaCandidate]
    let store: MediaLibraryStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                MobileScreenHeader(title: title, subtitle: subtitle)
                if candidates.isEmpty {
                    EmptyMediaState(text: "해당하는 항목이 없습니다")
                } else {
                    MediaCandidateGridBody(candidates: candidates, store: store)
                }
            }
            .padding(20)
        }
        .background(MobilePalette.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MediaCandidateGridBody: View {
    let candidates: [MediaCandidate]
    let store: MediaLibraryStore
    @State private var selection = Set<String>()
    @State private var confirmDelete = false

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
    ]

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(candidates) { candidate in
                    Button {
                        if selection.contains(candidate.id) {
                            selection.remove(candidate.id)
                        } else {
                            selection.insert(candidate.id)
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            PhotoThumbnail(localIdentifier: candidate.id)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()

                            if candidate.kind == .longVideo {
                                Text(MobileFormat.duration(candidate.duration))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.65))
                                    .padding(5)
                            }

                            Image(systemName: selection.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(selection.contains(candidate.id) ? MobilePalette.blue : .white)
                                .shadow(color: .black.opacity(0.35), radius: 2)
                                .padding(6)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("정리 후보")
                    .accessibilityValue(selection.contains(candidate.id) ? "선택됨" : "선택 안 됨")
                }
            }

            if !selection.isEmpty {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text(store.isDeleting ? "삭제 중" : "선택한 \(selection.count)개 삭제")
                }
                .buttonStyle(MobilePrimaryButtonStyle())
                .disabled(store.isDeleting)
            }
        }
        .confirmationDialog(
            "선택한 사진과 동영상을 삭제할까요? 삭제된 항목은 사진 앱의 최근 삭제된 항목으로 이동합니다.",
            isPresented: $confirmDelete
        ) {
            Button("삭제", role: .destructive) {
                let identifiers = Array(selection)
                Task {
                    await store.delete(localIdentifiers: identifiers)
                    selection.removeAll()
                }
            }
            Button("취소", role: .cancel) {}
        }
    }
}

private struct PhotoThumbnail: View {
    let localIdentifier: String
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Rectangle()
                    .fill(MobilePalette.elevated)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(MobilePalette.muted)
                    }
            }
        }
        .onAppear(perform: requestImage)
        .onDisappear {
            if let requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }

    private func requestImage() {
        guard image == nil else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 260, height: 260),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result {
                DispatchQueue.main.async { image = result }
            }
        }
    }
}

private struct EmptyMediaState: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(MobilePalette.teal)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MobilePalette.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
