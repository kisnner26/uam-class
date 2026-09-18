import SwiftUI

/// La cara de una cuenta guardada: tu Mii si existe, si no, iniciales sobre
/// un degradé del tinte activo. Compartido entre `AccountSwitcher` (macOS,
/// sidebar) y `SettingsViewIOS` (iPhone, ajustes).
struct AccountAvatar: View {
    let account: SavedAccount?
    var fallbackName: String
    var tint: Color
    var size: CGFloat

    @ObservedObject private var localStore = LocalStore.shared

    private var mii: Mii? { localStore.mii(for: account?.id) }

    var body: some View {
        ZStack {
            if let mii {
                MiiView(mii: mii, size: size)
            } else {
                Circle().fill(tint.brandGradient)
                Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(0.3), radius: size * 0.16, x: 0, y: 1)
    }

    private var initials: String {
        if let a = account, !a.initials.isEmpty { return a.initials }
        return Fmt.initials(fallbackName)
    }
}
