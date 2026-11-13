import Charts
import PervaneCore
import SwiftUI

struct ProfileEditor: View {
    let profile: Profile
    let canDelete: Bool
    let onChange: (Profile) -> Void
    let onDelete: () -> Void

    private func change(_ edit: (inout Profile) -> Void) {
        var p = profile
        edit(&p)
        onChange(p)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Kip", selection: Binding(get: { profile.mode }, set: { v in
                change { p in
                    p.mode = v
                    if v == .curve, p.curve.isEmpty { p.curve = [.init(45, 0), .init(90, 100)] }
                }
            })) {
                ForEach(FanMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch profile.mode {
            case .fixed:
                HStack {
                    Slider(value: Binding(get: { profile.fixedPercent }, set: { v in change { $0.fixedPercent = v } }),
                           in: 0...100, step: 5)
                    Text("%\(Int(profile.fixedPercent))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            case .curve:
                CurveEditor(points: profile.curve) { pts in change { $0.curve = pts } }
                HStack {
                    Picker("Sensör", selection: Binding(get: { profile.sensor }, set: { v in change { $0.sensor = v } })) {
                        ForEach(SensorKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .frame(width: 150)
                    Spacer()
                    Stepper("Bant \(Int(profile.hysteresis))°",
                            value: Binding(get: { profile.hysteresis }, set: { v in change { $0.hysteresis = v } }),
                            in: 0...15, step: 1)
                }
                HStack {
                    Button("Nokta Ekle") {
                        change { p in
                            let sorted = p.curve.sorted { $0.temp < $1.temp }
                            let last = sorted.last ?? CurvePoint(60, 50)
                            p.curve.append(CurvePoint(min(105, last.temp + 5), last.percent))
                        }
                    }
                    .disabled(profile.curve.count >= 12)
                    Button("Nokta Sil") { change { p in p.curve = Array(p.curve.sorted { $0.temp < $1.temp }.dropLast()) } }
                        .disabled(profile.curve.count <= 2)
                }
                .buttonStyle(.link)
            case .auto, .max:
                EmptyView()
            }
            if canDelete {
                Button("Profili Sil", role: .destructive, action: onDelete).buttonStyle(.link)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Sürüklenebilir noktalı fan eğrisi: yatay sıcaklık, dikey devir yüzdesi.
struct CurveEditor: View {
    let points: [CurvePoint]
    let onChange: ([CurvePoint]) -> Void

    @State private var draft: [CurvePoint]?
    @State private var dragIndex: Int?

    private let tempRange = 30.0...105.0

    var body: some View {
        let shown = (draft ?? points).sorted { $0.temp < $1.temp }
        Chart {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("°C", p.temp), y: .value("%", p.percent))
                PointMark(x: .value("°C", p.temp), y: .value("%", p.percent)).symbolSize(90)
            }
        }
        .chartXScale(domain: tempRange)
        .chartYScale(domain: 0...100)
        .chartXAxis { AxisMarks(values: [40, 60, 80, 100]) { v in
            AxisGridLine()
            AxisValueLabel(collisionResolution: .disabled) { Text("\(v.as(Int.self) ?? 0)°").fixedSize() }
        } }
        .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in
            AxisGridLine()
            AxisValueLabel { Text("%\(v.as(Int.self) ?? 0)") }
        } }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard let frame = proxy.plotFrame.map({ geo[$0] }) else { return }
                            let loc = CGPoint(x: g.location.x - frame.minX, y: g.location.y - frame.minY)
                            guard let t: Double = proxy.value(atX: loc.x), let pct: Double = proxy.value(atY: loc.y) else { return }
                            var pts = shown
                            if dragIndex == nil {
                                // En yakın noktayı tut.
                                dragIndex = pts.indices.min { a, b in
                                    distance(pts[a], t, pct) < distance(pts[b], t, pct)
                                }
                            }
                            guard let i = dragIndex else { return }
                            // Komşularını geçemez; sıra bozulmaz.
                            let lo = i > 0 ? pts[i - 1].temp + 1 : tempRange.lowerBound
                            let hi = i < pts.count - 1 ? pts[i + 1].temp - 1 : tempRange.upperBound
                            pts[i] = CurvePoint(min(hi, max(lo, t.rounded())), (min(100, max(0, pct)) / 5).rounded() * 5)
                            draft = pts
                        }
                        .onEnded { _ in
                            if let d = draft { onChange(d) }
                            draft = nil
                            dragIndex = nil
                        })
            }
        }
        .frame(height: 130)
    }

    private func distance(_ p: CurvePoint, _ t: Double, _ pct: Double) -> Double {
        // Eksenler farklı ölçekte; yüzdeyi sıcaklık aralığına oranla.
        let dx = p.temp - t, dy = (p.percent - pct) * 0.75
        return dx * dx + dy * dy
    }
}
