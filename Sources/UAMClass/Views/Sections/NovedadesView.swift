import SwiftUI

/// El diario de cambios silenciosos.
///
/// Lo que Moodle no te dice: que movieron una entrega, que reescribieron un
/// enunciado, que apareció o desapareció material. Cada escaneo compara la
/// materia con la última foto guardada y anota la diferencia.
struct NovedadesView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var watcher = ChangeWatcher.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header

                if watcher.scanning && watcher.changes.isEmpty {
                    scanningCard
                } else if watcher.baselineOnly && watcher.changes.isEmpty {
                    baselineCard
                } else if watcher.changes.isEmpty {
                    Card {
                        EmptyState(icon: "checkmark.circle",
                                   title: "Nada cambió",
                                   subtitle: "Desde la última revisión, ningún docente movió fechas ni editó material. Volvé a buscar cuando quieras.",
                                   actionTitle: "Buscar cambios",
                                   action: { scan() })
                    }
                } else {
                    ForEach(days, id: \.self) { day in
                        daySection(day)
                    }
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .task(id: state.visibleCourses.map(\.id)) {
            await watcher.scan(courses: state.visibleCourses, moodle: state.moodle)
        }
        .onDisappear { watcher.markAllSeen() }
    }

    // MARK: Encabezado

    private var header: some View {
        SectionHeader(
            title: "Novedades",
            eyebrow: "Cambios silenciosos",
            subtitle: subtitle,
            trailing: AnyView(
                HStack(spacing: 8) {
                    if watcher.scanning { ProgressView().controlSize(.small) }
                    if !watcher.changes.isEmpty {
                        Button { watcher.clear() } label: {
                            Label("Vaciar", systemImage: "trash")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .nativeGlassButton()
                        .controlSize(.small)
                    }
                    Button { scan() } label: {
                        Label("Buscar cambios", systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .nativeGlassButton(prominent: true)
                    .tint(prefs.tint)
                    .controlSize(.small)
                    .disabled(watcher.scanning)
                }
            )
        )
    }

    private var subtitle: String {
        if watcher.scanning {
            return "Comparando materias… \(Int(watcher.progress * 100))%"
        }
        guard let last = watcher.lastScan else {
            return "Lo que Moodle edita sin avisarte"
        }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.unitsStyle = .full
        let cuando = f.localizedString(for: last, relativeTo: Date())
        if watcher.changes.isEmpty { return "Revisado \(cuando) · sin cambios" }
        let n = watcher.unseenCount
        return n > 0
            ? "Revisado \(cuando) · \(n) sin leer"
            : "Revisado \(cuando) · \(watcher.changes.count) en el diario"
    }

    private var scanningCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Comparando cada materia con la última foto guardada…")
                    .font(Type.body)
                    .foregroundStyle(Palette.textSecondary)
                AccentBar(value: watcher.progress, tint: prefs.tint, height: 5)
                ForEach(0..<2, id: \.self) { _ in SkeletonRow() }
            }
        }
    }

    /// La primera vez no hay con qué comparar. Decirlo explícitamente evita que
    /// parezca que la función no sirve.
    private var baselineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(prefs.tint)
                    Text("Primera foto tomada")
                        .font(Type.heading)
                        .foregroundStyle(Palette.textPrimary)
                }
                Text("Acabo de guardar cómo están tus materias ahora mismo: fechas de entrega, enunciados y archivos. Todavía no hay nada que reportar porque no existe una versión anterior con qué compararlas.")
                    .font(Type.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("De acá en adelante, cada vez que busques cambios te voy a decir qué se movió: si un docente adelanta una entrega o reescribe un enunciado, vas a verlo acá.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Agrupado por día

    private var days: [Date] {
        let cal = Calendar.current
        return Array(Set(watcher.changes.map { cal.startOfDay(for: $0.detectedAt) }))
            .sorted(by: >)
    }

    private func changes(on day: Date) -> [CourseChange] {
        let cal = Calendar.current
        return watcher.changes.filter { cal.isDate($0.detectedAt, inSameDayAs: day) }
    }

    private func daySection(_ day: Date) -> some View {
        let items = changes(on: day)
        let cal = Calendar.current
        let title = cal.isDateInToday(day) ? "Hoy"
                  : cal.isDateInYesterday(day) ? "Ayer"
                  : day.formatted(.dateTime.weekday(.wide).day().month(.wide))

        return VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: "clock", title: title, count: items.count) { EmptyView() }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                    ChangeRow(change: c, isLast: i == items.count - 1)
                }
            }
            .adaptiveSurface(prefs, cornerRadius: Radius.md)
        }
    }

    private func scan() {
        Task { await watcher.scan(courses: state.visibleCourses, moodle: state.moodle) }
    }
}

// MARK: - Fila

private struct ChangeRow: View {
    let change: CourseChange
    let isLast: Bool

    @EnvironmentObject private var prefs: UserPrefs

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.sm) {
                Image(systemName: change.kind.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(change.tone)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(change.courseCode)
                            .font(.system(size: 9.5, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(Palette.textTertiary)
                        Text(change.subject)
                            .font(Type.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        if !change.seen {
                            Circle().fill(prefs.tint).frame(width: 5, height: 5)
                        }
                    }

                    Text(change.detail)
                        .font(Type.caption)
                        .foregroundStyle(change.kind.isCritical
                                         ? Palette.textSecondary : Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.xs)

                Pill(text: change.kind.label,
                     tone: change.kind.isCritical ? .warning : .neutral,
                     compact: true)
            }
            .padding(.horizontal, prefs.padLarge)
            .padding(.vertical, 10)
            .background(change.kind.isCritical
                        ? Palette.warning.opacity(0.06) : Color.clear)

            if !isLast {
                Divider().overlay(Palette.divider).padding(.leading, 46)
            }
        }
    }
}
