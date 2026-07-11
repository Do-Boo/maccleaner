import SwiftUI
import UIKit

enum MobilePalette {
    static let background = dynamic(light: 0xF4F6F7, dark: 0x111416)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x171B1E)
    static let elevated = dynamic(light: 0xE9EDF0, dark: 0x20262A)
    static let text = dynamic(light: 0x171A1C, dark: 0xF3F5F6)
    static let secondary = dynamic(light: 0x667078, dark: 0x9CA6AD)
    static let muted = dynamic(light: 0x8A949B, dark: 0x6F7A82)
    static let line = dynamic(light: 0xDDE2E5, dark: 0x2A3035)
    static let blue = dynamic(light: 0x4F7FD7, dark: 0x6D9BE8)
    static let teal = dynamic(light: 0x2FAE9B, dark: 0x47C3AE)
    static let amber = dynamic(light: 0xC98B48, dark: 0xDDA261)
    static let red = dynamic(light: 0xD85D6A, dark: 0xE87984)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum MobileFormat {
    static func bytes(_ value: Int64) -> String {
        if value == 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct MobileScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(MobilePalette.text)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MobilePalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MobilePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(MobilePalette.blue.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
