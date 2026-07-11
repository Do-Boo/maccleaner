import Foundation
import Observation

struct ImportedFile: Identifiable, Hashable {
    let url: URL
    let byteCount: Int64
    let modifiedAt: Date?

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }
}

@MainActor
@Observable
final class ImportedFileStore {
    private(set) var files: [ImportedFile] = []
    private(set) var isImporting = false
    var errorMessage: String?

    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directoryURL = directoryURL ?? documents.appendingPathComponent("Imported", isDirectory: true)
        try? fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        reload()
    }

    var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.byteCount }
    }

    func reload() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        files = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
                return nil
            }
            return ImportedFile(
                url: url,
                byteCount: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            )
        }
        .sorted { $0.byteCount > $1.byteCount }
    }

    func importFiles(from sourceURLs: [URL]) async {
        guard !sourceURLs.isEmpty, !isImporting else { return }
        isImporting = true
        defer {
            isImporting = false
            reload()
        }

        do {
            for sourceURL in sourceURLs {
                let accessing = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessing { sourceURL.stopAccessingSecurityScopedResource() }
                }

                let destination = availableDestination(for: sourceURL.lastPathComponent)
                try fileManager.copyItem(at: sourceURL, to: destination)
            }
        } catch {
            errorMessage = "파일을 가져오지 못했습니다. \(error.localizedDescription)"
        }
    }

    func delete(_ file: ImportedFile) {
        do {
            try fileManager.removeItem(at: file.url)
            reload()
        } catch {
            errorMessage = "\(file.name)을 삭제하지 못했습니다. \(error.localizedDescription)"
        }
    }

    func availableDestination(for filename: String) -> URL {
        let original = directoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let source = URL(fileURLWithPath: filename)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var index = 2

        while true {
            let candidateName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directoryURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
