import SwiftUI

enum MobileSection: String, CaseIterable, Identifiable {
    case status = "기기"
    case photos = "사진"
    case files = "파일"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status: "waveform.path.ecg"
        case .photos: "photo.on.rectangle.angled"
        case .files: "folder"
        }
    }

    init?(launchValue: String) {
        switch launchValue {
        case "status": self = .status
        case "photos": self = .photos
        case "files": self = .files
        default: return nil
        }
    }
}
