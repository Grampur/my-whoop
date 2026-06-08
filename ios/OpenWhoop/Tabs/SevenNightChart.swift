import SwiftUI
import WhoopStore

// MARK: - SevenNightChart
// Gantt-style 7-night sleep/wake timeline.
//
// Layout: each NIGHT is ONE row. Multiple sessions on the same night (naps +
// main sleep) each get their own bar on the same row.
//
// Default label state: only the LONGEST bar's start and end times are shown
// (that's the main sleep). Tapping any other bar selects it — the longest
// bar's labels hide and that bar's start/end appear instead. Tapping the
// selected bar again (or it being the longest) resets to default.
// Selection is ephemeral — resets on next data load.

struct SevenNightChart: View {
    let sessions: [CachedSleepSession]

    // MARK: - Static formatters

    private static let nightLabelFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE M/d"
        return fmt
    }()

    private static let clockFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        fmt.amSymbol = "AM"
        fmt.pmSymbol = "PM"
        return fmt
    }()

    // MARK: - Layout constants

    private let labelColumnWidth: CGFloat = 54
    private let rowHeight:        CGFloat = 44
    private let barHeight:        CGFloat = 14
    private let axisHeight:       CGFloat = 28

    // MARK: - Models

    struct SessionBar {
        let index:    Int       // position within the night's bars
        let xStart:   Double
        let xEnd:     Double
        let bedtime:  String
        let waketime: String
        let duration: Double    // seconds — used to find the longest bar
        let isLongest: Bool
    }

    struct NightRow: Identifiable {
        let id:    String
        let label: String
        let bars:  [SessionBar]
    }

    // MARK: - Time helpers

    private func hoursFromBaseline(_ epochSeconds: Int, referenceSixPm: Date) -> Double {
        let target = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        return target.timeIntervalSince(referenceSixPm) / 3600
    }

    private func referenceSixPm(for session: CachedSleepSession) -> Date {
        let cal = Calendar.current
        let startDate = Date(timeIntervalSince1970: TimeInterval(session.startTs))
        var comps = cal.dateComponents([.year, .month, .day], from: startDate)
        comps.hour = 18; comps.minute = 0; comps.second = 0
        guard let sameDaySixPm = cal.date(from: comps) else { return startDate }
        if startDate < sameDaySixPm {
            return cal.date(byAdding: .day, value: -1, to: sameDaySixPm) ?? sameDaySixPm
        }
        return sameDaySixPm
    }

    private func nightLabel(_ session: CachedSleepSession) -> String {
        let cal = Calendar.current
        let startDate = Date(timeIntervalSince1970: TimeInterval(session.startTs))
        var comps = cal.dateComponents([.year, .month, .day], from: startDate)
        comps.hour = 18; comps.minute = 0; comps.second = 0
        guard let sameDaySixPm = cal.date(from: comps) else {
            return SevenNightChart.nightLabelFormatter.string(from: startDate)
        }
        // If session started before 6 PM, it belongs to the previous night
        let labelDate: Date
        if startDate < sameDaySixPm {
            labelDate = cal.date(byAdding: .day, value: -1, to: startDate) ?? startDate
        } else {
            labelDate = startDate
        }
        return SevenNightChart.nightLabelFormatter.string(from: labelDate)
    }

    private func clockTime(_ epochSeconds: Int) -> String {
        SevenNightChart.clockFormatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        )
    }

    // MARK: - Grouping

    private func buildNightRows() -> [NightRow] {
        var groups: [(label: String, sessions: [CachedSleepSession])] = []
        var labelIndex: [String: Int] = [:]

        for s in sessions {
            let label = nightLabel(s)
            if let idx = labelIndex[label] {
                groups[idx].sessions.append(s)
            } else {
                labelIndex[label] = groups.count
                groups.append((label: label, sessions: [s]))
            }
        }

        return groups.map { group in
            let sorted = group.sessions.sorted { $0.startTs < $1.startTs }
            let durations = sorted.map { Double($0.endTs - $0.startTs) }
            let maxDuration = durations.max() ?? 0

            let bars: [SessionBar] = sorted.enumerated().map { idx, s in
                let sixPm    = referenceSixPm(for: s)
                let duration = Double(s.endTs - s.startTs)
                return SessionBar(
                    index:     idx,
                    xStart:    hoursFromBaseline(s.startTs, referenceSixPm: sixPm),
                    xEnd:      hoursFromBaseline(s.endTs,   referenceSixPm: sixPm),
                    bedtime:   clockTime(s.startTs),
                    waketime:  clockTime(s.endTs),
                    duration:  duration,
                    isLongest: duration == maxDuration
                )
            }
            return NightRow(id: group.label, label: group.label, bars: bars)
        }
    }

    // MARK: - Body

    var body: some View {
        let rows = buildNightRows()
        let allX = rows.flatMap { $0.bars.flatMap { [$0.xStart, $0.xEnd] } }
        let xMin = (allX.min() ?? 4.0) - 0.5
        let xMax = (allX.max() ?? 14.0) + 0.75
        let candidates: [Double] = [3.0, 6.0, 9.0, 12.0, 15.0, 18.0]
        let axisTicks = candidates.filter { $0 >= xMin && $0 <= xMax }

        VStack(alignment: .leading, spacing: 0) {
            if rows.count < 2 {
                HStack {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(WH.Color.textSecondary)
                    Text(rows.isEmpty
                         ? "No nights recorded yet"
                         : "One night recorded — collect more for the trend view")
                        .font(WH.Font.caption)
                        .foregroundStyle(WH.Color.textSecondary)
                    Spacer()
                }
                .padding(WH.Spacing.md)
            } else {
                GanttCanvas(
                    rows: rows,
                    xMin: xMin,
                    xMax: xMax,
                    axisTicks: axisTicks,
                    labelColumnWidth: labelColumnWidth,
                    rowHeight: rowHeight,
                    barHeight: barHeight,
                    axisHeight: axisHeight
                )
            }
        }
        .padding(WH.Spacing.md)
        .background(WH.Color.surface,
                    in: RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: WH.Radius.card, style: .continuous))
    }
}

// MARK: - GanttCanvas

private struct GanttCanvas: View {
    let rows:             [SevenNightChart.NightRow]
    let xMin:             Double
    let xMax:             Double
    let axisTicks:        [Double]
    let labelColumnWidth: CGFloat
    let rowHeight:        CGFloat
    let barHeight:        CGFloat
    let axisHeight:       CGFloat

    private func axisLabel(hoursFromSixPm: Double) -> String {
        let totalHour = Int(18 + hoursFromSixPm) % 24
        let isPm      = totalHour >= 12
        let display   = totalHour % 12 == 0 ? 12 : totalHour % 12
        return "\(display)\(isPm ? "p" : "a")"
    }

    var body: some View {
        GeometryReader { geo in
            canvasContent(totalWidth: geo.size.width)
        }
        .frame(height: CGFloat(rows.count) * rowHeight + axisHeight)
    }

    @ViewBuilder
    private func canvasContent(totalWidth: CGFloat) -> some View {
        let trackWidth  = totalWidth - labelColumnWidth
        let totalHeight = CGFloat(rows.count) * rowHeight + axisHeight
        let scale = { (v: Double) -> CGFloat in
            CGFloat((v - xMin) / (xMax - xMin)) * trackWidth
        }

        ZStack(alignment: .topLeading) {
            ForEach(axisTicks, id: \.self) { tick in
                Rectangle()
                    .fill(WH.Color.separator.opacity(0.4))
                    .frame(width: 1, height: CGFloat(rows.count) * rowHeight)
                    .offset(x: labelColumnWidth + scale(tick), y: 0)
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                NightRowView(
                    row: row,
                    index: idx,
                    labelColumnWidth: labelColumnWidth,
                    rowHeight: rowHeight,
                    barHeight: barHeight,
                    trackWidth: trackWidth,
                    xScale: scale
                )
            }

            let axisY = CGFloat(rows.count) * rowHeight
            Rectangle()
                .fill(WH.Color.separator)
                .frame(width: trackWidth, height: 1)
                .offset(x: labelColumnWidth, y: axisY)

            ForEach(axisTicks, id: \.self) { tick in
                AxisTickView(
                    tick: tick,
                    label: axisLabel(hoursFromSixPm: tick),
                    axisY: axisY,
                    labelColumnWidth: labelColumnWidth,
                    totalWidth: totalWidth,
                    xScale: scale
                )
            }

            Color.clear.frame(width: totalWidth, height: totalHeight)
        }
    }
}

// MARK: - NightRowView
// Manages its own selected bar index. nil = default (show longest bar's labels).
// Tapping the longest bar is a no-op. Tapping any other bar selects it;
// tapping the already-selected bar deselects back to default.

private struct NightRowView: View {
    let row:              SevenNightChart.NightRow
    let index:            Int
    let labelColumnWidth: CGFloat
    let rowHeight:        CGFloat
    let barHeight:        CGFloat
    let trackWidth:       CGFloat
    let xScale:           (Double) -> CGFloat

    @State private var selectedBarIndex: Int? = nil

    var body: some View {
        let yTop   = CGFloat(index) * rowHeight
        let barY   = yTop + (rowHeight - barHeight) / 2
        let labelY = yTop + (rowHeight - 14) / 2

        let activeIndex: Int = {
            if let sel = selectedBarIndex { return sel }
            return row.bars.firstIndex(where: { $0.isLongest }) ?? 0
        }()

        ZStack(alignment: .topLeading) {

            Text(row.label)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(WH.Color.textSecondary)
                .frame(width: labelColumnWidth, alignment: .leading)
                .offset(x: 0, y: labelY)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(WH.Color.surface2)
                .frame(width: trackWidth, height: barHeight)
                .offset(x: labelColumnWidth, y: barY)

            ForEach(Array(row.bars.enumerated()), id: \.offset) { idx, bar in
                let barX0 = labelColumnWidth + xScale(bar.xStart)
                let barX1 = labelColumnWidth + xScale(bar.xEnd)
                let barW  = max(barX1 - barX0, 4)
                let isActive = idx == activeIndex

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [WH.Color.sleepPurple, WH.Color.stageLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(bar.isLongest ? 1.0 : 0.55)
                    .frame(width: barW, height: barHeight)
                    .offset(x: barX0, y: barY)
                    .onTapGesture {
                        guard !bar.isLongest else { return }
                        selectedBarIndex = (selectedBarIndex == idx) ? nil : idx
                    }

                if isActive {
                    // Bedtime — left of bar
                    Text(bar.bedtime)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(WH.Color.sleepPurple)
                        .frame(width: 60, alignment: .leading)
                        .offset(x: barX0, y: barY - 12)

                    // Waketime — right of bar, but clamped so it never
                    // overlaps the bedtime label (min 62pt gap between starts)
                    let wakeX = max(barX1 - 60, barX0 + 62)
                    Text(bar.waketime)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(WH.Color.stageLight)
                        .frame(width: 60, alignment: .trailing)
                        .offset(x: wakeX, y: barY - 12)
                }
            }
        }
        // Reset selection whenever the row data changes (pull-to-refresh)
        .id(row.id + String(row.bars.count))
    }
}

// MARK: - AxisTickView

private struct AxisTickView: View {
    let tick:             Double
    let label:            String
    let axisY:            CGFloat
    let labelColumnWidth: CGFloat
    let totalWidth:       CGFloat
    let xScale:           (Double) -> CGFloat

    var body: some View {
        let x          = labelColumnWidth + xScale(tick)
        let labelWidth: CGFloat = 28
        let clampedX   = min(x, totalWidth - labelWidth / 2)

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(WH.Color.separator)
                .frame(width: 1, height: 5)
                .offset(x: x, y: axisY + 1)

            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(WH.Color.textSecondary)
                .frame(width: labelWidth, alignment: .center)
                .offset(x: clampedX - labelWidth / 2, y: axisY + 7)
        }
    }
}