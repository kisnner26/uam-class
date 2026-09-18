import SwiftUI
import AppKit
import UserNotifications

/// Fuerza activation policy .regular + configura menu bar widget.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }

        // Notificaciones solo si tenemos bundle identifier (i.e. corremos como .app)
        // `swift run` crea binario suelto sin bundle → UNUserNotificationCenter crashea.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }

        // Menu bar widget
        menuBar = MenuBarController()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // seguimos vivos aunque cierren la ventana (por el menu bar)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows { window.makeKeyAndOrderFront(nil) }
        }
        return true
    }
}

@main
struct UAMClassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var prefs = UserPrefs.shared
    @AppStorage("UAMClass.appearance") private var appearance: String = "auto"

    var body: some Scene {
        WindowGroup("UAM Class") {
            RootView()
                .environmentObject(state)
                .environmentObject(prefs)
                .tint(prefs.tint)
                .frame(minWidth: 1000, minHeight: 680)
                .task { await state.bootstrap() }
                .background(Palette.canvas.ignoresSafeArea())
                .preferredColorScheme(preferredScheme)
                .onReceive(NotificationCenter.default.publisher(for: .init("UAMClass.OpenPalette"))) { _ in
                    state.showCommandPalette = true
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        // Ventanas de cuenta: una por cada cuenta extra abierta en simultáneo.
        //
        // Cada una construye su PROPIO `AppState` (y con él su propio
        // `MoodleClient`, su token y su cache), así que dos cuentas conviven sin
        // pisarse. Compartir el `AppState` de la app haría que la segunda
        // ventana desconectara a la primera.
        WindowGroup(id: AccountWindow.sceneID, for: String.self) { $accountID in
            AccountWindow(accountID: accountID)
                .environmentObject(prefs)
                .tint(prefs.tint)
                .frame(minWidth: 1000, minHeight: 680)
                .background(Palette.canvas.ignoresSafeArea())
                .preferredColorScheme(preferredScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .textEditing) {
                Button("Buscar todo…") {
                    state.showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
            CommandMenu("Herramientas") {
                Button("Sesión de estudio…") {
                    state.showStudyTimer = true
                }.keyboardShortcut("t", modifiers: [.command])
                Button("Archivar semestre…") {
                    state.showArchiver = true
                }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Cambiar plataforma") {
                    state.backToPicker()
                }.keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Re-indexar materiales locales") {
                    Task { await LocalFileSearch.shared.rebuildIndex() }
                }
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

    /// Deep links: uamclass://course/{id}, uamclass://palette, uamclass://timer
    private func handleDeepLink(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows { window.makeKeyAndOrderFront(nil) }

        let host = url.host ?? ""
        switch host {
        case "palette":
            state.showCommandPalette = true
        case "timer":
            state.showStudyTimer = true
        case "course":
            let idStr = url.pathComponents.last ?? ""
            if let id = Int(idStr),
               let c = state.courses.first(where: { $0.id == id }) {
                state.pendingCourseOpen = c
            }
        default:
            break
        }
    }
}

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
                MainWindow(platform: platform)
                    .transition(.opacity)
                    .onAppear {
                        if !onboardingDone {
                            showOnboarding = true
                            onboardingDone = true
                        }
                    }
            }

            if state.showCommandPalette {
                CommandPalette()
                    .transition(.opacity)
                    .zIndex(100)
            }

            // El examen va por encima de todo y tapa la app entera: durante un
            // intento no debe haber forma de tocar otra cosa por accidente.
            if let session = state.activeQuiz {
                QuizAttemptView(session: session, moodle: state.moodle)
                    .id(session.id.description + (session.review ? "-r" : ""))
                    .transition(.opacity.combined(with: .scale(scale: 1.01)))
                    .zIndex(150)
            }

            ToastPresenter()
                .allowsHitTesting(false)
                .zIndex(200)
        }
        .animation(Motion.fade, value: state.phase)
        .animation(Motion.spring, value: state.showCommandPalette)
        .animation(Motion.spring, value: state.activeQuiz)
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environmentObject(prefs)
        }
    }
}

/// Splash. Vive los ~400ms del silent-resume, así que la animación entra
/// completa en medio segundo o no se ve nunca.
struct SplashView: View {
    @EnvironmentObject private var prefs: UserPrefs
    @State private var appear = false
    @State private var sweep = false

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: prefs.tint, intensity: 1.15)

            VStack(spacing: Space.md) {
                BrandMark(size: 64)
                    .scaleEffect(appear ? 1 : 0.86)
                    .opacity(appear ? 1 : 0)

                VStack(spacing: 4) {
                    Text("UAM Class")
                        .displayStyle(22, weight: .semibold)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Conectando con el portal")
                        .font(Type.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 6)

                // Barra indeterminada: un punto de luz que recorre el riel.
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.textPrimary.opacity(0.08))
                    Capsule()
                        .fill(prefs.tint.brandGradient)
                        .frame(width: 48)
                        .offset(x: sweep ? 92 : -48)
                        .shadow(color: prefs.tint.opacity(0.5), radius: 6)
                }
                .frame(width: 140, height: 4)
                .clipShape(Capsule())
                .padding(.top, Space.xs)
                .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(Motion.spring) { appear = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
    }
}
