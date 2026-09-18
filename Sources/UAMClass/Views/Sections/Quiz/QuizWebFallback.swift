import SwiftUI
import WebKit

/// Visor web del intento, dentro de la app.
///
/// Existe para los tipos de pregunta que no se pueden responder nativamente sin
/// riesgo (arrastrar y soltar, cloze) y como salida de emergencia si algo del
/// examinador nativo falla. Usa el almacén de datos persistente, así que la
/// sesión de Moodle web se inicia una sola vez y queda para las siguientes.
struct QuizWebFallback: View {
    let url: URL?
    let title: String

    @EnvironmentObject private var prefs: UserPrefs
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconTile(symbol: "safari", tint: prefs.tint, size: 28, filled: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Text("Visor web de Moodle")
                        .font(Type.micro)
                        .foregroundStyle(Palette.textTertiary)
                }
                if loading {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                }
                Spacer()
                if let url {
                    GlassIconButton(symbol: "arrow.up.forward.app",
                                    help: "Abrir en el navegador del sistema", size: 26) {
                        NSWorkspace.shared.open(url)
                    }
                }
                GlassIconButton(symbol: "xmark", help: "Cerrar", size: 26) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Space.sm)
            .background(.thinMaterial)

            Divider().overlay(Palette.divider)

            if let url {
                QuizWebView(url: url, loading: $loading)
            } else {
                EmptyState(icon: "link.badge.plus",
                           title: "Sin dirección",
                           subtitle: "No se pudo construir la URL del intento.")
            }
        }
        .frame(width: 980, height: 720)
        .background(Palette.canvas)
    }
}

private struct QuizWebView: NSViewRepresentable {
    let url: URL
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // Persistente a propósito: si fuera efímero habría que iniciar sesión en
        // Moodle web en cada pregunta que caiga acá.
        cfg.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: cfg)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: QuizWebView
        init(_ parent: QuizWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            parent.loading = false
        }
    }
}
