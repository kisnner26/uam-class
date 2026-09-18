import SwiftUI

/// Tu semana de clases, escrita a mano.
///
/// Moodle no sabe a qué hora te toca cada materia, así que esto no se sincroniza
/// con nada: lo cargás una vez por semestre y queda. A cambio funciona sin red,
/// sin token y sin que importe qué expone el sitio.
struct HorarioView: View {
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared

    @State private var editing: ClassSlot?
    @State private var showEditor = false

    private var conflicts: Set<UUID> { store.conflictingSlotIDs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header

                if store.schedule.isEmpty {
                    Card {
                        EmptyState(icon: "calendar.badge.plus",
                                   title: "Todavía no cargaste tu horario",
                                   subtitle: "Agregá cada clase con su día, su hora y su sección. Se guarda en esta Mac y no depende de Moodle.",
                                   actionTitle: "Agregar la primera clase",
                                   action: { newSlot() })
                    }
                } else {
                    if !conflicts.isEmpty { conflictNote }
                    ForEach(store.scheduledDays) { day in
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
        .sheet(isPresented: $showEditor) {
            ClassSlotEditor(slot: editing) { saved in
                store.upsertSlot(saved)
            } onDelete: { id in
                store.removeSlot(id)
            }
            .environmentObject(prefs)
        }
    }

    // MARK: Encabezado

    private var header: some View {
        SectionHeader(
            title: "Horario",
            eyebrow: "Tu semana",
            subtitle: subtitle,
            trailing: AnyView(
                Button {
                    newSlot()
                } label: {
                    Label("Agregar clase", systemImage: "plus")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .nativeGlassButton(prominent: true)
                .tint(prefs.tint)
                .controlSize(.small)
            )
        )
    }

    private var subtitle: String {
        let n = store.schedule.count
        if n == 0 { return "Cargá tus clases: día, hora, sección y materia" }
        let hoy = store.slots(on: .today)
        let base = "\(n) clase\(n == 1 ? "" : "s") en \(store.scheduledDays.count) día\(store.scheduledDays.count == 1 ? "" : "s")"
        if hoy.isEmpty { return base + " · hoy no tenés clases" }
        return base + " · hoy tenés \(hoy.count)"
    }

    private var conflictNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.warning)
            Text("Hay clases que se pisan entre sí. Están marcadas abajo — puede ser un error de dedo al cargar la hora.")
                .font(Type.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Palette.warning.opacity(0.10)))
    }

    // MARK: Un día

    private func daySection(_ day: Weekday) -> some View {
        let slots = store.slots(on: day)
        let isToday = day == .today

        return VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: isToday ? "sun.max" : "calendar",
                        title: isToday ? "\(day.label) · hoy" : day.label,
                        count: slots.count) { EmptyView() }

            VStack(spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { i, slot in
                    SlotRow(slot: slot,
                            isLast: i == slots.count - 1,
                            conflicted: conflicts.contains(slot.id)) {
                        editing = slot
                        showEditor = true
                    } onDelete: {
                        store.removeSlot(slot.id)
                    }
                }
            }
            .adaptiveSurface(prefs, cornerRadius: Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(prefs.tint.opacity(isToday ? 0.35 : 0), lineWidth: 1)
            )
        }
    }

    private func newSlot() {
        editing = nil
        showEditor = true
    }
}

// MARK: - Fila de clase

private struct SlotRow: View {
    let slot: ClassSlot
    let isLast: Bool
    let conflicted: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                // La hora manda: es lo primero que se lee en un horario.
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.startText)
                        .font(Type.mono)
                        .foregroundStyle(Palette.textPrimary)
                    Text(slot.endText)
                        .font(Type.mono)
                        .foregroundStyle(Palette.textQuaternary)
                }
                .frame(width: 78, alignment: .leading)

                Rectangle()
                    .fill(conflicted ? Palette.warning : prefs.tint.opacity(0.45))
                    .frame(width: 2.5)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 3) {
                    Text(slot.courseName)
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !slot.section.isEmpty {
                            Pill(text: slot.section, tone: .neutral, compact: true)
                        }
                        if let aula = slot.roomText {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 8))
                                Text(aula)
                            }
                            .font(Type.micro)
                            .foregroundStyle(prefs.tint)
                        }
                        Text(slot.durationText)
                            .font(Type.micro)
                            .foregroundStyle(Palette.textQuaternary)
                        if conflicted {
                            Text("se pisa con otra")
                                .font(Type.micro)
                                .foregroundStyle(Palette.warning)
                        }
                    }
                }

                Spacer(minLength: Space.xs)

                if hovered {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Editar")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.danger)
                    }
                    .buttonStyle(.plain)
                    .help("Eliminar")
                }
            }
            .padding(.horizontal, prefs.padLarge)
            .padding(.vertical, 10)
            .background(RowHighlight(hovered: hovered, tint: Palette.accent))
            .contentShape(Rectangle())
            .consoleHover($hovered)
            .onTapGesture(count: 2, perform: onEdit)
            .animation(Motion.quick, value: hovered)

            if !isLast {
                Divider().overlay(Palette.divider).padding(.leading, 92)
            }
        }
    }
}

// MARK: - Editor

/// Alta y edición de un bloque. Mismo formulario para los dos casos: la única
/// diferencia es que editando aparece "Eliminar".
private struct ClassSlotEditor: View {
    let slot: ClassSlot?
    let onSave: (ClassSlot) -> Void
    let onDelete: (UUID) -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss

    @State private var courseName = ""
    @State private var section = ""
    @State private var room = ""
    @State private var weekday: Weekday = .lunes
    @State private var start = Date()
    @State private var end = Date()

    private var isEditing: Bool { slot != nil }

    private var canSave: Bool {
        !courseName.trimmingCharacters(in: .whitespaces).isEmpty
            && minutes(from: end) > minutes(from: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(Palette.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    TextInput(label: "Nombre de la clase", text: $courseName,
                              placeholder: "Anatomía II", icon: "book.closed")

                    HStack(spacing: Space.sm) {
                        TextInput(label: "Sección o grupo", text: $section,
                                  placeholder: "CBM0103 · Grupo B", icon: "person.3")
                        TextInput(label: "Aula", text: $room,
                                  placeholder: "C-205", icon: "mappin.and.ellipse")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Día").labelCaps()
                        dayPicker
                    }

                    HStack(spacing: Space.md) {
                        timeField("Desde", value: $start)
                        timeField("Hasta", value: $end)
                    }

                    if !canSave && !courseName.isEmpty {
                        Text("La hora de fin tiene que ser posterior a la de inicio.")
                            .font(Type.micro)
                            .foregroundStyle(Palette.warning)
                    }
                }
                .padding(Space.lg)
            }
            .scrollContentBackground(.hidden)

            Divider().overlay(Palette.divider)
            footerBar
        }
        #if os(macOS)
        .frame(width: 460, height: 520)
        #endif
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.5))
        .onAppear(perform: hydrate)
    }

    private var headerBar: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: isEditing ? "pencil" : "calendar.badge.plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(prefs.tint)
            Text(isEditing ? "Editar clase" : "Nueva clase")
                .font(Type.heading)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }

    /// Los siete días como chips. Un `Picker` en menú escondería el dato más
    /// importante del formulario detrás de un click.
    private var dayPicker: some View {
        HStack(spacing: 5) {
            ForEach(Weekday.week) { d in
                let on = d == weekday
                Button {
                    weekday = d
                } label: {
                    Text(d.short)
                        .font(Type.micro)
                        .foregroundStyle(on ? Palette.textOnAccent : Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(on ? prefs.tint : Palette.textPrimary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(Motion.quick, value: weekday)
    }

    private func timeField(_ label: String, value: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).labelCaps()
            DatePicker("", selection: value, displayedComponents: .hourAndMinute)
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
                .labelsHidden()
                .font(Type.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerBar: some View {
        HStack(spacing: Space.xs) {
            if let slot {
                Button("Eliminar", role: .destructive) {
                    onDelete(slot.id)
                    dismiss()
                }
                .nativeGlassButton()
                .controlSize(.small)
            }
            Spacer()
            Button("Cancelar") { dismiss() }
                .nativeGlassButton()
                .controlSize(.small)
            Button(isEditing ? "Guardar" : "Agregar") { save() }
                .nativeGlassButton(prominent: true)
                .tint(prefs.tint)
                .controlSize(.small)
                .disabled(!canSave)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }

    // MARK: Datos

    private func hydrate() {
        if let s = slot {
            courseName = s.courseName
            section = s.section
            room = s.room ?? ""
            weekday = s.weekday
            start = date(fromMinutes: s.startMinutes)
            end = date(fromMinutes: s.endMinutes)
        } else {
            // Un default sensato ahorra dos interacciones en el caso común.
            // Domingo casi nunca hay clase: si hoy es domingo, arrancá en lunes.
            let hoy = Weekday.today
            weekday = hoy == .domingo ? .lunes : hoy
            start = date(fromMinutes: 7 * 60)
            end = date(fromMinutes: 8 * 60 + 30)
        }
    }

    private func save() {
        let clean = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        onSave(ClassSlot(
            id: slot?.id ?? UUID(),
            courseName: clean,
            section: section.trimmingCharacters(in: .whitespacesAndNewlines),
            weekday: weekday,
            room: room.trimmingCharacters(in: .whitespacesAndNewlines),
            startMinutes: minutes(from: start),
            endMinutes: minutes(from: end)
        ))
        dismiss()
    }

    private func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func date(fromMinutes m: Int) -> Date {
        let base = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: m, to: base) ?? base
    }
}
