import SwiftUI

struct LargeFilesView: View {
    @ObservedObject var vm: LargeFilesViewModel
    @State private var confirmTrash = false
    @State private var fileDetail: ScannedFileDetail?
    @State private var sort = ScanItemSort.size

    private var sortedFiles: [CleanableItem] {
        sort.sorted(vm.files)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageToolbar(
                subtitle: "홈 폴더에서 큰 파일을 찾아 공간을 확보합니다"
            ) {
                HStack {
                    BrandMenuPicker(
                        title: "기준",
                        selection: $vm.minSizeMB,
                        options: [
                            (100, "100MB 이상"),
                            (500, "500MB 이상"),
                            (1000, "1GB 이상"),
                            (5000, "5GB 이상"),
                        ]
                    )
                    .frame(width: 150)
                    BrandMenuPicker(
                        title: "정렬",
                        selection: $sort,
                        options: ScanItemSort.allCases.map { ($0, $0.rawValue) }
                    )
                    .frame(width: 100)

                    Button {
                        vm.scan()
                    } label: {
                        Label("스캔", systemImage: "magnifyingglass")
                    }
                    .disabled(vm.isScanning)

                    Button(role: .destructive) {
                        confirmTrash = true
                    } label: {
                        Label("삭제 (\(formatBytes(vm.selectedSize)))", systemImage: "trash")
                    }
                    .disabled(vm.isScanning || vm.selectedItems.isEmpty)
                }
            }

            if vm.isScanning {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(vm.scanProgress.phase.isEmpty ? "홈 폴더를 스캔하는 중..." : vm.scanProgress.phase)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(TossColor.grey700)
                    Text("검사 \(vm.scanProgress.scanned)개 · 발견 \(vm.scanProgress.found)개")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(TossColor.grey500)
                        .monospacedDigit()
                    if vm.scanProgress.skippedCloud + vm.scanProgress.skippedUnavailable > 0 {
                        Text("온라인 전용 \(vm.scanProgress.skippedCloud)개 · 접근 불가 \(vm.scanProgress.skippedUnavailable)개 제외")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(TossColor.grey400)
                    }
                    if !vm.scanProgress.currentPath.isEmpty {
                        Text(vm.scanProgress.currentPath)
                            .font(.caption)
                            .foregroundStyle(TossColor.grey400)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 520)
                    }
                    Button("스캔 취소") { vm.cancelScan() }
                        .buttonStyle(TossPillButtonStyle(
                            foreground: TossColor.grey700,
                            background: TossColor.grey100
                        ))
                }
                Spacer()
            } else if !vm.hasScanned {
                emptyState(
                    icon: "externaldrive.badge.questionmark",
                    message: "기준 크기를 정하고 스캔 버튼을 눌러보세요"
                )
            } else if vm.files.isEmpty {
                emptyState(icon: "checkmark.circle", message: "기준보다 큰 파일이 없습니다")
            } else {
                ScrollView(showsIndicators: false) {
                    TossList(items: sortedFiles) { file in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { vm.selected.contains(file.id) },
                                set: { on in
                                    if on { vm.selected.insert(file.id) } else { vm.selected.remove(file.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                    Text(file.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            Spacer()
                            Text(formatBytes(file.size))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button {
                                fileDetail = ScannedFileDetail(item: file)
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.plain)
                            .help("파일 상세 정보")
                            .accessibilityLabel("\(file.name) 상세 정보")
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            } label: {
                                Image(systemName: "magnifyingglass.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Finder에서 보기")
                            .accessibilityLabel("\(file.name) Finder에서 보기")
                            Button {
                                vm.exclude(file)
                            } label: {
                                Image(systemName: "nosign")
                            }
                            .buttonStyle(.plain)
                            .help("다시 추천하지 않기")
                            .accessibilityLabel("\(file.name) 제외 목록에 추가")
                        }
                        .padding(.vertical, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    Text("\(vm.files.count)개 파일 발견")
                        .foregroundStyle(TossColor.grey700)
                    Spacer()
                    Text("선택됨: \(vm.selectedItems.count)개 · \(formatBytes(vm.selectedSize))")
                        .foregroundStyle(TossColor.grey500)
                }
            }
        }
        .confirmationDialog(
            "선택한 \(vm.selectedItems.count)개 파일(\(formatBytes(vm.selectedSize)))을 휴지통으로 이동할까요?",
            isPresented: $confirmTrash
        ) {
            Button("휴지통으로 이동", role: .destructive) { vm.trashSelected() }
            Button("취소", role: .cancel) {}
        }
        .sheet(item: $fileDetail) { detail in
            FileDetailView(detail: detail)
        }
        .alert(
            "대용량 파일",
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
