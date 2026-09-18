import SwiftUI

/// Registro de asistencia por materia.
///
/// Es un registro **propio y local**: marcás vos a qué clases fuiste. No
/// depende de que UAM tenga instalado el plugin `mod_attendance` de Moodle
/// (que es de terceros y puede no existir). Si el sitio SÍ lo tiene, se avisa
/// arriba para que sepas que la asistencia oficial vive allá.
struct AsistenciaView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared

    @State private var selectedDate = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                if state.visibleCourses.isEmpty {
                    Card {
                        EmptyState(icon: "person.badge.clock",
                                   title: "Sin materias",
                                   subtitle: "No hay materias en el semestre seleccionado.")
                    }
                } else {
                    budgetSection
                    dayStrip
                    courseList
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Presupuesto de faltas

    private var budgets: [AttendanceBudget] {
        AttendanceBudgetIndex.budgets(courses: state.visibleCourses, store: store)
    }

    private var budgetSection: some View {
        let list = budgets.sorted { $0.remaining < $1.remaining }
        let sinHorario = list.filter { !$0.fromSchedule }.count

        return VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: "gauge.with.needle",
                        title: "Cuántas faltas te quedan",
                        count: list.count) { EmptyView() }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Space.sm)],
                      spacing: Space.sm) {
                ForEach(list, id: \.courseID) { b in
                    budgetCard(b)
                }
            }

            if sinHorario > 0 {
                Text("\(sinHorario) materia\(sinHorario == 1 ? "" : "s") no está\(sinHorario == 1 ? "" : "n") en tu Horario, así que asumí una sesión por semana — el caso más estricto. Cargalas en Horario para que el cálculo sea real.")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textQuaternary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func budgetCard(_ b: AttendanceBudget) -> some View {
        let tone: Color = {
            switch b.standing {
            case .holgado:  return Palette.success
            case .ajustado: return Palette.warning
            case .alLimite: return Palette.warning
            case .perdido:  return Palette.danger
            }
        }()

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(b.courseCode)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
                Pill(text: b.standing.label, tone: .custom(tone), compact: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(b.remaining)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(b.exhausted ? Palette.danger : Palette.textPrimary)
                Text("de \(b.allowed)")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)
                if !b.fromSchedule {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textQuaternary)
                        .help("Materia no encontrada en tu Horario: se asumió 1 sesión por semana")
                }
            }

            // La barra se llena con lo GASTADO: se lee como un tanque vaciándose.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.textPrimary.opacity(0.10))
                    Capsule().fill(tone)
                        .frame(width: max(3, geo.size.width * b.ratio))
                }
            }
            .frame(height: 5)

            Text(b.sentence)
                .font(Type.micro)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    private var header: some View {
        SectionHeader(
            title: "Asistencia",
            eyebrow: "Registro propio",
            subtitle: summaryLine,
            trailing: AnyView(
                Button {
                    selectedDate = Date()
                } label: {
                    Text("Hoy").font(.system(size: 11.5, weight: .medium))
                }
                .nativeGlassButton()
                .controlSize(.small)
                .disabled(Calendar.current.isDateInToday(selectedDate))
            )
        )
    }

    private var summaryLine: String {
        let rates = state.visibleCourses.compactMap { store.attendanceRate(courseId: $0.id) }
        guard !rates.isEmpty else {
            return "Marcá tus clases y llevá la cuenta vos mismo"
        }
        let avg = rates.reduce(0, +) / Double(rates.count)
        return "Promedio de asistencia: \(Int((avg * 100).rounded()))%"
    }

    // MARK: Tira de días

    private var dayStrip: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Dos semanas hacia atrás: marcar asistencia suele hacerse en diferido.
        let days = (0..<14).reversed().map {
            cal.date(byAdding: .day, value: -$0, to: today)!
        }

        return VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: "calendar", title: "Día")
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
            .padding(Space.xs)
            .adaptiveSurface(prefs, cornerRadius: Radius.md)
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let selected = cal.isDate(day, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(day)
        let marked = state.visibleCourses.contains {
            store.attendance(courseId: $0.id, date: day) != nil
        }

        return Button {
            withAnimation(Motion.quick) { selectedDate = day }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.narrow)).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? Palette.textOnAccent : Palette.textTertiary)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: isToday ? .heavy : .medium, design: .rounded))
                    .foregroundStyle(selected ? Palette.textOnAccent : Palette.textPrimary)
                Circle()
                    .fill(marked ? (selected ? Palette.textOnAccent : Palette.textPrimary)
                                 : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(selected ? Palette.accent : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(isToday && !selected ? Palette.borderStrong : Color.clear,
                                  lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(day.formatted(date: .complete, time: .omitted))
    }

    // MARK: Materias

    private var courseList: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: "books.vertical",
                        title: selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                        count: state.visibleCourses.count)

            VStack(spacing: 0) {
                ForEach(Array(state.visibleCourses.enumerated()), id: \.element.id) { i, course in
                    AttendanceRow(course: course,
                                  date: selectedDate,
                                  isLast: i == state.visibleCourses.count - 1)
                }
            }
            .adaptiveSurface(prefs, cornerRadius: Radius.md)
        }
    }
}

// MARK: - Fila

private struct AttendanceRow: View {
    let course: MoodleCourse
    let date: Date
    let isLast: Bool

    @EnvironmentObject private var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared

    private var accent: Color { CourseAccent.color(for: course) }
    private var record: AttendanceRecord? { store.attendance(courseId: course.id, date: date) }

    var body: some View {
        let info = CourseInfo(course: course)

        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(info.code)
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(accent)
                    Text(info.name)
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.sm)

                if let rate = store.attendanceRate(courseId: course.id) {
                    Text("\(Int((rate * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(rate < 0.75 ? Palette.danger : Palette.textSecondary)
                        .help("Asistencia registrada en esta materia")
                }

                // Los cuatro estados, siempre visibles: marcar tiene que ser un
                // click, no un menú desplegable.
                HStack(spacing: 3) {
                    ForEach(AttendanceStatus.allCases) { status in
                        StatusButton(status: status,
                                     selected: record?.status == status) {
                            if record?.status == status {
                                store.clearAttendance(courseId: course.id, date: date)
                            } else {
                                store.markAttendance(courseId: course.id,
                                                     date: date, status: status)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, prefs.padLarge)
            .padding(.vertical, 9)

            if !isLast {
                Divider().overlay(Palette.divider).padding(.leading, prefs.padLarge)
            }
        }
    }
}

private struct StatusButton: View {
    let status: AttendanceStatus
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: status.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? Palette.textOnAccent : status.tone.opacity(0.7))
                .frame(width: 26, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(selected ? status.tone
                                       : Palette.textPrimary.opacity(hovered ? 0.06 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .strokeBorder(selected ? Color.clear : Palette.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
        .help(status.label)
    }
}
