import SwiftUI

/// Editor de tags libres para categorizar cursos localmente.
struct TagsEditor: View {
    let courseId: Int
    @EnvironmentObject private var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Etiquetas").labelCaps()
                Spacer()
                Text("Personales · locales")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }

            let tags = store.tags(for: courseId)

            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { t in
                    TagChip(label: t, tint: prefs.tint) {
                        withAnimation(Motion.spring) { store.removeTag(t, from: courseId) }
                    }
                }
                inputChip
            }

            if tags.isEmpty && !focused {
                Text("Ej: obligatoria · difícil · con proyecto · final oral")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .padding(Space.md)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
    }

    private var inputChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(focused ? prefs.tint : Palette.textTertiary)
            TextField("Nueva…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 90)
                .focused($focused)
                .onSubmit(commit)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule().fill(Palette.textPrimary.opacity(focused ? 0.06 : 0))
        )
        .overlay(
            Capsule().strokeBorder(focused ? prefs.tint.opacity(0.55) : Palette.border,
                                   lineWidth: focused ? 1 : 0.5)
        )
        .animation(Motion.quick, value: focused)
    }

    private func commit() {
        let s = draft.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        store.addTag(s, to: courseId)
        draft = ""
    }
}

private struct TagChip: View {
    let label: String
    var tint: Color = Palette.accent
    let onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium))
            if hovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(hovered ? tint : Palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(tint.opacity(hovered ? 0.14 : 0.08)))
        .overlay(Capsule().strokeBorder(tint.opacity(hovered ? 0.28 : 0.14), lineWidth: 0.5))
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}
