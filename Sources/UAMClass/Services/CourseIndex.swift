import Foundation
import PDFKit
import AppKit

// MARK: - Índice de texto de la materia
//
// El problema que resuelve: hasta ahora cada consulta abría los PDFs de cero.
// Leer un PDF es lo más caro y lento que hace Claude — página por página, con
// el texto envuelto en estructura — y se repetía en cada pregunta.
//
// La solución no necesita un modelo. macOS extrae el texto de un PDF con
// PDFKit, gratis y al instante: 28 páginas en milisegundos. Se hace UNA vez por
// materia, queda en `indice/` como texto plano con marcas de página, y a partir
// de ahí las consultas hacen `Grep` sobre texto —instantáneo— y leen solo el
// pedazo que importa.
//
// Es el mismo principio que un grafo de conocimiento: pagar el costo de
// entender el corpus una vez, y que cada consulta posterior sea barata.

@MainActor
enum CourseIndex {

    struct Entry {
        let name: String
        let pages: Int
        let characters: Int
        /// Títulos detectados, para armar la tabla de contenidos.
        let headings: [String]
    }

    struct Summary {
        var entries: [Entry] = []
        var failed: [String] = []
        var totalCharacters: Int { entries.reduce(0) { $0 + $1.characters } }
        var isEmpty: Bool { entries.isEmpty }
    }

    static func folder(for course: MoodleCourse) -> URL {
        StudyWorkspace.folder(for: course).appendingPathComponent("indice", isDirectory: true)
    }

    static func mapFile(for course: MoodleCourse) -> URL {
        StudyWorkspace.folder(for: course).appendingPathComponent("MAPA.md")
    }

    static func exists(for course: MoodleCourse) -> Bool {
        let dir = folder(for: course)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.contains { $0.hasSuffix(".txt") }
    }

    static func hasMap(for course: MoodleCourse) -> Bool {
        FileManager.default.fileExists(atPath: mapFile(for: course).path)
    }

    // MARK: Construcción

    /// Extrae el texto de todo el material. Determinístico y sin red.
    @discardableResult
    static func build(for course: MoodleCourse) throws -> Summary {
        let source = StudyWorkspace.materialsFolder(for: course)
        let target = folder(for: course)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let files = (try? FileManager.default.contentsOfDirectory(
            at: source, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []

        var summary = Summary()

        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let extracted = text(of: file) else {
                summary.failed.append(file.lastPathComponent)
                continue
            }
            let out = target.appendingPathComponent(
                file.deletingPathExtension().lastPathComponent + ".txt")
            try? extracted.body.write(to: out, atomically: true, encoding: .utf8)

            summary.entries.append(Entry(name: file.lastPathComponent,
                                         pages: extracted.pages,
                                         characters: extracted.body.count,
                                         headings: headings(in: extracted.body)))
        }

        try tableOfContents(course: course, summary: summary)
            .write(to: StudyWorkspace.folder(for: course)
                        .appendingPathComponent("INDICE.md"),
                   atomically: true, encoding: .utf8)

        return summary
    }

    // MARK: Extracción

    private static func text(of url: URL) -> (body: String, pages: Int)? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return nil }
            var out = ""
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i)?.string, !page.isEmpty else { continue }
                // La marca de página es lo que permite citar "(archivo.pdf, p. 12)"
                // sin volver a abrir el original.
                out += "\n\n[[p.\(i + 1)]]\n" + page
            }
            return out.isEmpty ? nil : (out, doc.pageCount)

        case "txt", "md", "csv":
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (body, 1)

        case "docx", "doc", "rtf", "odt", "html", "htm", "pptx":
            // `NSAttributedString` abre Word, RTF y HTML sin dependencias.
            guard let attributed = try? NSAttributedString(
                url: url, options: [:], documentAttributes: nil) else { return nil }
            let body = attributed.string
            return body.isEmpty ? nil : (body, 1)

        default:
            return nil
        }
    }

    /// Líneas que parecen títulos. Heurística deliberadamente conservadora: es
    /// para orientar, no para ser exacta.
    private static func headings(in body: String) -> [String] {
        var out: [String] = []
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count >= 8, line.count <= 90 else { continue }
            guard !line.hasPrefix("[[p.") else { continue }
            let letters = line.filter { $0.isLetter }
            guard letters.count >= 6 else { continue }

            let upperRatio = Double(letters.filter { $0.isUppercase }.count)
                           / Double(letters.count)
            let numbered = line.range(of: #"^([IVXLC]+\.|\d+(\.\d+)*\.?)\s"#,
                                      options: .regularExpression) != nil
            if upperRatio > 0.6 || numbered {
                out.append(line)
            }
            if out.count >= 25 { break }
        }
        return out
    }

    // MARK: Tabla de contenidos

    private static func tableOfContents(course: MoodleCourse, summary: Summary) -> String {
        let info = CourseInfo(course: course)
        var out = """
        # Índice de texto — \(info.code) \(info.name)

        Texto plano extraído del material del docente. **Consultá esto y no los
        PDFs**: es el mismo contenido, sin el costo de abrir un PDF.

        Cada archivo lleva marcas `[[p.N]]` con el número de página del original,
        para poder citar sin volver a abrirlo.

        """

        if summary.entries.isEmpty {
            out += "\n_No se pudo extraer texto de ningún archivo._\n"
        }

        for e in summary.entries {
            let txt = (e.name as NSString).deletingPathExtension + ".txt"
            out += "\n## \(e.name)\n\n"
            out += "- Texto en `indice/\(txt)`\n"
            out += "- \(e.pages) página\(e.pages == 1 ? "" : "s") · "
                 + "\(e.characters.formatted()) caracteres\n"
            if !e.headings.isEmpty {
                out += "- Contiene:\n"
                for h in e.headings.prefix(12) {
                    out += "  - \(h)\n"
                }
            }
        }

        if !summary.failed.isEmpty {
            out += "\n## Sin texto extraíble\n\n"
            out += summary.failed.map { "- \($0)" }.joined(separator: "\n")
            out += "\n\nProbablemente sean escaneos sin OCR o formatos que no se pueden leer.\n"
        }
        return out
    }
}
