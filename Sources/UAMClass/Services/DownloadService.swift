import Foundation
#if os(macOS)
import AppKit
import Quartz
#endif

/// Descarga archivos de Moodle, los guarda en ~/Downloads/UAM Class/{curso}/
/// y ofrece integración con Quick Look + Finder.
@MainActor
final class DownloadService: ObservableObject {

    static let shared = DownloadService()

    private let moodle: MoodleClient
    init(moodle: MoodleClient = MoodleClient()) { self.moodle = moodle }

    /// Estado por archivo (key = fileurl)
    @Published private(set) var progress: [String: DownloadState] = [:]

    enum DownloadState: Equatable {
        case idle
        case downloading(Double)  // 0.0 ... 1.0 (indeterminado si NaN)
        case done(URL)
        case failed(String)
    }

    /// Cambia el token que usa el downloader (llamar cuando cambia sesión).
    func setToken(_ token: String?) async {
        await moodle.setToken(token)
    }

    /// Root: ~/Downloads/UAM Class en Mac; Documents/UAM Class en iPhone (no
    /// hay carpeta de Descargas visible en el sandbox de la app).
    private var rootFolder: URL {
        #if os(macOS)
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        #else
        let downloads = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
        return downloads.appendingPathComponent("UAM Class", isDirectory: true)
    }

    func folder(for course: MoodleCourse) -> URL {
        let info = CourseInfo(course: course)
        let name = "\(info.code) - \(info.name)"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = rootFolder.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Devuelve la URL local si el archivo ya está descargado.
    func existingLocal(for file: MoodleContentFile, in course: MoodleCourse) -> URL? {
        guard let name = file.filename else { return nil }
        let dest = folder(for: course).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
    }

    /// Descarga un archivo Moodle. Si ya existe, devuelve el existente.
    func download(_ file: MoodleContentFile, for course: MoodleCourse) async {
        guard let url = file.fileurl, let name = file.filename else {
            progress[file.id] = .failed("Archivo sin URL o nombre.")
            ToastCenter.shared.show("No pude descargar (URL faltante)", symbol: "exclamationmark.triangle.fill", tint: Palette.danger)
            return
        }
        let dest = folder(for: course).appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: dest.path) {
            progress[file.id] = .done(dest)
            return
        }

        progress[file.id] = .downloading(.nan)
        do {
            let tmp = try await moodle.downloadFile(fileurl: url)
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tmp, to: dest)
            progress[file.id] = .done(dest)
            ToastCenter.shared.show("Descargado: \(name)", symbol: "arrow.down.circle.fill", tint: Palette.success)
        } catch {
            progress[file.id] = .failed(error.localizedDescription)
            ToastCenter.shared.show("Falló la descarga", symbol: "exclamationmark.triangle.fill", tint: Palette.danger)
        }
    }

    // MARK: Acciones sobre el archivo local (solo macOS — en iPhone el archivo
    // descargado se previsualiza inline con `InlinePreview`, que ya funciona
    // en ambas plataformas).

    #if os(macOS)
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openWithDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Abre Quick Look (barra espaciadora estilo Finder).
    func quickLook(_ url: URL) {
        QuickLookPresenter.shared.show(url: url)
    }
    #endif
}

#if os(macOS)
// MARK: - Quick Look (single-item)

/// Presenta Quick Look nativo sobre la ventana principal.
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPresenter()

    private var currentURL: URL?

    func show(url: URL) {
        self.currentURL = url as NSURL as URL
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
            if panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { currentURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        currentURL as NSURL?
    }
}
#endif
