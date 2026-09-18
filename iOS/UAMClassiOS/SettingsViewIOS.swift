import SwiftUI

/// Ajustes para iPhone. La versión de Mac (`SettingsSheet`) tiene paneles de
/// AppKit (NSSavePanel, NSAlert, mostrar-en-Finder) que no tienen sentido acá;
/// esta es una versión chica: cuenta, tinte, apariencia y cerrar sesión.
struct SettingsViewIOS: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var accounts = AccountStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("UAMClass.appearance") private var appearance: String = "auto"

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceSection
                aboutSection
                Section {
                    Button(role: .destructive) {
                        Task { await state.logout(from: .moodle) }
                        dismiss()
                    } label: {
                        Text("Cerrar sesión")
                    }
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Cuenta") {
            ForEach(accounts.ordered) { account in
                Button {
                    guard account.id != accounts.activeID else { return }
                    Task { await state.switchTo(account: account) }
                } label: {
                    HStack(spacing: 12) {
                        AccountAvatar(account: account, fallbackName: account.fullname,
                                      tint: prefs.tint, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.displayName)
                                .foregroundStyle(Palette.textPrimary)
                            Text("\(account.instance.displayName) · \(account.username)")
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        if account.id == accounts.activeID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(prefs.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Button {
                state.addAccount()
            } label: {
                Label("Agregar otra cuenta", systemImage: "person.badge.plus")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Apariencia") {
            Picker("Color de acento", selection: $prefs.tintIndex) {
                ForEach(UserPrefs.tintPresets.indices, id: \.self) { i in
                    HStack {
                        Circle().fill(UserPrefs.tintPresets[i].color).frame(width: 14, height: 14)
                        Text(UserPrefs.tintPresets[i].name)
                    }
                    .tag(i)
                }
            }
            Picker("Tema", selection: $appearance) {
                Text("Automático").tag("auto")
                Text("Claro").tag("light")
                Text("Oscuro").tag("dark")
            }
        }
    }

    private var aboutSection: some View {
        Section("Acerca de") {
            HStack {
                Text("Versión")
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}
