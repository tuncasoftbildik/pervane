import Charts
import PervaneCore
import SwiftUI

/// Son 30 dakika: sıcaklık çizgisi, altında fan yüzdesi dolgusu.
struct HistoryChart: View {
    let samples: [Sample]
    let fan: FanState?
    let emergency: Double

    @State private var hover: Sample?

    private let low = 20.0, high = 105.0

    private func percent(_ s: Sample) -> Double {
        guard let fan, fan.max > fan.min else { return 0 }
        return min(100, max(0, (s.rpm - fan.min) / (fan.max - fan.min) * 100))
    }

    /// Fan yüzdesini sıcaklık eksenine oturtur: %0 altta, %100 üstte.
    private func fanY(_ s: Sample) -> Double { low + percent(s) / 100 * (high - low) }

    var body: some View {
        let now = Date().timeIntervalSince1970
        // 30 dakikalık geçmişi ~180 noktaya indir.
        let recent = samples.filter { $0.t >= now - 30 * 60 }
        let step = max(1, recent.count / 180)
        let points = step == 1 ? recent : recent.enumerated().filter { $0.offset % step == 0 }.map(\.element)

        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(points, id: \.t) { s in
                    AreaMark(x: .value("dk", (s.t - now) / 60), yStart: .value("alt", low), yEnd: .value("fan", fanY(s)))
                        .foregroundStyle(LinearGradient(colors: [fanTint.opacity(0.38), fanTint.opacity(0.08)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                ForEach(points, id: \.t) { s in
                    LineMark(x: .value("dk", (s.t - now) / 60), y: .value("°C", min(high, max(low, s.temp))))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("eşik", emergency))
                    .foregroundStyle(.red.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if let h = hover {
                    RuleMark(x: .value("dk", (h.t - now) / 60))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: -30...0)
            .chartYScale(domain: low...high)
            .chartPlotStyle { $0.clipped() }
            .chartXAxis {
                AxisMarks(values: [-30, -20, -10, 0]) { v in
                    AxisGridLine()
                    AxisValueLabel { Text(v.as(Int.self) == 0 ? "şimdi" : "\(v.as(Int.self) ?? 0) dk") }
                }
            }
            .chartYAxis {
                AxisMarks(values: [40, 60, 80, 100]) { v in
                    AxisGridLine()
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)°") }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                guard let frame = proxy.plotFrame.map({ geo[$0] }),
                                      let minutes: Double = proxy.value(atX: loc.x - frame.minX) else { return }
                                let t = now + minutes * 60
                                hover = samples.min { abs($0.t - t) < abs($1.t - t) }
                            case .ended:
                                hover = nil
                            }
                        }
                }
            }
            .frame(height: 104)

            HStack(spacing: 10) {
                legend(.orange, "Sıcaklık")
                legend(fanTint, "Fan")
                Spacer()
                if let h = hover {
                    let ago = Int(((now - h.t) / 60).rounded())
                    Text("\(ago == 0 ? "şimdi" : "\(ago) dk önce") · \(Int(h.temp.rounded()))° · %\(Int(percent(h).rounded()))")
                        .monospacedDigit()
                } else {
                    Text("son 30 dakika").foregroundStyle(.tertiary)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }
}
