import SwiftUI

/// Todos los módulos marcados, de todos los cursos, en un solo lugar.
struct BookmarksView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared
    @State private var modulesByCourse: [Int: [MoodleModule]] = [:]
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header

                if loading && modulesByCourse.isEmpty {
                    Card {
                        VStack(spacing: Space.sm) {
                            ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
                        }
                    }
                } else if allBookmarks.isEmpty {
                    Card {
                        EmptyState(icon: "bookmark",
                                   title: "Sin marcadores",
                                   subtitle: "Tocá el ícono de marcador en cualquier módulo dentro de una materia y aparecerá acá.")
                    }
                } else {
                    VStack(spacing: Space.md) {
                        ForEach(coursesWithBookmarks, id: \.id) { c in
                            courseSection(c)
                        }
                    }
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollContentBackground(.hidden)
        .task { await loadAll() }
    }

    private var header: some View {
        let n = coursesWithBookmarks.count
        return SectionHeader(
            title: "Marcadores",
            eyebrow: "Guardados",
            subtitle: "\(allBookmarks.count) módulos en \(n) materia\(n == 1 ? "" : "s")"
        )
    }

    private var allBookmarks: [MoodleModule] {
        modulesByCourse.values.flatMap { $0 }.filter { store.isBookmarked($0.id) }
    }

    private var coursesWithBookmarks: [MoodleCourse] {
        state.visibleCourses.filter { hasBookmarks(in: $0) }
    }

    private func hasBookmarks(in c: MoodleCourse) -> Bool {
        (modulesByCourse[c.id] ?? []).contains { store.isBookmarked($0.id) }
    }

    private func courseSection(_ c: MoodleCourse) -> some View {
        let info = CourseInfo(course: c)
        let accent = CourseAccent.color(for: c)
        let mods = (modulesByCourse[c.id] ?? []).filter { store.isBookmarked($0.id) }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.code)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                    Text(info.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                NavigationLink(value: c) {
                    HStack(spacing: 3) {
                        Text("Abrir materia")
                            .font(.system(size: 10.5, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, prefs.padLarge)
            .padding(.vertical, Space.sm)

            Divider().overlay(Palette.divider)

            VStack(spacing: 0) {
                ForEach(Array(mods.enumerated()), id: \.element.id) { i, m in
                    BookmarkRow(module: m, accent: accent) {
                        withAnimation(Motion.spring) { store.toggleBookmark(m.id) }
                    }
                    if i < mods.count - 1 {
                        Divider().overlay(Palette.divider).padding(.leading, prefs.padLarge)
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    private func loadAll() async {
        guard modulesByCourse.isEmpty else { return }
        loading = true; defer { loading = false }
        for c in state.visibleCourses {
            if let sections = try? await state.moodle.courseContents(courseId: c.id) {
                let mods = sections.flatMap { $0.modules }
                await MainActor.run { modulesByCourse[c.id] = mods }
            }
        }
    }
}

private struct BookmarkRow: View {
    let module: MoodleModule
    let accent: Color
    let onRemove: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(accent)
                .frame(width: 16)

            Text(module.displayName)
                .font(Type.body)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Space.sm)

            if hovered {
                Button(action: onRemove) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Quitar marcador")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, prefs.padLarge)
        .padding(.vertical, 9)
        .background(RowHighlight(hovered: hovered, tint: Palette.accent))
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}
