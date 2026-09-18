import SwiftUI
import PDFKit
import AVKit
import WebKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Preview inline nativo por tipo de archivo. Streamea desde la URL Moodle
/// con token en query. No requiere descarga previa.
struct InlinePreview: View {
    let file: MoodleContentFile
    let tokenizedURL: URL?

    var body: some View {
        Group {
            if let url = tokenizedURL {
                if file.isPDF {
                    PDFPreview(url: url)
                } else if file.isImage {
                    ImagePreview(url: url)
                } else if file.isVideo {
                    VideoPlayer(player: AVPlayer(url: url))
                } else if isPlainText {
                    TextPreview(url: url)
                } else if isOfficeDoc {
                    OfficeFallback(url: url, filename: file.displayName)
                } else {
                    WebPreview(url: url)
                }
            } else {
                unavailable
            }
        }
        .background(Palette.background)
    }

    private var isPlainText: Bool {
        let mt = file.mimetype ?? ""
        return mt.hasPrefix("text/") && !mt.contains("html")
    }

    private var isOfficeDoc: Bool {
        let ext = (file.filename as NSString?)?.pathExtension.lowercased() ?? ""
        return ["doc", "docx", "xls", "xlsx", "ppt", "pptx"].contains(ext)
    }

    private var unavailable: some View {
        EmptyState(icon: "exclamationmark.circle",
                   title: "Preview no disponible",
                   subtitle: "No se pudo generar la URL de este archivo.")
    }
}

// MARK: - PDF

#if os(macOS)
struct PDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = NSColor.textBackgroundColor
        return v
    }
    func updateNSView(_ nsView: PDFView, context: Context) {
        DispatchQueue.global(qos: .userInitiated).async {
            let doc = PDFDocument(url: url)
            DispatchQueue.main.async { nsView.document = doc }
        }
    }
}
#else
struct PDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .systemBackground
        return v
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        DispatchQueue.global(qos: .userInitiated).async {
            let doc = PDFDocument(url: url)
            DispatchQueue.main.async { uiView.document = doc }
        }
    }
}
#endif

/// Panel de resumen IA local (NLTagger) para PDFs.
struct PDFSummaryPanel: View {
    let url: URL
    @State private var summary: PDFSummarizer.Summary?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                if loading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Analizando…").font(Type.caption).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(20)
                } else if let s = summary {
                    header(s)
                    if !s.keywords.isEmpty { keywords(s) }
                    if !s.firstSentences.isEmpty { sentences(s) }
                    if !s.dates.isEmpty { dates(s) }
                    if !s.urls.isEmpty { urls(s) }
                }
            }
            .padding(16)
        }
        .task {
            summary = await PDFSummarizer.summarize(url: url)
            loading = false
        }
    }

    private func header(_ s: PDFSummarizer.Summary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.accent)
            Text("Resumen · \(s.wordCount) palabras")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func keywords(_ s: PDFSummarizer.Summary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Conceptos clave").labelCaps()
            FlowLayout(spacing: 6) {
                ForEach(s.keywords, id: \.self) { k in
                    Text(k)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.accentSoft))
                }
            }
        }
    }

    private func sentences(_ s: PDFSummarizer.Summary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ideas principales").labelCaps()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(s.firstSentences.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 18, alignment: .leading)
                        Text(s.firstSentences[i])
                            .font(Type.body).foregroundStyle(Palette.textPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func dates(_ s: PDFSummarizer.Summary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fechas mencionadas").labelCaps()
            FlowLayout(spacing: 6) {
                ForEach(s.dates, id: \.self) { d in
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 9))
                        Text(d).font(.system(size: 11))
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Palette.surface))
                    .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                }
            }
        }
    }

    private func urls(_ s: PDFSummarizer.Summary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enlaces").labelCaps()
            VStack(alignment: .leading, spacing: 4) {
                ForEach(s.urls, id: \.self) { u in
                    Link(destination: u) {
                        HStack(spacing: 6) {
                            Image(systemName: "link").font(.system(size: 10))
                            Text(u.absoluteString).font(Type.mono).lineLimit(1)
                        }
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
        }
    }
}

/// FlowLayout simple para chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += sz.width + spacing
            lineHeight = max(lineHeight, sz.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > bounds.minX + width {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineHeight = max(lineHeight, sz.height)
        }
    }
}

// MARK: - Image

struct ImagePreview: View {
    let url: URL
    @State private var image: PlatformImage?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            if let img = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(platformImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if loading {
                ProgressView().controlSize(.regular)
            } else if let err = error {
                Text(err).font(Type.caption).foregroundStyle(Palette.danger).padding()
            }
        }
        .task {
            loading = true
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = PlatformImage(data: data) {
                    self.image = img
                } else {
                    self.error = "No se pudo decodificar la imagen."
                }
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

// MARK: - Text

struct TextPreview: View {
    let url: URL
    @State private var text: String = ""
    @State private var loading = true

    var body: some View {
        ScrollView {
            if loading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Cargando…").font(Type.caption).foregroundStyle(Palette.textSecondary)
                }.padding()
            } else {
                Text(text)
                    .font(Type.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .task {
            loading = true
            defer { loading = false }
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let s = String(data: data, encoding: .utf8) {
                self.text = s
            }
        }
    }
}

// MARK: - Web (fallback para HTML u otros)

#if os(macOS)
struct WebPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")
        return v
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
#else
struct WebPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}
#endif

// MARK: - Office fallback

struct OfficeFallback: View {
    let url: URL
    let filename: String
    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("Preview no disponible para este formato")
                .font(Type.subtitle).foregroundStyle(Palette.textPrimary)
            Text("Los documentos de Office no se pueden renderizar nativamente. Abrilo con la app externa o descárgalo.")
                .font(Type.caption).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
