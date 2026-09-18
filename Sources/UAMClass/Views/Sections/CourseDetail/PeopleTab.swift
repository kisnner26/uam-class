import SwiftUI

struct PeopleTab: View {
    let courseId: Int
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @State private var users: [MoodleEnrolledUser] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""

    var teachers: [MoodleEnrolledUser] {
        users.filter { $0.isTeacher }.sorted { $0.fullname < $1.fullname }
    }
    var students: [MoodleEnrolledUser] {
        users.filter { !$0.isTeacher }
            .sorted { $0.fullname < $1.fullname }
            .filter { search.isEmpty || $0.fullname.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Personas").labelCaps()
                Spacer()
                SearchField(text: $search, placeholder: "Buscar compañero", width: 170)
            }

            if loading && users.isEmpty {
                VStack(spacing: Space.xs) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                }
                .adaptiveSurface(prefs, cornerRadius: Radius.lg)
            } else if let err = error {
                Text(err)
                    .font(Type.caption)
                    .foregroundStyle(Palette.danger)
            } else {
                if !teachers.isEmpty {
                    group(title: "Docentes", icon: "person.crop.rectangle.badge.plus",
                          count: teachers.count) {
                        VStack(spacing: 0) {
                            ForEach(Array(teachers.enumerated()), id: \.element.id) { i, u in
                                UserRow(user: u, accent: true,
                                        tint: prefs.tint,
                                        isLast: i == teachers.count - 1)
                            }
                        }
                    }
                }

                group(title: "Estudiantes", icon: "person.2.fill", count: students.count) {
                    if students.isEmpty {
                        EmptyState(icon: "person.2",
                                   title: search.isEmpty ? "Sin estudiantes" : "Sin coincidencias",
                                   subtitle: search.isEmpty ? nil
                                       : "Nadie coincide con “\(search)”.")
                            .frame(minHeight: 160)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(students.enumerated()), id: \.element.id) { i, u in
                                UserRow(user: u, accent: false,
                                        tint: prefs.tint,
                                        isLast: i == students.count - 1)
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func group<Content: View>(title: String, icon: String, count: Int,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            BlockHeader(icon: icon, title: title, count: count)
            content()
                .adaptiveSurface(prefs, cornerRadius: Radius.lg)
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            users = try await state.moodle.enrolledUsers(courseId: courseId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct UserRow: View {
    let user: MoodleEnrolledUser
    let accent: Bool
    var tint: Color = Palette.accent
    let isLast: Bool

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Avatar(url: user.profileimageurl ?? user.profileimageurlsmall,
                       name: user.fullname, size: 30, accent: accent,
                       userID: user.id)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Fmt.properName(user.fullname))
                        .font(Type.body)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if !user.primaryRole.isEmpty {
                            Text(user.primaryRole)
                                .font(Type.micro)
                                .foregroundStyle(accent ? tint : Palette.textTertiary)
                        }
                        if let email = user.email, !email.isEmpty {
                            if !user.primaryRole.isEmpty {
                                Text("·").font(Type.micro).foregroundStyle(Palette.textQuaternary)
                            }
                            Text(email)
                                .font(Type.micro)
                                .foregroundStyle(Palette.textTertiary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: Space.xs)

                if let email = user.email, !email.isEmpty,
                   let url = URL(string: "mailto:\(email)") {
                    Button {
                        PlatformBridge.openURL(url)
                    } label: {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(hovered ? tint : Palette.textTertiary)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle().fill(tint.opacity(hovered ? 0.12 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Enviar correo a \(email)")
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, 9)
            .background(RowHighlight(hovered: hovered, tint: Palette.accent))
            .consoleHover($hovered)
            .animation(Motion.quick, value: hovered)

            if !isLast {
                Divider().overlay(Palette.divider).padding(.leading, 58)
            }
        }
    }
}
