import SwiftUI
import AppKit

/// Ficha completa de una persona.
///
/// Combina dos fuentes:
///  · Lo que ya sabemos del índice (materias en común y rol en cada una), que
///    siempre está disponible.
///  · `core_user_get_course_user_profiles`, que añade carrera, grupos y —si el
///    sitio lo permite— sus cursos matriculados.
///
/// Los campos ausentes no se dibujan: un perfil medio vacío con seis "—" es
/// peor que uno corto.
struct UserProfileSheet: View {
    let entry: DirectoryIndex.Entry

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss

    @State private var profile: MoodleUserProfile?
    @State private var otherCourses: [MoodleCourse] = []
    @State private var loading = true
    @State private var restricted = false

    private var user: MoodleEnrolledUser { entry.user }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(Palette.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    identityCard
                    if !entry.courses.isEmpty {
                        sharedCoursesCard
                    }
                    if !otherCourses.isEmpty {
                        otherCoursesCard
                    }
                    if let bio = profile?.cleanDescription, !bio.isEmpty {
                        bioCard(bio)
                    }
                    if restricted {
                        restrictedNote
                    }
                }
                .padding(Space.lg)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(width: 620, height: 640)
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.5))
        .task { await load() }
    }

    // MARK: Barra

    private var headerBar: some View {
        HStack(spacing: Space.sm) {
            Avatar(url: profile?.profileimageurl ?? user.profileimageurl
                        ?? user.profileimageurlsmall,
                   name: user.fullname, size: 44, accent: true,
                   userID: user.id)

            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.properName(user.fullname))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let cif = profile?.cif ?? user.cif {
                        Text(cif)
                            .font(Type.mono)
                            .foregroundStyle(Palette.textTertiary)
                            .textSelection(.enabled)
                    }
                    if entry.isTeacherSomewhere {
                        Pill(text: "Docente", tone: .neutral, compact: true)
                    }
                }
            }

            Spacer(minLength: Space.xs)

            if loading { ProgressView().controlSize(.small) }

            if let email = profile?.email ?? user.email, !email.isEmpty,
               let url = URL(string: "mailto:\(email)") {
                GlassIconButton(symbol: "envelope", help: email, size: 28) {
                    NSWorkspace.shared.open(url)
                }
            }
            GlassIconButton(symbol: "bubble.left", help: "Enviar un mensaje", size: 28) {
                Task {
                    do {
                        try await state.moodle.sendInstantMessage(toUserId: user.id, text: "Hola")
                        ToastCenter.shared.show("Mensaje enviado", symbol: "paperplane",
                                                tint: Palette.success)
                    } catch {
                        ToastCenter.shared.show("No se pudo enviar",
                                                symbol: "exclamationmark.triangle",
                                                tint: Palette.danger)
                    }
                }
            }
            GlassIconButton(symbol: "xmark", help: "Cerrar", size: 28) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Space.md)
        .background(.thinMaterial)
    }

    // MARK: Identidad

    private var identityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                BlockHeader(icon: "person.text.rectangle", title: "Datos")

                field("Nombre completo", Fmt.properName(user.fullname))
                if let cif = profile?.cif ?? user.cif { field("CIF", cif, mono: true) }
                if let p = profile?.program ?? user.department { field("Carrera", p) }
                if let inst = profile?.institution, !inst.isEmpty,
                   inst != (profile?.department ?? "") { field("Facultad", inst) }
                if let mail = profile?.email ?? user.email, !mail.isEmpty {
                    field("Correo", mail, selectable: true)
                }
                if let city = profile?.city ?? user.city, !city.isEmpty { field("Ciudad", city) }

                if let groups = profile?.groups?.compactMap(\.name), !groups.isEmpty {
                    field("Grupos", groups.joined(separator: ", "))
                }
                if let last = profile?.lastAccessDate ?? user.lastAccessDate {
                    field("Última conexión",
                          last.formatted(.relative(presentation: .named)))
                }
                if let first = profile?.firstAccessDate {
                    field("Primer ingreso",
                          first.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private func field(_ label: String, _ value: String,
                       mono: Bool = false, selectable: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Text(label)
                .font(Type.caption)
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 122, alignment: .leading)
            // Todo seleccionable: son datos que uno quiere copiar (CIF, correo).
            Text(value)
                .font(mono ? Type.mono : Type.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Materias

    private var sharedCoursesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                BlockHeader(icon: "person.2.badge.gearshape",
                            title: "Materias en común",
                            count: entry.courses.count)

                VStack(spacing: 0) {
                    ForEach(Array(entry.courses.enumerated()), id: \.element.id) { i, shared in
                        courseRow(course: shared.course,
                                  role: shared.role,
                                  isLast: i == entry.courses.count - 1)
                    }
                }
            }
        }
    }

    private var otherCoursesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                BlockHeader(icon: "books.vertical",
                            title: "Otras materias que lleva",
                            count: otherCourses.count)

                VStack(spacing: 0) {
                    ForEach(Array(otherCourses.enumerated()), id: \.element.id) { i, c in
                        courseRow(course: c, role: "", isLast: i == otherCourses.count - 1)
                    }
                }
            }
        }
    }

    private func courseRow(course: MoodleCourse, role: String, isLast: Bool) -> some View {
        let info = CourseInfo(course: course)
        let accent = CourseAccent.color(for: course)

        return VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 26)

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

                Spacer(minLength: Space.xs)

                if !role.isEmpty {
                    Text(role)
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                }
                if let p = AcademicPeriod(course: course) {
                    Text(p.label)
                        .font(Type.micro)
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            .padding(.vertical, 7)

            if !isLast {
                Divider().overlay(Palette.divider)
            }
        }
    }

    private func bioCard(_ bio: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.xs) {
                BlockHeader(icon: "text.quote", title: "Descripción")
                Text(bio)
                    .font(Type.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private var restrictedNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
            Text("Moodle limita qué datos de otras personas podés ver. Lo que falta acá no es un error de la app: el sitio no lo entrega.")
                .font(Type.micro)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    // MARK: Carga

    private func load() async {
        defer { loading = false }

        // El perfil enriquecido se pide en el contexto de un curso compartido.
        // Si no compartimos ninguno (resultado remoto por CIF), se intenta con
        // cualquiera de mis cursos: Moodle igual responde con lo que la
        // política de privacidad permita.
        let contextCourse = entry.courses.first?.course ?? state.visibleCourses.first
        if let course = contextCourse {
            do {
                let profiles = try await state.moodle.courseUserProfiles(userId: user.id,
                                                                         courseId: course.id)
                profile = profiles.first
            } catch {
                restricted = true
            }
        }

        // Sus otros cursos. Suele estar restringido para terceros; si falla, nos
        // quedamos con las materias en común, que ya son datos reales.
        if let all = try? await state.moodle.coursesOf(userId: user.id) {
            let sharedIDs = Set(entry.courses.map(\.course.id))
            otherCourses = all.filter { !sharedIDs.contains($0.id) }
        } else if let refs = profile?.enrolledcourses {
            let sharedIDs = Set(entry.courses.map(\.course.id))
            otherCourses = refs.filter { !sharedIDs.contains($0.id) }.map {
                MoodleCourse(id: $0.id, shortname: $0.shortname ?? "",
                             fullname: $0.fullname ?? "", displayname: $0.fullname,
                             idnumber: nil, visible: 1, category: nil, progress: nil,
                             hidden: nil, startdate: nil, enddate: nil,
                             courseimage: nil, overviewfiles: nil)
            }
        } else {
            restricted = true
        }
    }
}
