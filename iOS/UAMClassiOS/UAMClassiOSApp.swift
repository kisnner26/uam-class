import SwiftUI
import UserNotifications

@main
struct UAMClassiOSApp: App {
    @StateObject private var state = AppState()
    @StateObject private var prefs = UserPrefs.shared
    @AppStorage("UAMClass.appearance") private var appearance: String = "auto"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(prefs)
                .tint(prefs.tint)
                .background(Palette.canvas.ignoresSafeArea())
                .preferredColorScheme(preferredScheme)
                .task {
                    ScheduleSeed.applyIfNeeded()
                    PhoneConnectivityManager.shared.activate()
                    await state.bootstrap()
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// Deep links: uamclass://course/{id}
    private func handleDeepLink(_ url: URL) {
        guard url.host == "course" else { return }
        let idStr = url.pathComponents.last ?? ""
        if let id = Int(idStr), let c = state.courses.first(where: { $0.id == id }) {
            state.pendingCourseOpen = c
        }
    }
}

/// Igual a `RootView` de macOS pero sin dependencias de AppKit ni ventanas:
/// el mismo árbol de fases (`bootstrapping` → `picking` → `signingIn` → `signedIn`),
/// con `RootTabView` en vez de `MainWindow` como pantalla principal.
struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @AppStorage("UAMClass.onboardingDone") private var onboardingDone: Bool = false
    @State private var showOnboarding: Bool = false

    var body: some View {
        ZStack {
            switch state.phase {
            case .bootstrapping:
                SplashView()
                    .transition(.opacity)
            case .picking:
                PlatformPickerView()
                    .transition(.opacity.combined(with: .scale(scale: 1.01)))
            case .signingIn(let platform):
                LoginView(platform: platform)
                    .transition(.opacity.combined(with: .scale(scale: 1.01)))
            case .signedIn(let platform):
                RootTabView(platform: platform)
                    .transition(.opacity)
                    .onAppear {
                        if !onboardingDone {
                            showOnboarding = true
                            onboardingDone = true
                        }
                    }
            }

            ToastPresenter()
                .allowsHitTesting(false)
                .zIndex(200)
        }
        .animation(Motion.fade, value: state.phase)
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environmentObject(prefs)
        }
    }
}
