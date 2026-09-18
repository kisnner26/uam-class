import SwiftUI

/// Tarjeta de perfil que abre el selector de cuentas. Reemplaza a la tarjeta
/// estática del sidebar: mismo lugar, ahora clickeable.
struct AccountSwitcher: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = AccountStore.shared

    @State private var open = false
    @State private var showMii = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            profileCard
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            AccountMenu(open: $open, showMii: $showMii)
                .environmentObject(state)
                .environmentObject(prefs)
        }
        .sheet(isPresented: $showMii) {
            MiiEditor(accountID: store.activeID ?? "local",
                      displayName: store.accounts.first { $0.id == store.activeID }?.fullname
                                   ?? state.moodleSiteInfo?.fullname ?? "Tu cuenta")
                .environmentObject(prefs)
        }
    }

    private var profileCard: some View {
        HStack(spacing: 10) {
            AccountAvatar(account: store.active,
                          fallbackName: state.moodleSiteInfo?.fullname ?? "",
                          tint: prefs.tint, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.moodleSiteInfo.map { Fmt.properName($0.fullname) } ?? "Cuenta")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.isOffline ? Palette.warning : Palette.success)
                        .frame(width: 5, height: 5)
                    Text(subtitle)
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.textQuaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassBar(radius: Radius.md)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let name = store.active?.instance.displayName ?? state.moodleInstance.displayName
        if store.accounts.count > 1 {
            return "\(name) · \(store.accounts.count) cuentas"
        }
        return name
    }
}

// MARK: - Menú

private struct AccountMenu: View {
    @Binding var open: Bool
    @Binding var showMii: Bool
    @ObservedObject private var localStore = LocalStore.shared

    private var miiExists: Bool {
        localStore.mii(for: AccountStore.shared.activeID) != nil
    }

    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @ObservedObject private var store = AccountStore.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(Palette.divider)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.ordered) { account in
                        AccountRow(account: account,
                                   active: account.id == store.activeID,
                                   busy: state.switchingAccount && account.id == pendingID,
                                   onSelect: { switchTo(account) },
                                   onOpenWindow: { openInNewWindow(account) },
                                   onRemove: { store.remove(account) })
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 260)

            Divider().overlay(Palette.divider)

            footer
        }
        .frame(width: 300)
        .background(Palette.canvas)
    }

    @State private var pendingID: String?

    private var header: some View {
        HStack(spacing: 6) {
            Text("Cuentas").labelCaps()
            Spacer()
            if state.switchingAccount {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
        }
        .padding(.horizontal, Space.sm)
        .padding(.top, Space.sm)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            MenuAction(symbol: "face.smiling",
                       label: miiExists ? "Editar mi Mii" : "Crear mi Mii",
                       tint: prefs.tint) {
                open = false
                showMii = true
            }
            MenuAction(symbol: "person.badge.plus", label: "Agregar otra cuenta", tint: prefs.tint) {
                open = false
                state.addAccount()
            }
            MenuAction(symbol: "rectangle.portrait.and.arrow.right",
                       label: "Cerrar sesión de esta cuenta") {
                open = false
                Task { await state.logout(from: .moodle) }
            }
        }
        .padding(6)
    }

    /// Abre una cuenta en su propia ventana, para tenerla en simultáneo con la
    /// actual en vez de reemplazarla.
    private func openInNewWindow(_ account: SavedAccount) {
        open = false
        openWindow(id: AccountWindow.sceneID, value: account.id)
    }

    private func switchTo(_ account: SavedAccount) {
        guard account.id != store.activeID else { open = false; return }
        pendingID = account.id
        Task {
            await state.switchTo(account: account)
            open = false
        }
    }
}

private struct AccountRow: View {
    let account: SavedAccount
    let active: Bool
    let busy: Bool
    let onSelect: () -> Void
    let onOpenWindow: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var prefs: UserPrefs
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            AccountAvatar(account: account, fallbackName: account.fullname,
                          tint: prefs.tint, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.displayName)
                    .font(.system(size: 12.5, weight: active ? .semibold : .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(account.instance.displayName) · \(account.username)")
                    .font(Type.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.xs)

            if busy {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else if active {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(prefs.tint)
            } else if hovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textQuaternary)
                }
                .buttonStyle(.plain)
                .help("Olvidar esta cuenta")
            }

            if hovered || active {
                Button(action: onOpenWindow) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Abrir en una ventana nueva (a la vez que la actual)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(active ? prefs.tint.opacity(0.12)
                             : Palette.textPrimary.opacity(hovered ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}

// `AccountAvatar` vive en Components/AccountAvatar.swift — la usa también
// SettingsViewIOS, que no puede depender del resto de este archivo (multi-
// ventana, exclusivo de Mac).

// MARK: - Menu action

private struct MenuAction: View {
    let symbol: String
    let label: String
    var tint: Color = Palette.textSecondary
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.textPrimary.opacity(hovered ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .consoleHover($hovered)
        .animation(Motion.quick, value: hovered)
    }
}
