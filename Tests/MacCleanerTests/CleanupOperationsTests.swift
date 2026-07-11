import Foundation
import XCTest
@testable import MacCleaner

final class CleanupOperationsTests: XCTestCase {
    func testProtectedSystemPathIsRejected() {
        let result = FileProtection.deletionTargets(from: [URL(fileURLWithPath: "/System")])

        XCTAssertTrue(result.urls.isEmpty)
        XCTAssertEqual(result.rejections.count, 1)
        XCTAssertTrue(result.rejections[0].message.contains("시스템 보호"))
    }

    func testParentTargetCollapsesChildTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerTests-\(UUID().uuidString)")
        let child = root.appendingPathComponent("child.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("test".utf8).write(to: child)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = FileProtection.deletionTargets(from: [child, root])

        XCTAssertEqual(result.urls.map(\.standardizedFileURL.path), [root.standardizedFileURL.path])
        XCTAssertTrue(result.rejections.isEmpty)
    }

    func testExclusionMatchesDescendantsOnly() {
        let excluded = URL(fileURLWithPath: "/tmp/example")
        let paths = [ExclusionRules.normalizedPath(excluded)]

        XCTAssertTrue(ExclusionRules.isExcluded(excluded.appendingPathComponent("child"), in: paths))
        XCTAssertFalse(ExclusionRules.isExcluded(URL(fileURLWithPath: "/tmp/example-other"), in: paths))
    }

    func testTrashAndRestoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerRestore-\(UUID().uuidString)")
        let file = root.appendingPathComponent("restore.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("restore me".utf8).write(to: file)
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: root)
        }

        let trashed = Cleaner.trash([file])
        XCTAssertEqual(trashed.succeeded, 1, trashed.errors.joined(separator: "\n"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(trashed.moved.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.moved[0].trashedURL.path))

        let restored = Cleaner.restore(trashed.moved)
        XCTAssertEqual(restored.restored.count, 1)
        XCTAssertTrue(restored.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanupOutcomeMatchesOnlyMovedOriginalURL() {
        let original = URL(fileURLWithPath: "/tmp/original")
        let move = TrashMove(
            originalURL: original,
            trashedURL: URL(fileURLWithPath: "/tmp/trashed"),
            size: 10
        )
        let outcome = CleanupOutcome(moved: [move], failures: [])

        XCTAssertTrue(outcome.didMove(original))
        XCTAssertFalse(outcome.didMove(URL(fileURLWithPath: "/tmp/other")))
        XCTAssertEqual(outcome.freed, 10)
    }

    func testRestoreDoesNotOverwriteExistingOriginal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanerConflict-\(UUID().uuidString)")
        let original = root.appendingPathComponent("same.txt")
        let trashed = root.appendingPathComponent("trashed.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: original)
        try Data("trashed".utf8).write(to: trashed)
        defer { try? FileManager.default.removeItem(at: root) }

        let move = TrashMove(originalURL: original, trashedURL: trashed, size: 7)
        let result = Cleaner.restore([move])

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "existing")
    }

    func testScanItemSorting() {
        let old = CleanableItem(
            url: URL(fileURLWithPath: "/tmp/z"),
            name: "Zeta",
            detail: "",
            size: 10,
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let recent = CleanableItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            name: "Alpha",
            detail: "",
            size: 20,
            modifiedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(ScanItemSort.size.sorted([old, recent]).map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(ScanItemSort.modified.sorted([old, recent]).map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(ScanItemSort.name.sorted([old, recent]).map(\.name), ["Alpha", "Zeta"])
    }
}
