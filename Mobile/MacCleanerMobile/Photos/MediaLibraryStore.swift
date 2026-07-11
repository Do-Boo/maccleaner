import Foundation
import Observation
import Photos

enum MediaCandidateKind: String, Sendable {
    case screenshot
    case longVideo
    case similar
}

struct MediaCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let kind: MediaCandidateKind
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let creationDate: Date?
}

struct MediaScanResult: Sendable {
    var screenshotCandidates: [MediaCandidate] = []
    var longVideoCandidates: [MediaCandidate] = []
    var similarGroups: [[MediaCandidate]] = []

    static let empty = MediaScanResult()
}

@MainActor
@Observable
final class MediaLibraryStore {
    private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var result = MediaScanResult.empty
    private(set) var isScanning = false
    private(set) var isDeleting = false
    var errorMessage: String?

    var canReadLibrary: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func requestAccessAndScan() async {
        authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard canReadLibrary else { return }
        await scan()
    }

    func scan() async {
        guard canReadLibrary, !isScanning else { return }
        isScanning = true
        result = await Task.detached(priority: .userInitiated) {
            MediaScanner.scan()
        }.value
        isScanning = false
    }

    func delete(localIdentifiers: [String]) async {
        guard !localIdentifiers.isEmpty, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            await scan()
        } catch {
            errorMessage = "선택한 항목을 삭제하지 못했습니다. \(error.localizedDescription)"
        }
    }
}

enum MediaScanner {
    static func scan() -> MediaScanResult {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 10_000

        let fetchResult = PHAsset.fetchAssets(with: options)
        var screenshots: [MediaCandidate] = []
        var longVideos: [MediaCandidate] = []
        var similarityBuckets: [String: [MediaCandidate]] = [:]

        fetchResult.enumerateObjects { asset, _, _ in
            if asset.mediaType == .image, asset.mediaSubtypes.contains(.photoScreenshot) {
                screenshots.append(candidate(from: asset, kind: .screenshot))
            }

            if asset.mediaType == .video, asset.duration >= 60 {
                longVideos.append(candidate(from: asset, kind: .longVideo))
            }

            guard let creationDate = asset.creationDate else { return }
            let key = similarityKey(
                mediaTypeRawValue: asset.mediaType.rawValue,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                duration: asset.duration,
                creationDate: creationDate
            )
            similarityBuckets[key, default: []].append(candidate(from: asset, kind: .similar))
        }

        let similarGroups = similarityBuckets.values
            .filter { $0.count > 1 }
            .sorted { lhs, rhs in
                (lhs.first?.creationDate ?? .distantPast) > (rhs.first?.creationDate ?? .distantPast)
            }
            .prefix(100)

        return MediaScanResult(
            screenshotCandidates: screenshots,
            longVideoCandidates: longVideos.sorted { $0.duration > $1.duration },
            similarGroups: Array(similarGroups)
        )
    }

    private static func candidate(from asset: PHAsset, kind: MediaCandidateKind) -> MediaCandidate {
        MediaCandidate(
            id: asset.localIdentifier,
            kind: kind,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            creationDate: asset.creationDate
        )
    }

    static func similarityKey(
        mediaTypeRawValue: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: TimeInterval,
        creationDate: Date
    ) -> String {
        let timeBucket = Int(creationDate.timeIntervalSince1970 / 120)
        let durationBucket = mediaTypeRawValue == PHAssetMediaType.video.rawValue
            ? Int(duration.rounded())
            : 0
        return "\(mediaTypeRawValue)-\(pixelWidth)x\(pixelHeight)-\(durationBucket)-\(timeBucket)"
    }
}
