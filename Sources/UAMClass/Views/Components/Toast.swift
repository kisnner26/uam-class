import SwiftUI
import Combine

/// Toast notifications globales. Bus vía `ToastCenter.shared.show(_:)`.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var current: Toast?
    private var task: Task<Void, Never>?

    func show(_ message: String,
              symbol: String = "checkmark.circle.fill",
              tint: Color = .green,
              detail: String? = nil) {
        task?.cancel()
        withAnimation(Motion.pop) {
            current = Toast(message: message, symbol: symbol, tint: tint, detail: detail)
        }
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.spring) { current = nil }
        }
    }

    func dismiss() {
        task?.cancel()
        withAnimation(Motion.spring) { current = nil }
    }

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let symbol: String
        let tint: Color
        var detail: String? = nil
    }
}

/// Cápsula de vidrio que baja desde el borde inferior. Es navegación flotante,
/// así que acá el Liquid Glass sí corresponde.
struct ToastPresenter: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        VStack {
            Spacer()
            if let t = center.current {
                HStack(spacing: 10) {
                    Image(systemName: t.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(t.tint)
                        .symbolRenderingMode(.hierarchical)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.message)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(2)
                        if let detail = t.detail {
                            Text(detail)
                                .font(Type.micro)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, Space.md)
                .padding(.vertical, 10)
                .glassPanel(radius: 24, tint: t.tint.opacity(0.10), elevation: .floating)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(t.tint)
                        .frame(width: 3)
                        .padding(.vertical, 9)
                        .padding(.leading, 4)
                }
                .transition(
                    .move(edge: .bottom)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.94, anchor: .bottom))
                )
                .padding(.bottom, 28)
            }
        }
        .animation(Motion.pop, value: center.current?.id)
    }
}
