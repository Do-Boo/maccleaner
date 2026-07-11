import SwiftUI
import Security

// MARK: - 셰레더 (덮어쓰기 삭제)

enum Shredder {
    /// 파일 내용을 무작위 데이터로 덮어쓴 뒤 삭제해 복구 가능성을 낮춤.
    static func shred(_ urls: [URL]) -> (succeeded: Int, freed: Int64, errors: [String]) {
        var succeeded = 0
        var freed: Int64 = 0
        let targets = FileProtection.deletionTargets(from: urls)
        var errors = targets.rejections.map { "\($0.url.lastPathComponent): \($0.message)" }

        for url in targets.urls {
            let size = FileSizer.itemSize(url)
            do {
                try shredItem(url)
                succeeded += 1
                freed += size
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (succeeded, freed, errors)
    }

    private static func shredItem(_ url: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }

        if isDir.boolValue {
            var overwriteErrors: [String] = []
            if let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey],
                options: [], errorHandler: { _, _ in true }
            ) {
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if values?.isRegularFile == true {
                        do {
                            try overwrite(fileURL)
                        } catch {
                            overwriteErrors.append("\(relativePath(fileURL, under: url)): \(error.localizedDescription)")
                        }
                    }
                }
            }
            if !overwriteErrors.isEmpty {
                throw ShredderError.overwriteFailures(overwriteErrors)
            }
        } else {
            try overwrite(url)
        }
        try FileManager.default.removeItem(at: url)
    }

    private static func overwrite(_ url: URL) throws {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0 else { return }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0)

        let chunkSize = 1_000_000
        var remaining = size
        while remaining > 0 {
            let n = min(chunkSize, remaining)
            var chunk = Data(count: n)
            let status = chunk.withUnsafeMutableBytes { buffer -> OSStatus in
                guard let base = buffer.baseAddress else { return errSecParam }
                return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
            }
            guard status == errSecSuccess else {
                throw ShredderError.randomBytesFailed(status)
            }
            try handle.write(contentsOf: chunk)
            remaining -= n
        }
        try handle.synchronize()
    }

    private static func relativePath(_ fileURL: URL, under root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return fileURL.path.hasPrefix(rootPath)
            ? String(fileURL.path.dropFirst(rootPath.count))
            : fileURL.lastPathComponent
    }
}

private enum ShredderError: LocalizedError {
    case overwriteFailures([String])
    case randomBytesFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .overwriteFailures(let errors):
            return "일부 파일 덮어쓰기 실패: \(errors.prefix(3).joined(separator: ", "))"
        case .randomBytesFailed(let status):
            return "무작위 데이터 생성 실패 (\(status))"
        }
    }
}

@MainActor
final class ShredderViewModel: ObservableObject {
    @Published var items: [CleanableItem] = []
    @Published var isWorking = false
    @Published var resultMessage: String?

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "추가"
        panel.message = "덮어쓴 뒤 삭제할 파일이나 폴더를 선택하세요"
        guard panel.runModal() == .OK else { return }

        let existingPaths = Set(items.map(\.url.path))
        for url in panel.urls where !existingPaths.contains(url.path) {
            items.append(CleanableItem(
                url: url,
                name: url.lastPathComponent,
                detail: url.deletingLastPathComponent().path,
                size: FileSizer.itemSize(url)
            ))
        }
    }

    func remove(_ item: CleanableItem) {
        items.removeAll { $0.id == item.id }
    }

    func shred() {
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }
        isWorking = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { Shredder.shred(urls) }.value
            var message = "\(outcome.succeeded)개 항목을 덮어쓴 뒤 삭제했습니다 (\(formatBytes(outcome.freed)))."
            if !outcome.errors.isEmpty {
                message += "\n실패: \(outcome.errors.prefix(3).joined(separator: ", "))"
            }
            CleanupHistoryStore.shared.add(
                action: "셰레더",
                itemCount: outcome.succeeded,
                freedBytes: outcome.freed,
                errors: outcome.errors
            )
            self.resultMessage = message
            self.items.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
            self.isWorking = false
        }
    }
}

struct ShredderView: View {
    @ObservedObject var vm: ShredderViewModel
    @State private var confirmShred = false

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "셰레더",
                subtitle: "파일을 무작위 데이터로 덮어쓴 뒤 삭제합니다. SSD/APFS에서는 복구 불가를 보장하지 않습니다"
            ) {
                HStack {
                    Button {
                        vm.addFiles()
                    } label: {
                        Label("파일 추가", systemImage: "plus")
                    }
                    .disabled(vm.isWorking)
                    Button(role: .destructive) {
                        confirmShred = true
                    } label: {
                        Label("보안 삭제 (\(formatBytes(vm.totalSize)))", systemImage: "flame")
                    }
                    .disabled(vm.isWorking || vm.items.isEmpty)
                }
            }

            if vm.isWorking {
                Spacer()
                ProgressView("덮어쓰는 중... 파일이 크면 오래 걸립니다")
                Spacer()
            } else if vm.items.isEmpty {
                emptyState(icon: "flame", message: "'파일 추가'로 덮어쓴 뒤 삭제할 항목을 골라주세요")
            } else {
                ScrollView {
                    TossList(items: vm.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(formatBytes(item.size))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button {
                                vm.remove(item)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.plain)
                            .help("목록에서 제거")
                            .accessibilityLabel("\(item.name) 목록에서 제거")
                        }
                        .padding(.vertical, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    Text("휴지통을 거치지 않고 즉시 삭제됩니다. SSD/APFS에서는 복구 불가를 보장하지 않으니 민감 파일에만 신중하게 사용하세요.")
                        .font(.caption)
                        .foregroundStyle(TossColor.red)
                    Spacer()
                }
            }
        }
        .confirmationDialog(
            "\(vm.items.count)개 항목(\(formatBytes(vm.totalSize)))을 덮어쓴 뒤 삭제할까요? 휴지통에서 복원할 수 없습니다.",
            isPresented: $confirmShred
        ) {
            Button("보안 삭제", role: .destructive) { vm.shred() }
            Button("취소", role: .cancel) {}
        }
        .alert(
            "셰레더",
            isPresented: Binding(
                get: { vm.resultMessage != nil },
                set: { if !$0 { vm.resultMessage = nil } }
            )
        ) {
            Button("확인") { vm.resultMessage = nil }
        } message: {
            Text(vm.resultMessage ?? "")
        }
    }
}
