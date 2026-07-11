import Photos
import XCTest
@testable import MacCleanerMobile

final class MobileCoreTests: XCTestCase {
    func testDurationFormatting() {
        XCTAssertEqual(MobileFormat.duration(65), "1:05")
        XCTAssertEqual(MobileFormat.duration(-5), "0:00")
        XCTAssertEqual(MobileFormat.bytes(0), "0 KB")
    }

    func testPhotoSimilarityKeyUsesTwoMinuteBuckets() {
        let date = Date(timeIntervalSince1970: 1_000)
        let first = MediaScanner.similarityKey(
            mediaTypeRawValue: PHAssetMediaType.image.rawValue,
            pixelWidth: 4032,
            pixelHeight: 3024,
            duration: 0,
            creationDate: date
        )
        let second = MediaScanner.similarityKey(
            mediaTypeRawValue: PHAssetMediaType.image.rawValue,
            pixelWidth: 4032,
            pixelHeight: 3024,
            duration: 0,
            creationDate: date.addingTimeInterval(30)
        )

        XCTAssertEqual(first, second)
    }

    @MainActor
    func testImportedFileNameCollisionAddsSuffix() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existing = root.appendingPathComponent("Report.pdf")
        try Data("test".utf8).write(to: existing)
        let store = ImportedFileStore(directoryURL: root)

        XCTAssertEqual(store.availableDestination(for: "Report.pdf").lastPathComponent, "Report 2.pdf")
    }

    @MainActor
    func testImportAndDeleteRoundTrip() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDirectory = temporary.appendingPathComponent("Source", isDirectory: true)
        let importDirectory = temporary.appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let source = sourceDirectory.appendingPathComponent("sample.txt")
        try Data("mobile-cleaner".utf8).write(to: source)

        let store = ImportedFileStore(directoryURL: importDirectory)
        await store.importFiles(from: [source])

        XCTAssertEqual(store.files.count, 1)
        XCTAssertEqual(store.files.first?.name, "sample.txt")
        XCTAssertEqual(store.totalBytes, Int64(Data("mobile-cleaner".utf8).count))

        let imported = try XCTUnwrap(store.files.first)
        store.delete(imported)
        XCTAssertTrue(store.files.isEmpty)
    }
}
