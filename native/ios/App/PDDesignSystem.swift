import SwiftUI

/// The approved Calm Editorial palette, with the intelligence blue reserved for
/// local analytics and report actions. Every colour adapts to system appearance.
enum PDColors {
    static let page = adaptive(0xF7F5EF, dark: 0x101D1C)
    static let surface = adaptive(0xFFFFFF, dark: 0x1C302D)
    static let ink = adaptive(0x20332F, dark: 0xF3F7F3)
    static let teal = adaptive(0x124C47, dark: 0x9AD9C9)
    static let actionFill = Color(red: 0x12 / 255.0, green: 0x4C / 255.0, blue: 0x47 / 255.0)
    static let onAction = Color.white
    static let jade = adaptive(0x26786D, dark: 0x8BD2C2)
    static let sage = adaptive(0xDCECE4, dark: 0x294840)
    static let navy = adaptive(0x142E48, dark: 0xD5E8FF)
    static let blue = adaptive(0x245BC0, dark: 0x8EB6FF)
    static let blueFill = adaptive(0x245BC0, dark: 0x315FAF)
    static let chartSurface = adaptive(0xFFFFFF, dark: 0x1A2D3A)
    static let line = Color(uiColor: .separator)
    static let danger = adaptive(0x92342B, dark: 0xFF8576)

    private static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

enum PDLayout {
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 20
    static let cardRadius: CGFloat = 18
    static let primaryTarget: CGFloat = 64
}

/// Original scalable double-arch mark. The geometry is shared with the
/// checked-in SVG and generated raster app icons.
struct PDBridgeArch: Shape {
    let secondary: Bool

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        if secondary {
            path.move(to: point(0.43, 0.70))
            path.addCurve(to: point(0.90, 0.70), control1: point(0.55, 0.37), control2: point(0.77, 0.37))
            path.addLine(to: point(0.75, 0.70))
            path.addCurve(to: point(0.57, 0.70), control1: point(0.68, 0.54), control2: point(0.61, 0.54))
        } else {
            path.move(to: point(0.10, 0.70))
            path.addCurve(to: point(0.73, 0.70), control1: point(0.23, 0.27), control2: point(0.55, 0.27))
            path.addLine(to: point(0.57, 0.70))
            path.addCurve(to: point(0.26, 0.70), control1: point(0.49, 0.49), control2: point(0.35, 0.49))
        }
        path.closeSubpath()
        return path
    }
}

struct PDBridgeMark: View {
    var tiled = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if tiled {
                    RoundedRectangle(cornerRadius: geometry.size.width * 0.22, style: .continuous)
                        .fill(PDColors.actionFill)
                }
                PDBridgeArch(secondary: false)
                    .fill(tiled ? Color.white : PDColors.teal)
                PDBridgeArch(secondary: true)
                    .fill(tiled ? Color(red: 0.62, green: 0.86, blue: 0.77) : PDColors.jade)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct PDWelcomeLandscape: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.30))
                    path.addCurve(to: CGPoint(x: width, y: height * 0.44),
                                  control1: CGPoint(x: width * 0.35, y: height * 0.31),
                                  control2: CGPoint(x: width * 0.53, y: height * 0.68))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                }.fill(PDColors.sage)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.68))
                    path.addCurve(to: CGPoint(x: width, y: height * 0.37),
                                  control1: CGPoint(x: width * 0.42, y: height * 0.98),
                                  control2: CGPoint(x: width * 0.68, y: height * 0.12))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                }.fill(PDColors.jade.opacity(0.36))
            }
        }
        .accessibilityHidden(true)
    }
}

struct PDSymptomCard: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(PDColors.teal)
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(6)
            .background(PDColors.sage)
            .clipShape(RoundedRectangle(cornerRadius: PDLayout.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: PDLayout.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
