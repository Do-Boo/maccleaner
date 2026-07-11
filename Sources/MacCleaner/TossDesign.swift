import SwiftUI

private extension NSColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }
}

// MARK: - 토스 디자인 시스템 (TDS 스타일)

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: match == .darkAqua ? dark : light)
        })
    }
}

enum TossColor {
    // 브랜드
    static let blue = Color(light: 0x3182F6, dark: 0x5A9CFF)
    static let blueLight = Color(light: 0xE8F3FF, dark: 0x17375E)
    static let red = Color(light: 0xF04452, dark: 0xFF6673)
    static let redLight = Color(light: 0xFEECEE, dark: 0x4A242A)
    static let green = Color(light: 0x00C471, dark: 0x29D98A)
    static let orange = Color(light: 0xFF8400, dark: 0xFFA33A)
    static let orangeLight = Color(light: 0xFFF2E6, dark: 0x49301D)
    static let mint = Color(light: 0x00C7AE, dark: 0x28D7C2)
    static let mintLight = Color(light: 0xE6FAF7, dark: 0x173D38)

    // 그레이 스케일
    static let grey900 = Color(light: 0x191F28, dark: 0xF2F4F6) // 제목
    static let grey700 = Color(light: 0x333D4B, dark: 0xD1D6DB) // 본문
    static let grey500 = Color(light: 0x6B7684, dark: 0xA6ADB4) // 보조 텍스트
    static let grey400 = Color(light: 0x8B95A1, dark: 0x8B95A1)
    static let grey200 = Color(light: 0xE5E8EB, dark: 0x3C434B) // 구분선
    static let grey100 = Color(light: 0xF2F4F6, dark: 0x262C33)
    static let grey50 = Color(light: 0xF9FAFB, dark: 0x1E2329)

    static let chrome = Color(light: 0xFFFFFF, dark: 0x171A1F)
    static let sidebar = Color(light: 0x171A1F, dark: 0x0F1115)
    static let canvas = Color(light: 0xF6F8FA, dark: 0x20242A)
    static let inspector = Color(light: 0xFBFCFD, dark: 0x191D22)
    static let line = Color(light: 0xE3E7EB, dark: 0x333940)

    static let bg = canvas
    static let card = Color(light: 0xFFFFFF, dark: 0x161A1F)
}

/// 기본 버튼: 연한 파랑 배경 + 파랑 텍스트 알약, destructive면 빨강 계열
struct TossButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(destructive ? TossColor.redLight : TossColor.blueLight)
            .foregroundStyle(destructive ? TossColor.red : TossColor.blue)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 강조 버튼: 토스 블루 채움 + 흰색 텍스트
struct TossProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(TossColor.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 색을 지정할 수 있는 알약 버튼 (주황·민트 등 포인트 컬러용)
struct TossPillButtonStyle: ButtonStyle {
    var foreground: Color = TossColor.blue
    var background: Color = TossColor.blueLight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 위험 동작 확정용: 빨강 채움 버튼
struct TossDangerProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(TossColor.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// 취소 등 중립 동작용: 회색 채움 버튼
struct TossNeutralProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(TossColor.grey100)
            .foregroundStyle(TossColor.grey700)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 대시보드 빠른 실행 타일
struct TossTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(TossColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TossColor.line)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 토스식 원형 체크박스 (켜짐: 파랑 원 + 흰 체크, 꺼짐: 회색 원)
struct TossCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(configuration.isOn ? TossColor.blue : TossColor.grey200)
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 흰색 라운드 카드 안에 행을 쌓는 토스 스타일 리스트
struct TossList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                if index < items.count - 1 {
                    Divider()
                        .overlay(TossColor.grey100)
                        .padding(.leading, 16)
                }
            }
        }
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TossColor.line)
        )
    }
}

/// 카드 위에 붙는 작은 섹션 제목
struct TossSectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TossColor.grey500)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TossColor.grey400)
            }
        }
        .padding(.horizontal, 6)
    }
}

/// 하단 고정 액션 바
struct TossBottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            content
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(TossColor.card)
        .overlay(alignment: .top) {
            Divider().overlay(TossColor.grey200)
        }
    }
}

/// 카드: 흰색 배경 + 큰 라운드 + 은은한 그림자
struct TossGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
            configuration.content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TossColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TossColor.line)
        )
    }
}
