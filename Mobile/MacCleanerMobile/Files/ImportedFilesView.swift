import SwiftUI
import UniformTypeIdentifiers

struct ImportedFilesView: View {
    let store: ImportedFileStore
    @State private var showImporter = false
    @State private var pendingDeletion: ImportedFile?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    MobileScreenHeader(
                        title: "파일 보관함",
                        subtitle: "가져온 파일만 앱 내부에서 안전하게 관리합니다"
                    )

                    summary

                    if store.files.isEmpty {
                        emptyState
                    } else {
                        fileList
                    }

                    Button {
                        showImporter = true
                    } label: {
                        Label(store.isImporting ? "가져오는 중" : "파일 가져오기", systemImage: "plus")
                    }
                    .buttonStyle(MobilePrimaryButtonStyle())
                    .disabled(store.isImporting)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .background(MobilePalette.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                Task { await store.importFiles(from: urls) }
            case let .failure(error):
                store.errorMessage = "파일 선택을 완료하지 못했습니다. \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "이 파일을 앱 보관함에서 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { file in
            Button("삭제", role: .destructive) {
                store.delete(file)
                pendingDeletion = nil
            }
            Button("취소", role: .cancel) { pendingDeletion = nil }
        } message: { file in
            Text(file.name)
        }
        .alert(
            "파일 보관함",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("확인") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .task { store.reload() }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("보관 중")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MobilePalette.secondary)
                Text("\(store.files.count)개")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(MobilePalette.text)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("사용 공간")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MobilePalette.secondary)
                Text(MobileFormat.bytes(store.totalBytes))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(MobilePalette.text)
            }
        }
        .padding(.vertical, 8)
    }

    private var fileList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(store.files.enumerated()), id: \.element.id) { index, file in
                HStack(spacing: 12) {
                    Image(systemName: icon(for: file))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint(for: file))
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MobilePalette.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(file.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "수정일 없음")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MobilePalette.muted)
                    }

                    Spacer()

                    Text(MobileFormat.bytes(file.byteCount))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MobilePalette.secondary)

                    Menu {
                        ShareLink(item: file.url) {
                            Label("공유", systemImage: "square.and.arrow.up")
                        }
                        Button("삭제", systemImage: "trash", role: .destructive) {
                            pendingDeletion = file
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MobilePalette.secondary)
                            .frame(width: 32, height: 38)
                    }
                }
                .frame(height: 64)

                if index < store.files.count - 1 {
                    Rectangle().fill(MobilePalette.line).frame(height: 1).padding(.leading, 40)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(MobilePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MobilePalette.line)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(MobilePalette.amber)
            Text("가져온 파일이 없습니다")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MobilePalette.text)
            Text("파일 앱에서 문서와 압축 파일 등을 가져올 수 있습니다")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MobilePalette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
    }

    private func icon(for file: ImportedFile) -> String {
        switch file.fileExtension {
        case "jpg", "jpeg", "png", "heic", "gif": "photo"
        case "mov", "mp4", "m4v": "video"
        case "zip", "rar", "7z": "archivebox"
        case "pdf": "doc.richtext"
        default: "doc"
        }
    }

    private func tint(for file: ImportedFile) -> Color {
        switch file.fileExtension {
        case "jpg", "jpeg", "png", "heic", "gif": MobilePalette.teal
        case "mov", "mp4", "m4v": MobilePalette.blue
        case "zip", "rar", "7z": MobilePalette.amber
        case "pdf": MobilePalette.red
        default: MobilePalette.secondary
        }
    }
}
