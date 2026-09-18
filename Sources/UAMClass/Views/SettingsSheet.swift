import SwiftUI
import UserNotifications

/// Panel de configuración global. Estilo Apple: List con sections y toggles nativos.
struct SettingsSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LocalStore.shared

    @AppStorage("UAMClass.appearance") private var appearance: String = "auto"
    @AppStorage("UAMClass.notifications24h") private var notif24h: Bool = true
    @AppStorage("UAMClass.notifications1h") private var notif1h: Bool = true
    @AppStorage("UAMClass.pomodoroMinutes") private var pomodoroMinutes: Int = 25

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section("Apariencia") {
                    Picker("Tema", selection: $appearance) {
                        Text("Automático").tag("auto")
                        Text("Claro").tag("light")
                        Text("Oscuro").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    Picker("Densidad", selection: $prefs.density) {
                        ForEach(UserPrefs.Density.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Estilo de fondos", selection: $prefs.glass) {
                        ForEach(UserPrefs.Glass.allCases) { g in
                            Text(g.label).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                             count: 9),
                              spacing: 10) {
                        ForEach(Array(UserPrefs.tintPresets.enumerated()), id: \.offset) { idx, preset in
                            TintSwatch(preset: preset,
                                       selected: prefs.tintIndex == idx) {
                                withAnimation(Motion.spring) { prefs.tintIndex = idx }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("Color de acento")
                        Spacer()
                        Text(UserPrefs.tintPresets[min(prefs.tintIndex,
                                                       UserPrefs.tintPresets.count - 1)].name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(prefs.tint)
                    }
                }

                Section {
                    ForEach(Array(prefs.dashboardWidgets.enumerated()), id: \.element.id) { idx, widget in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            Image(systemName: widget.id.symbol)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(widget.id.label)
                                .font(.system(size: 13))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { prefs.dashboardWidgets[idx].visible },
                                set: { prefs.dashboardWidgets[idx].visible = $0 }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                    }
                    .onMove { source, destination in
                        prefs.moveWidget(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    HStack {
                        Text("Widgets del dashboard")
                        Spacer()
                        Text("Arrastrá para reordenar")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Section("Notificaciones") {
                    ClaudeAccountBanner()
                        .padding(.vertical, 2)
                    Toggle("Sonidos de interfaz", isOn: Binding(
                        get: { prefs.sounds },
                        set: { prefs.sounds = $0; if $0 { SoundKit.shared.play(.toggle) } }
                    ))
                    Toggle("Recordar 24h antes de una entrega", isOn: $notif24h)
                    Toggle("Recordar 1h antes de una entrega", isOn: $notif1h)
                    Button("Abrir preferencias del sistema") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                Section("Estudio") {
                    Picker("Duración Pomodoro por defecto", selection: $pomodoroMinutes) {
                        ForEach([15, 20, 25, 30, 45, 60, 90], id: \.self) { m in
                            Text("\(m) minutos").tag(m)
                        }
                    }
                    Text("Racha actual: \(currentStreak) día\(currentStreak == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section("Datos") {
                    Button("Re-indexar archivos locales") {
                        Task { await LocalFileSearch.shared.rebuildIndex() }
                        ToastCenter.shared.show("Re-indexado en curso…", symbol: "sparkles", tint: prefs.tint)
                    }
                    Button("Abrir carpeta de descargas") {
                        openDownloads()
                    }
                    Button("Exportar preferencias…") { exportPrefs() }
                    Button("Importar preferencias…") { importPrefs() }
                    Button(role: .destructive) {
                        clearData()
                    } label: {
                        Text("Borrar preferencias locales")
                    }
                }

                Section("Sobre") {
                    LabeledContent("Versión", value: "1.0")
                    LabeledContent("Instancia Moodle", value: state.moodleInstance.displayName)
                    if let info = state.moodleSiteInfo {
                        LabeledContent("Cuenta", value: Fmt.properName(info.fullname))
                        LabeledContent("CIF", value: info.username)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 580, height: 700)
        .background(AmbientBackdrop(tint: prefs.tint, intensity: 0.5))
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "gearshape.fill", tint: prefs.tint, size: 30, filled: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Configuración")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("Apariencia, notificaciones y datos")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            GlassIconButton(symbol: "xmark", help: "Cerrar", size: 24) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Space.md)
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

    private func openDownloads() {
        let url = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appendingPathComponent("UAM Class", isDirectory: true)
        if let url = url, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func clearData() {
        let alert = NSAlert()
        alert.messageText = "¿Borrar todas las preferencias?"
        alert.informativeText = "Se borrarán favoritos, notas personales, tags, bookmarks e historial de sesiones. Los archivos descargados no se borran."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Borrar")
        alert.addButton(withTitle: "Cancelar")
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.kisnner.uamclass")
        }
    }

    private func exportPrefs() {
        let keys = ["UAMClass.favorites", "UAMClass.notes", "UAMClass.studytime",
                    "UAMClass.sessions", "UAMClass.bookmarks", "UAMClass.tags",
                    "UAMClass.ratings", "UAMClass.recents",
                    "UAMClass.tintIndex", "UAMClass.density", "UAMClass.glass",
                    "UAMClass.dashboardWidgets"]
        var dict: [String: Any] = [:]
        for k in keys {
            if let v = UserDefaults.standard.object(forKey: k) {
                dict[k] = v
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                     options: [.prettyPrinted]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "uamclass-backup-\(Int(Date().timeIntervalSince1970)).json"
        panel.begin { r in
            if r == .OK, let url = panel.url {
                try? data.write(to: url)
                ToastCenter.shared.show("Backup exportado", symbol: "square.and.arrow.down", tint: Palette.success)
            }
        }
    }

    private func importPrefs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { r in
            if r == .OK, let url = panel.url,
               let data = try? Data(contentsOf: url),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in dict {
                    UserDefaults.standard.set(v, forKey: k)
                }
                ToastCenter.shared.show("Backup importado. Reiniciá la app.",
                                        symbol: "arrow.down.doc.fill", tint: Palette.success)
            }
        }
    }
}

// MARK: - Tint swatch

private struct TintSwatch: View {
    let preset: TintPreset
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if selected {
                    Circle()
                        .strokeBorder(preset.color, lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                }

                Circle()
                    .fill(preset.color.brandGradient)
                    .frame(width: 25, height: 25)
                    .overlay(Circle().strokeBorder(Palette.rimOnDark, lineWidth: 0.6))
                    .shadow(color: preset.color.opacity(selected ? 0.5 : 0.2),
                            radius: selected ? 8 : 3, x: 0, y: 2)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 34)
            .scaleEffect(hovered ? 1.1 : 1.0)
            .animation(Motion.quick, value: hovered)
            .animation(Motion.spring, value: selected)
            .help(preset.name)
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
    }
}
