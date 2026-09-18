import SwiftUI
import Combine
import AppKit

/// Timer Pomodoro: elegís materia, cuenta hacia atrás, registra sesión al terminar.
struct StudyTimerSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss
    @StateObject private var timer = StudyTimerController()

    @State private var selectedCourseId: Int?
    @State private var minutes: Int = 25

    private let presets = [15, 25, 45, 60, 90]

    /// Color de la sesión: el de la materia elegida. Hace que el timer se
    /// sienta parte del curso y no un accesorio genérico.
    private var accent: Color {
        guard let id = selectedCourseId ?? timer.courseId,
              let c = state.courses.first(where: { $0.id == id }) else { return prefs.tint }
        return CourseAccent.color(for: c)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.divider)
            content
        }
        .frame(width: 470, height: 500)
        .background(AmbientBackdrop(tint: accent, intensity: 0.9))
        .onDisappear { timer.pause() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "timer", tint: accent, size: 32, filled: true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Sesión de estudio")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(timer.isRunning ? "En curso" : "Pomodoro personalizado")
                    .font(Type.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            GlassIconButton(symbol: "xmark", help: "Cerrar", size: 24) {
                timer.pause()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(Space.md)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if timer.isRunning || timer.isPaused {
            timerRunning
        } else {
            setup
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Materia").labelCaps()
                Menu {
                    ForEach(state.courses) { c in
                        Button(CourseInfo(course: c).name) { selectedCourseId = c.id }
                    }
                } label: {
                    HStack {
                        if let id = selectedCourseId,
                           let c = state.courses.first(where: { $0.id == id }) {
                            Circle().fill(CourseAccent.color(for: c))
                                .frame(width: 7, height: 7)
                            Text(CourseInfo(course: c).name)
                                .font(Type.body)
                                .foregroundStyle(Palette.textPrimary)
                        } else {
                            Text("Elegí una materia")
                                .font(Type.body)
                                .foregroundStyle(Palette.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, Space.sm)
                    .padding(.vertical, 9)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .glassBar(radius: Radius.md)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Duración").labelCaps()
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { m in
                        Button {
                            withAnimation(Motion.spring) { minutes = m }
                        } label: {
                            Text("\(m)m")
                                .font(.system(size: 12, weight: minutes == m ? .bold : .medium))
                                .monospacedDigit()
                                .foregroundStyle(minutes == m ? .white : Palette.textSecondary)
                                .frame(minWidth: 48)
                                .padding(.vertical, 8)
                                .background {
                                    if minutes == m {
                                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                            .fill(accent.brandGradient)
                                            .shadow(color: accent.opacity(0.4), radius: 8, x: 0, y: 3)
                                    } else {
                                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                            .fill(Palette.textPrimary.opacity(0.05))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Anticipo de a qué hora termina: quita la cuenta mental.
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 10))
                Text("Termina a las \(endTimeString)")
                    .font(Type.micro)
            }
            .foregroundStyle(Palette.textTertiary)

            Spacer(minLength: 0)

            PrimaryButton(title: "Empezar", icon: "play.fill",
                          disabled: selectedCourseId == nil) {
                timer.start(minutes: minutes, courseId: selectedCourseId!)
            }
        }
        .padding(Space.lg)
    }

    private var endTimeString: String {
        let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let f = DateFormatter()
        f.timeStyle = .short
        f.locale = Locale(identifier: "es_ES")
        return f.string(from: end)
    }

    private var timerRunning: some View {
        VStack(spacing: Space.lg) {
            if let c = state.courses.first(where: { $0.id == timer.courseId }) {
                let info = CourseInfo(course: c)
                VStack(spacing: 2) {
                    Text(info.code)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(accent)
                    Text(info.name)
                        .font(Type.subtitle)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.center)
                }
            }

            ZStack {
                Circle()
                    .stroke(Palette.textPrimary.opacity(0.08), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(
                        AngularGradient(colors: [accent.mixed(with: .white, amount: 0.3), accent],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(0.5), radius: 10)
                    .animation(.easeInOut(duration: 0.6), value: timer.progress)

                VStack(spacing: 2) {
                    Text(timer.displayTime)
                        .font(.system(size: 50, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .monospacedDigit()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(timer.isPaused ? Palette.warning : Palette.success)
                            .frame(width: 5, height: 5)
                        Text(timer.isPaused ? "En pausa" : "Estudiando")
                            .font(Type.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .frame(width: 210, height: 210)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                SecondaryButton(title: timer.isPaused ? "Reanudar" : "Pausar",
                                icon: timer.isPaused ? "play.fill" : "pause.fill") {
                    if timer.isPaused { timer.resume() } else { timer.pause() }
                }
                PrimaryButton(title: "Terminar", icon: "checkmark") {
                    if let id = timer.courseId, timer.elapsedSeconds > 0 {
                        LocalStore.shared.logSession(courseId: id,
                                                     start: timer.startedAt ?? Date(),
                                                     duration: timer.elapsedSeconds)
                    }
                    timer.reset()
                    dismiss()
                }
            }
        }
        .padding(Space.lg)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Controller

@MainActor
final class StudyTimerController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var totalSeconds: TimeInterval = 0
    @Published private(set) var courseId: Int?
    @Published private(set) var startedAt: Date?
    private var task: Task<Void, Never>?

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1.0 - (remainingSeconds / totalSeconds)
    }

    var elapsedSeconds: TimeInterval {
        max(0, totalSeconds - remainingSeconds)
    }

    var displayTime: String {
        let total = Int(remainingSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    func start(minutes: Int, courseId: Int) {
        self.courseId = courseId
        self.startedAt = Date()
        self.totalSeconds = TimeInterval(minutes * 60)
        self.remainingSeconds = self.totalSeconds
        self.isRunning = true
        self.isPaused = false
        tick()
    }

    func pause() {
        isPaused = true
        task?.cancel()
    }

    func resume() {
        isPaused = false
        tick()
    }

    func reset() {
        task?.cancel()
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        totalSeconds = 0
        courseId = nil
        startedAt = nil
    }

    private func tick() {
        task?.cancel()
        task = Task { [weak self] in
            while let self = self, await MainActor.run(body: { self.isRunning && !self.isPaused && self.remainingSeconds > 0 }) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self.remainingSeconds = max(0, self.remainingSeconds - 1)
                    if self.remainingSeconds == 0 {
                        self.finish()
                    }
                }
            }
        }
    }

    private func finish() {
        guard let cid = courseId else { return }
        LocalStore.shared.logSession(courseId: cid,
                                     start: startedAt ?? Date(),
                                     duration: totalSeconds)
        NSSound.beep()
        ToastCenter.shared.show(
            "¡Sesión completa!",
            symbol: "checkmark.seal.fill",
            tint: Palette.success,
            detail: "\(Int(totalSeconds / 60)) min sumados a tu racha"
        )
    }
}
