import SwiftUI
import AppKit

/// Overlay full-screen minimalista para modo Focus.
/// Mientras está activo, hay un timer visible en la esquina + botón salir.
struct FocusOverlay: View {
    let course: MoodleCourse?
    let remainingSeconds: TimeInterval
    let onExit: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("MODO ENFOQUE")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.6))
                    if let c = course {
                        Text(CourseInfo(course: c).code)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text(display(remainingSeconds))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Button(action: onExit) {
                        Text("Salir del modo enfoque")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                )
                .padding(24)
            }
            Spacer()
        }
    }

    private func display(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
