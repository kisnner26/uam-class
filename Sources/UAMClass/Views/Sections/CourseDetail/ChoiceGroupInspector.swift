import SwiftUI

/// Elegir grupo de trabajo (`mod_choicegroup`).
///
/// La diferencia con una consulta común: las opciones son GRUPOS del curso, y
/// lo que uno realmente quiere saber antes de anotarse no es cuánta gente hay
/// sino **quién**. Por eso el visor cruza las opciones con los participantes de
/// la materia y muestra las caras de cada grupo.
///
/// El plugin es de terceros, así que primero se pregunta si el sitio lo expone:
/// llamar a una función que no existe devuelve un error críptico de Moodle que
/// no le dice nada a nadie.
struct ChoiceGroupInspector: View {
    let module: MoodleModule
    let course: MoodleCourse

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs

    @State private var activity: MoodleChoiceGroup?
    @State private var options: [MoodleChoiceGroupOption] = []
    /// Integrantes por nombre de grupo, sacados de la lista de participantes.
    @State private var members: [String: [MoodleEnrolledUser]] = [:]
    @State private var picked: Int?
    @State private var loading = true
    @State private var busy = false
    @State private var error: String?
    @State private var done = false

    private var supported: Bool { state.moodleSiteInfo?.supportsChoiceGroup ?? false }
    private var mine: MoodleChoiceGroupOption? { options.first { $0.checked == true } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if !supported {
                    unavailable
                } else if loading {
                    Card { SkeletonRow() }
                } else if let a = activity {
                    if !a.cleanIntro.isEmpty {
                        Card {
                            Text(a.cleanIntro)
                                .font(Type.body)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    statusRow(a)
                    groupList(a)
                    if let error { note(error, tone: Palette.danger) }
                    actions(a)
                } else {
                    EmptyState(icon: "person.3.sequence",
                               title: "No se pudo cargar la elección",
                               subtitle: error ?? "Moodle no devolvió datos para esta actividad.")
                }
            }
            .padding(Space.md)
        }
        .task { await load() }
    }

    // MARK: Estados

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            EmptyState(icon: "puzzlepiece.extension",
                       title: "El sitio no expone este plugin",
                       subtitle: "UAM Virtual tiene instalado «Elección de grupo», pero no habilitó sus funciones de web service, así que la app no puede leer las opciones. Se abre en Moodle con tu sesión ya iniciada.")
            PrimaryButton(title: "Abrir en Moodle", loading: false, disabled: false) {
                MoodleOpener.shared.open(path: "mod/choicegroup/view.php?id=\(module.id)",
                                         state: state)
            }
        }
    }

    private func statusRow(_ a: MoodleChoiceGroup) -> some View {
        HStack(spacing: 8) {
            if let mine {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.success)
                Text("Estás en **\(mine.groupName)**")
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.warning)
                Text("Todavía no elegiste grupo")
                    .font(Type.body)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer(minLength: 0)
            if let close = a.closesAt {
                Pill(text: "cierra \(close.formatted(.dateTime.day().month().hour().minute()))",
                     icon: "clock", tone: a.isOpen ? .neutral : .danger, compact: true)
            }
        }
        .padding(Space.sm)
        .adaptiveSurface(prefs, cornerRadius: Radius.md)
    }

    // MARK: Grupos

    private func groupList(_ a: MoodleChoiceGroup) -> some View {
        VStack(spacing: Space.xs) {
            ForEach(options) { opt in
                groupCard(opt, activity: a)
            }
        }
    }

    private func groupCard(_ opt: MoodleChoiceGroupOption,
                           activity a: MoodleChoiceGroup) -> some View {
        let selected = picked == opt.id || (picked == nil && opt.checked == true)
        let people = members[opt.groupName] ?? []
        let blocked = opt.isFull && opt.checked != true

        return Button {
            guard a.isOpen, !blocked else { return }
            SoundKit.shared.play(.select)
            picked = opt.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: Space.sm) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? prefs.tint : Palette.textQuaternary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(opt.groupName)
                            .font(Type.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                        Text(opt.occupancy)
                            .font(Type.micro)
                            .foregroundStyle(opt.isFull ? Palette.warning
                                                        : Palette.textQuaternary)
                    }
                    Spacer(minLength: 0)
                    if opt.checked == true {
                        Pill(text: "Tu grupo", tone: .accent, compact: true)
                    } else if opt.isFull {
                        Pill(text: "Lleno", tone: .warning, compact: true)
                    }
                }

                // Las caras: lo que de verdad decide con quién te juntás.
                if !people.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(people.prefix(8)) { person in
                            Avatar(url: person.profileimageurl,
                                   name: person.fullname, size: 26,
                                   userID: person.id)
                        }
                        if people.count > 8 {
                            Text("+\(people.count - 8)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.leading, 10)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(people.prefix(4).map { Fmt.properName(Fmt.firstWord($0.fullname)) }
                            .joined(separator: ", ")
                         + (people.count > 4 ? " y \(people.count - 4) más" : ""))
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                        .lineLimit(1)
                }
            }
            .padding(Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveSurface(prefs, cornerRadius: Radius.md)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(selected ? prefs.tint.opacity(0.7) : .clear, lineWidth: 1.6))
            .opacity(blocked ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(blocked || !a.isOpen)
    }

    // MARK: Acciones

    private func actions(_ a: MoodleChoiceGroup) -> some View {
        HStack(spacing: Space.xs) {
            if done {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                    Text("Inscripción guardada")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else if !a.isOpen {
                Text("La elección está cerrada.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }

            if mine != nil && a.allowupdate == true {
                Button("Salir del grupo") { Task { await leave(a) } }
                    .nativeGlassButton()
                    .controlSize(.small)
                    .disabled(busy)
            }
            Button(mine == nil ? "Anotarme" : "Cambiar de grupo") {
                Task { await join(a) }
            }
            .nativeGlassButton(prominent: true)
            .tint(prefs.tint)
            .controlSize(.small)
            .disabled(busy || picked == nil || !a.isOpen
                      || (mine != nil && a.allowupdate != true))
        }
    }

    private func note(_ text: String, tone: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(tone)
            Text(text).font(Type.caption).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(tone.opacity(0.10)))
    }

    // MARK: Datos

    private func load() async {
        guard supported else { loading = false; return }
        loading = true
        defer { loading = false }
        do {
            let all = try await state.moodle.choiceGroups(courseIds: [course.id])
            activity = all.choicegroups.first { $0.id == module.instance }
                    ?? all.choicegroups.first { $0.coursemodule == module.id }
            if let a = activity {
                options = try await state.moodle.choiceGroupOptions(id: a.id)
                picked = options.first { $0.checked == true }?.id
            }
            error = nil
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
        await loadMembers()
    }

    /// Quién está en cada grupo. Sale de la lista de participantes, que ya trae
    /// la pertenencia a grupos — no hace falta otra llamada específica.
    private func loadMembers() async {
        guard let people = try? await state.moodle.enrolledUsers(courseId: course.id)
        else { return }
        var byGroup: [String: [MoodleEnrolledUser]] = [:]
        for person in people {
            for group in person.groups ?? [] {
                guard let name = group.name, !name.isEmpty else { continue }
                byGroup[name, default: []].append(person)
            }
        }
        members = byGroup
    }

    private func join(_ a: MoodleChoiceGroup) async {
        guard let opt = picked else { return }
        busy = true; defer { busy = false }
        do {
            try await state.moodle.submitChoiceGroup(id: a.id, optionId: opt)
            done = true
            SoundKit.shared.play(.confirm)
            options = (try? await state.moodle.choiceGroupOptions(id: a.id)) ?? options
            await loadMembers()
            error = nil
        } catch {
            self.error = (error as? MoodleClient.APIError)?.message
                ?? error.localizedDescription
        }
    }

    private func leave(_ a: MoodleChoiceGroup) async {
        busy = true; defer { busy = false }
        try? await state.moodle.deleteChoiceGroupResponse(id: a.id)
        options = (try? await state.moodle.choiceGroupOptions(id: a.id)) ?? options
        picked = nil
        done = false
        await loadMembers()
    }
}
