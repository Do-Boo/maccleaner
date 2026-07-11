import SwiftUI

struct DeviceStatusView: View {
    let store: DeviceStatusStore
    @Binding var selection: MobileSection

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                MobileScreenHeader(
                    title: "iPhone 상태",
                    subtitle: "저장 공간과 연결 상태를 한눈에 확인합니다"
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)

                storageLandscape
                    .frame(height: 290)

                statusBand

                quickActions
                    .padding(.top, 26)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .background(MobilePalette.background)
        .task { store.refresh() }
    }

    private var storageLandscape: some View {
        ZStack {
            MobileStorageTerrain(ratio: store.usageRatio)
                .padding(.horizontal, 14)
                .padding(.vertical, 22)

            VStack(spacing: 5) {
                Text("사용 가능한 공간")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MobilePalette.secondary)
                Text(MobileFormat.bytes(store.freeBytes))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(MobilePalette.text)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text("전체 \(MobileFormat.bytes(store.totalBytes)) · \(Int(store.usageRatio * 100))% 사용")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MobilePalette.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(MobilePalette.background.opacity(0.9))
        }
    }

    private var statusBand: some View {
        VStack(spacing: 0) {
            statusRow(
                icon: "battery.75percent",
                title: "배터리",
                value: store.batteryText,
                detail: store.batteryStateText,
                tint: MobilePalette.teal
            )
            Divider().overlay(MobilePalette.line).padding(.leading, 52)
            statusRow(
                icon: store.isNetworkAvailable ? "wifi" : "wifi.slash",
                title: "네트워크",
                value: store.networkLabel,
                detail: store.isNetworkAvailable ? "온라인 기능 사용 가능" : "연결을 확인하세요",
                tint: store.isNetworkAvailable ? MobilePalette.blue : MobilePalette.amber
            )
            Divider().overlay(MobilePalette.line).padding(.leading, 52)
            statusRow(
                icon: "internaldrive",
                title: "사용 중",
                value: MobileFormat.bytes(store.usedBytes),
                detail: "앱과 시스템 데이터 포함",
                tint: MobilePalette.blue
            )
        }
        .background(MobilePalette.surface)
        .overlay(alignment: .top) { Rectangle().fill(MobilePalette.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(MobilePalette.line).frame(height: 1) }
    }

    private func statusRow(
        icon: String,
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MobilePalette.secondary)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MobilePalette.muted)
            }
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MobilePalette.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("정리 시작")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MobilePalette.text)

            HStack(spacing: 10) {
                actionButton(
                    title: "사진 정리",
                    subtitle: "스크린샷과 긴 동영상",
                    icon: "photo.on.rectangle.angled",
                    tint: MobilePalette.blue
                ) { selection = .photos }

                actionButton(
                    title: "파일 보관함",
                    subtitle: "가져온 파일 확인",
                    icon: "folder",
                    tint: MobilePalette.amber
                ) { selection = .files }
            }
        }
    }

    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MobilePalette.text)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MobilePalette.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
            .background(MobilePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MobilePalette.line)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MobileStorageTerrain: View {
    let ratio: Double

    var body: some View {
        Canvas { context, size in
            for index in 0..<12 {
                let depth = Double(index) / 11
                let baseY = size.height * (0.1 + depth * 0.8)
                let amplitude = 4 + ratio * 10 + depth * 5
                var path = Path()

                for step in 0...36 {
                    let progress = Double(step) / 36
                    let x = size.width * progress
                    let envelope = max(0.18, 1 - abs(progress - 0.5) * 1.55)
                    let y = baseY
                        + sin(progress * 10 + Double(index) * 0.5) * amplitude * envelope
                        + cos(progress * 18 - Double(index) * 0.22) * amplitude * 0.28
                    if step == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                let color: Color
                if index == 4 {
                    color = MobilePalette.blue.opacity(0.52)
                } else if index == 8 {
                    color = MobilePalette.teal.opacity(0.42)
                } else {
                    color = MobilePalette.muted.opacity(0.16)
                }
                context.stroke(path, with: .color(color), lineWidth: index == 4 ? 1.5 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
