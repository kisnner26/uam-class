import Foundation
import PDFKit

/// Indexa y busca en materiales descargados a ~/Downloads/UAM Class/.
/// PDFKit extrae texto de PDFs; para otros formatos usamos filename.
@MainActor
final class LocalFileSearch: ObservableObject {
    static let shared = LocalFileSearch()

    @Published var isIndexing = false
    @Published private(set) var index: [FileEntry] = []

    struct FileEntry: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let filename: String
        let course: String   // "SIS0401 - Ingeniería"
        let period: String   // "2026-1"
        let excerpt: String?
    }

    private var rootFolder: URL {
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        return downloads.appendingPathComponent("UAM Class", isDirectory: true)
    }

    /// Escanea filesystem y construye índice. Rápido: solo metadata + primeras N palabras de PDFs.
    func rebuildIndex() async {
        isIndexing = true
        defer { isIndexing = false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootFolder.path) else {
            index = []
            return
        }
        var out: [FileEntry] = []

        // Root/Period/Course/(possible sub)/files
        let periods = (try? fm.contentsOfDirectory(atPath: rootFolder.path)) ?? []
        for period in periods {
            let periodFolder = rootFolder.appendingPathComponent(period)
            let courses = (try? fm.contentsOfDirectory(atPath: periodFolder.path)) ?? []
            for course in courses {
                let courseFolder = periodFolder.appendingPathComponent(course)
                let files = allFiles(in: courseFolder)
                for url in files {
                    let excerpt = await excerptFor(url: url)
                    out.append(FileEntry(
                        url: url,
                        filename: url.lastPathComponent,
                        course: course,
                        period: period,
                        excerpt: excerpt
                    ))
                }
            }
        }
        await MainActor.run { self.index = out }
    }

    /// Búsqueda simple case-insensitive contra nombre + excerpt.
    func search(_ query: String) -> [FileEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return index.filter { entry in
            entry.filename.lowercased().contains(q)
            || (entry.excerpt?.lowercased().contains(q) ?? false)
            || entry.course.lowercased().contains(q)
        }
    }

    // MARK: - Recursive file listing

    private func allFiles(in folder: URL) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        guard let en = fm.enumerator(at: folder,
                                     includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in en {
            if let v = try? url.resourceValues(forKeys: [.isRegularFileKey]),
               v.isRegularFile == true {
                out.append(url)
            }
        }
        return out
    }

    // MARK: - Excerpt

    private func excerptFor(url: URL) async -> String? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return await extractPDFText(url)
        } else if ["txt", "md"].contains(ext) {
            return (try? String(contentsOf: url, encoding: .utf8))?.prefix(400).description
        }
        return nil
    }

    private func extractPDFText(_ url: URL) async -> String? {
        await Task.detached(priority: .background) {
            guard let doc = PDFDocument(url: url) else { return nil as String? }
            var text = ""
            for i in 0..<min(doc.pageCount, 3) {
                if let page = doc.page(at: i), let s = page.string {
                    text.append(s)
                    text.append(" ")
                    if text.count > 800 { break }
                }
            }
            return String(text.prefix(500))
        }.value
    }
}
