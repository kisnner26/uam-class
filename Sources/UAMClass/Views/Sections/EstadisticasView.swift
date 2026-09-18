import SwiftUI
import Charts

struct EstadisticasView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared
    @State private var range: TimeRange = .week

    enum TimeRange: String, CaseIterable, Identifiable, Hashable {
        case week, month, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week:  return "7 días"
            case .month: return "30 días"
            case .all:   return "Todo"
            }
        }
        var days: Int? {
            switch self {
            case .week:  return 7
            case .month: return 30
            case .all:   return nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                heroWidgets
                studyChartCard
                HStack(alignment: .top, spacing: Space.md) {
                    courseBreakdown
                    sessionsHistory
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Header

    private var header: some View {
        SectionHeader(
            title: "Estadísticas",
            eyebrow: "Analítica",
            subtitle: "Tu tiempo de estudio y constancia",
            trailing: AnyView(
                GlassSegmented(selection: $range,
                               options: TimeRange.allCases.map { .init($0, label: $0.label) })
            )
        )
    }

    // MARK: Métricas

    private var heroWidgets: some View {
        HStack(spacing: prefs.gap) {
            MetricTile(icon: "clock.badge.checkmark.fill", label: "Tiempo total",
                       value: formatTime(totalTime), tint: Palette.bay)
            MetricTile(icon: "flame.fill", label: "Racha",
                       value: "\(currentStreak)d", tint: Palette.warning,
                       caption: currentStreak > 0 ? "sin cortar" : nil)
            MetricTile(icon: "chart.line.uptrend.xyaxis", label: "Sesiones",
                       value: "\(filteredSessions.count)", tint: Palette.success)
            MetricTile(icon: "timer", label: "Promedio",
                       value: formatTime(avgSession), tint: prefs.tint,
                       caption: "por sesión")
        }
    }

    private var totalTime: TimeInterval {
        filteredSessions.reduce(0) { $0 + $1.duration }
    }

    private var avgSession: TimeInterval {
        filteredSessions.isEmpty ? 0 : totalTime / Double(filteredSessions.count)
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let days = Set(store.studySessions.map { calendar.startOfDay(for: $0.start) })
        var streak = 0
        var day = calendar.startOfDay(for: Date())
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    private var filteredSessions: [StudySession] {
        guard let days = range.days else { return store.studySessions }
        let since = Date().addingTimeInterval(-Double(days) * 86400)
        return store.studySessions.filter { $0.start >= since }
    }

    // MARK: Chart

    private var studyChartCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            BlockHeader(icon: "chart.bar.fill", title: "Tiempo estudiado por día") {
                Text("minutos")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
            }

            let buckets = dailyBuckets()

            if buckets.allSatisfy({ $0.minutes == 0 }) {
                EmptyState(icon: "chart.bar",
                           title: "Sin datos todavía",
                           subtitle: "Arrancá una sesión de estudio (⌘T) y el gráfico se llena solo.")
                    .frame(height: 200)
            } else {
                Chart(buckets, id: \.day) { bucket in
                    // Área de fondo: da la forma de la tendencia.
                    AreaMark(
                        x: .value("Día", bucket.day),
                        y: .value("Minutos", bucket.minutes)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [prefs.tint.opacity(0.24), prefs.tint.opacity(0.01)],
                                       startPoint: .top, endPoint: .bottom)
                    )

                    // Barras encima: dan el valor exacto de cada día.
                    BarMark(
                        x: .value("Día", bucket.day),
                        y: .value("Minutos", bucket.minutes),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [prefs.tint, prefs.tint.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(3)
                }
                .frame(height: 230)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Palette.divider)
                        AxisValueLabel()
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel(format: .dateTime.day().month(.narrow), centered: true)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .chartPlotStyle { plot in
                    plot.background(Color.clear)
                }
            }
        }
        .padding(prefs.padLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    private var barWidth: CGFloat {
        switch range {
        case .week:  return 22
        case .month: return 7
        case .all:   return 7
        }
    }

    private struct DayBucket {
        let day: Date
        let minutes: Double
    }

    private func dailyBuckets() -> [DayBucket] {
        let calendar = Calendar.current
        let days = range.days ?? 30
        let startDay = calendar.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))

        var byDay: [Date: TimeInterval] = [:]
        for i in 0..<days {
            let d = calendar.date(byAdding: .day, value: i, to: startDay)!
            byDay[d] = 0
        }
        for s in store.studySessions {
            let day = calendar.startOfDay(for: s.start)
            if byDay[day] != nil {
                byDay[day]! += s.duration
            }
        }
        return byDay
            .sorted { $0.key < $1.key }
            .map { DayBucket(day: $0.key, minutes: $0.value / 60) }
    }

    // MARK: Por materia

    private var courseBreakdown: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            BlockHeader(icon: "books.vertical.fill", title: "Por materia",
                        count: perCourse.isEmpty ? nil : perCourse.count)

            if perCourse.isEmpty {
                Text("Todavía no hay sesiones registradas. Empezá una desde el toolbar (⌘T).")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Space.xs)
            } else {
                VStack(spacing: Space.sm) {
                    ForEach(perCourse, id: \.courseId) { entry in
                        CourseTimeBar(entry: entry, maxTime: perCourse.first?.time ?? 1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(prefs.padLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    struct CourseTimeEntry {
        let courseId: Int
        let name: String
        let code: String
        let time: TimeInterval
        let color: Color
    }

    private var perCourse: [CourseTimeEntry] {
        var bucket: [Int: TimeInterval] = [:]
        for s in filteredSessions {
            bucket[s.courseId, default: 0] += s.duration
        }
        return bucket
            .compactMap { (id, t) -> CourseTimeEntry? in
                guard let c = state.courses.first(where: { $0.id == id }) else { return nil }
                let info = CourseInfo(course: c)
                return CourseTimeEntry(courseId: id, name: info.name, code: info.code,
                                       time: t, color: CourseAccent.color(for: c))
            }
            .sorted { $0.time > $1.time }
    }

    // MARK: Historial

    private var sessionsHistory: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            BlockHeader(icon: "clock.arrow.circlepath", title: "Historial reciente")

            if filteredSessions.isEmpty {
                Text("Sin sesiones registradas todavía.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, Space.xs)
            } else {
                let recent = Array(filteredSessions.suffix(12).reversed())
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { i, s in
                        SessionRow(session: s,
                                   course: state.courses.first { $0.id == s.courseId },
                                   isLast: i == recent.count - 1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(prefs.padLarge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    // MARK: Utils

    private func formatTime(_ t: TimeInterval) -> String {
        let hours = Int(t) / 3600
        let mins = (Int(t) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: StudySession
    let course: MoodleCourse?
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let c = course {
                    IconTile(text: String(CourseInfo(course: c).code.prefix(3)),
                             tint: CourseAccent.color(for: c), size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(CourseInfo(course: c).name)
                            .font(Type.caption)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Text(session.start,
                             format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(Type.micro)
                            .foregroundStyle(Palette.textTertiary)
                    }
                } else {
                    Text("Curso desconocido")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: Space.xs)
                Text(formatDur(session.duration))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .monospacedDigit()
            }
            .padding(.vertical, 7)

            if !isLast {
                Divider().overlay(Palette.divider).padding(.leading, 38)
            }
        }
    }

    private func formatDur(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Barra por materia

private struct CourseTimeBar: View {
    let entry: EstadisticasView.CourseTimeEntry
    let maxTime: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.code)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(entry.color)
                Text(entry.name)
                    .font(Type.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.xs)
                Text(formatTime(entry.time))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(entry.color)
                    .monospacedDigit()
            }
            AccentBar(value: maxTime > 0 ? entry.time / maxTime : 0,
                      tint: entry.color, height: 5)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let hours = Int(t) / 3600
        let mins = (Int(t) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
