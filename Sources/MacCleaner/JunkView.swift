import SwiftUI

struct JunkView: View {
    @ObservedObject var vm: JunkViewModel
    @State private var confirmClean = false

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(
                title: "시스템 정리",
                subtitle: "캐시, 로그 등 불필요한 파일을 찾아 정리합니다"
            ) {
                HStack {
                    Button {
                        vm.scan()
                    } label: {
                        Label("스캔", systemImage: "magnifyingglass")
                    }
                    .disabled(vm.isScanning)

                    Button(role: .destructive) {
                        confirmClean = true
                    } label: {
                        Label("정리 (\(formatBytes(vm.selectedSize)))", systemImage: "sparkles")
                    }
                    .disabled(vm.isScanning || vm.selectedItems.isEmpty)
                }
            }

            if vm.isScanning {
                Spacer()
                ProgressView("스캔 중... 잠시만 기다려 주세요")
                Spacer()
            } else if !vm.hasScanned {
                emptyState(
                    icon: "sparkles",
                    message: "스캔 버튼을 눌러 정리 가능한 파일을 찾아보세요"
                )
            } else if vm.categories.isEmpty {
                emptyState(icon: "checkmark.circle", message: "정리할 파일이 없습니다. 깨끗해요!")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(vm.categories) { category in
                            VStack(alignment: .leading, spacing: 8) {
                                TossSectionTitle(
                                    text: category.name,
                                    trailing: formatBytes(category.totalSize)
                                )
                                TossList(items: category.items) { item in
                                    itemRow(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                TossBottomBar {
                    Button("전체 선택") {
                        vm.selected = Set(vm.categories.flatMap { $0.items.map(\.id) })
                    }
                    Button("전체 해제") { vm.selected = [] }
                    Spacer()
                    Text("선택됨: \(vm.selectedItems.count)개 · \(formatBytes(vm.selectedSize))")
                        .foregroundStyle(TossColor.grey500)
                }
            }
        }
        .confirmationDialog(
            "선택한 \(vm.selectedItems.count)개 항목(\(formatBytes(vm.selectedSize)))을 휴지통으로 이동할까요?",
            isPresented: $confirmClean
        ) {
            Button("휴지통으로 이동", role: .destructive) { vm.clean() }
            Button("취소", role: .cancel) {}
        }
        .alert(
            "정리 완료",
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

    private func itemRow(_ item: CleanableItem) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { vm.selected.contains(item.id) },
                set: { on in
                    if on { vm.selected.insert(item.id) } else { vm.selected.remove(item.id) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Text(formatBytes(item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

func emptyState(icon: String, message: String) -> some View {
    VStack(spacing: 12) {
        Spacer()
        Image(systemName: icon)
            .font(.system(size: 48))
            .foregroundStyle(.secondary)
        Text(message).foregroundStyle(.secondary)
        Spacer()
    }
    .frame(maxWidth: .infinity)
}
