import SwiftUI
import UniformTypeIdentifiers

/// Editor personal por curso. Se guarda automáticamente en LocalStore.
struct MyNotesTab: View {
    let course: MoodleCourse
    @EnvironmentObject private var prefs: UserPrefs
    @ObservedObject private var store = LocalStore.shared
    @State private var draft: String = ""
    @State private var lastSaved: Date?
    @State private var focused: Bool = false
    @FocusState private var editorFocused: Bool
    @State private var showExporter = false
    @State private var exportURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            editor
            footer
        }
        .onAppear {
            draft = store.note(for: course.id)
            lastSaved = draft.isEmpty ? nil : Date()
        }
        .fileMover(isPresented: $showExporter, file: exportURL) { _ in }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cuaderno").labelCaps()
                Text("Anotaciones personales")
                    .font(Type.title)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            statusChip
            iconAction("doc.on.doc", "Copiar todo") { copyToClipboard() }
            iconAction("square.and.arrow.down", "Exportar como .md") { exportMarkdown() }
        }
    }

    private func iconAction(_ symbol: String, _ tooltip: String,
                            _ action: @escaping () -> Void) -> some View {
        GlassIconButton(symbol: symbol, help: tooltip, size: 27, action: action)
    }

    private func exportMarkdown() {
        let info = CourseInfo(course: course)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(info.code) - notas.md")
        try? draft.data(using: .utf8)?.write(to: tmp)
        exportURL = tmp
        showExporter = true
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            Circle().fill(lastSaved != nil ? Palette.success : Palette.textQuaternary)
                .frame(width: 6, height: 6)
            Text(lastSaved != nil ? "Guardado" : "Vacío")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassChip(interactive: false)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .font(Type.body)
                .foregroundStyle(Palette.textPrimary)
                .padding(18)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .onChange(of: draft) { _, _ in
                    store.setNote(draft, for: course.id)
                    lastSaved = Date()
                }

            if draft.isEmpty && !editorFocused {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Escribí tus anotaciones — se guardan solas.")
                        .font(Type.body)
                        .foregroundStyle(Palette.textSecondary)
                    Text("O empezá con un template")
                        .labelCaps()
                    HStack(spacing: 6) {
                        templateChip("Resumen de clase") { draft = template(.resumen) }
                        templateChip("Preguntas") { draft = template(.preguntas) }
                        templateChip("Fórmulas") { draft = template(.formulas) }
                    }
                }
                .padding(24)
                .allowsHitTesting(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .adaptiveSurface(prefs, cornerRadius: Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(prefs.tint.opacity(editorFocused ? 0.45 : 0),
                              lineWidth: 1.2)
        )
        .animation(Motion.quick, value: editorFocused)
    }

    private func templateChip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(prefs.tint)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(prefs.tint.opacity(0.13)))
                .overlay(Capsule().strokeBorder(prefs.tint.opacity(0.22), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    enum NoteTemplate { case resumen, preguntas, formulas }
    private func template(_ t: NoteTemplate) -> String {
        let date = Date().formatted(date: .abbreviated, time: .omitted)
        switch t {
        case .resumen:
            return """
# Resumen de clase — \(date)

## Tema

## Ideas clave
-
-

## Ejemplos
-

## Dudas para el docente
-
"""
        case .preguntas:
            return """
# Preguntas para el docente — \(date)

- [ ]
- [ ]
- [ ]
"""
        case .formulas:
            return """
# Fórmulas — \(date)

**Definición**
```
```

**Ejemplo**
```
```
"""
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("\(words) palabras", systemImage: "text.word.spacing")
                .font(Type.caption)
                .foregroundStyle(Palette.textTertiary)
            Label("\(draft.count) caracteres", systemImage: "character")
                .font(Type.caption)
                .foregroundStyle(Palette.textTertiary)
            Spacer()
            if let ts = lastSaved {
                Text("Guardado \(ts, style: .relative)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var words: Int {
        draft.split { $0.isWhitespace }.count
    }

    private func copyToClipboard() {
        PlatformBridge.copyToClipboard(draft)
    }
}
