import AppKit
import PervaneCore
import SwiftUI

/// Sıcaklığa göre renk: serinken yeşil, eşiğe yaklaştıkça turuncudan kırmızıya.
func heatColor(_ temp: Double, limit: Double) -> Color {
    let r = min(1, max(0, (temp - 40) / max(1, limit - 40)))
    return Color(hue: 0.38 * (1 - r), saturation: 0.72, brightness: 0.86)
}

let fanTint = Color(hue: 0.55, saturation: 0.68, brightness: 0.92)

/// Türkçe binlik ayraçlı tam sayı: 7.820.
func grouped(_ value: Double) -> String {
    Int(value.rounded()).formatted(.number.locale(Locale(identifier: "tr_TR")))
}

/// Profil kartında ve seçicide görünen simge.
func symbol(for p: Profile) -> String {
    if let icon = p.icon { return icon }
    let name = p.name.lowercased()
    if name.contains("sessiz") || name.contains("quiet") { return "leaf.fill" }
    if name.contains("dengeli") || name.contains("balanced") { return "scalemass.fill" }
    if name.contains("serin") || name.contains("cool") { return "snowflake" }
    if name.contains("tam") || name.contains("max") { return "bolt.fill" }
    switch p.mode {
    case .auto: return "apple.logo"
    case .fixed: return "dial.medium.fill"
    case .curve: return "chart.xyaxis.line"
    case .max: return "bolt.fill"
    }
}

let iconChoices = ["leaf.fill", "scalemass.fill", "snowflake", "bolt.fill", "apple.logo", "dial.medium.fill",
                   "chart.xyaxis.line", "moon.fill", "flame.fill", "gamecontroller.fill", "hammer.fill", "film.fill"]

/// Profilin tek satırlık özeti.
func summary(of p: Profile) -> String {
    switch p.mode {
    case .auto: return "Sistem yönetir"
    case .max: return "Hep tam güç"
    case .fixed: return "Sabit %\(Int(p.fixedPercent))"
    case .curve:
        let pts = p.curve.sorted { $0.temp < $1.temp }
        guard let a = pts.first, let b = pts.last else { return "Eğri" }
        return "\(Int(a.temp))° → \(Int(b.temp))°"
    }
}

/// Alt kısmı açık halka gösterge.
struct RingGauge<Center: View>: View {
    /// 0…1
    let value: Double
    let colors: [Color]
    var size: CGFloat = 112
    @ViewBuilder var center: () -> Center

    private let sweep = 0.75

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: sweep * min(1, max(0.004, value)))
                .stroke(AngularGradient(colors: colors, center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.6), value: value)
            center()
        }
        .frame(width: size, height: size)
    }
}

/// Bölümleri ayıran yuvarlak köşeli zemin.
struct Card: ViewModifier {
    var padding: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 10) -> some View { modifier(Card(padding: padding)) }
}

/// Küçük bilgi hapı: simge + yazı.
struct Chip: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.45), in: Capsule())
    }
}

/// Eğrinin küçük önizlemesi (profil kartı).
struct Sparkline: View {
    let points: [CurvePoint]

    var body: some View {
        GeometryReader { geo in
            let pts = points.sorted { $0.temp < $1.temp }
            let x = { (t: Double) in CGFloat((t - 30) / 75) * geo.size.width }
            let y = { (p: Double) in geo.size.height - 1 - CGFloat(p / 100) * (geo.size.height - 2) }
            if let first = pts.first, let last = pts.last {
                let line = Path { path in
                    path.move(to: CGPoint(x: 0, y: y(first.percent)))
                    for p in pts { path.addLine(to: CGPoint(x: x(p.temp), y: y(p.percent))) }
                    path.addLine(to: CGPoint(x: geo.size.width, y: y(last.percent)))
                }
                var fill: Path {
                    var f = line
                    f.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    f.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    f.closeSubpath()
                    return f
                }
                fill.fill(LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.03)],
                                         startPoint: .top, endPoint: .bottom))
                line.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

/// Menü çubuğu simgesi: normalde sistem rengine uyar, ısınınca renklenir.
func menuBarSymbol(level: Int, connected: Bool) -> NSImage {
    let name = !connected ? "fan.slash" : level == 2 ? "exclamationmark.triangle.fill" : "fan"
    let base = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    let color: NSColor? = level == 2 ? .systemRed : level == 1 ? .systemOrange : nil
    let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Pervane")
        ?? NSImage(systemSymbolName: "fan", accessibilityDescription: "Pervane")!
    if let color, let tinted = symbol.withSymbolConfiguration(base.applying(.init(paletteColors: [color]))) {
        tinted.isTemplate = false
        return tinted
    }
    let plain = symbol.withSymbolConfiguration(base) ?? symbol
    plain.isTemplate = true
    return plain
}
