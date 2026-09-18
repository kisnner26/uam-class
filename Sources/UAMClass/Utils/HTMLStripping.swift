import Foundation

/// Utilidades para limpiar HTML crudo que Moodle a veces devuelve en itemname,
/// gradeformatted, feedback, intro, etc. No usamos WebKit para no cargar un
/// runtime pesado; sanitizamos manualmente con regex + entity table.
enum HTMLClean {

    /// Devuelve texto plano: entities decodificadas + tags removidos.
    static func plain(_ input: String?) -> String {
        guard let s = input, !s.isEmpty else { return "" }
        var out = stripTags(s)
        out = decodeEntities(out)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extrae el atributo `title="..."` del primer tag `<i>` o `<span>` que
    /// contenga una clase de badge (fa-check, fa-times, text-success, text-danger, etc.).
    /// Devuelve algo como "Aprobado" / "Reprobado" si Moodle lo puso.
    static func extractBadge(_ input: String?) -> Badge? {
        guard let s = input, !s.isEmpty else { return nil }
        let lower = s.lowercased()

        let positive = lower.contains("fa-check")
            || lower.contains("text-success")
            || lower.contains("aprobado")
        let negative = lower.contains("fa-times")
            || lower.contains("fa-xmark")
            || lower.contains("text-danger")
            || lower.contains("reprobado")

        // Extraer el atributo title=""
        let title: String? = {
            guard let m = s.range(of: #"title="([^"]*)""#, options: .regularExpression) else { return nil }
            let raw = String(s[m])
            let cleaned = raw.replacingOccurrences(of: "title=\"", with: "")
                             .replacingOccurrences(of: "\"", with: "")
            return cleaned.isEmpty ? nil : cleaned
        }()

        if positive { return Badge(kind: .positive, label: title ?? "Aprobado") }
        if negative { return Badge(kind: .negative, label: title ?? "Reprobado") }
        return nil
    }

    struct Badge: Equatable {
        enum Kind: Equatable { case positive, negative }
        let kind: Kind
        let label: String
    }

    /// Decodifica entidades sin tocar los tags. Lo usa el parser de preguntas,
    /// que necesita el texto de cada opción ya legible pero conserva la
    /// estructura por su cuenta.
    static func decode(_ s: String) -> String {
        decodeEntities(s)
    }

    // MARK: - Internos

    private static func stripTags(_ s: String) -> String {
        // Elimina todo entre < y > (incluyendo atributos que contienen ">" no es común)
        var result = ""
        result.reserveCapacity(s.count)
        var inTag = false
        for ch in s {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { result.append(ch) }
        }
        return result
    }

    /// Decodifica entidades más comunes + numéricas &#123; &#xAB;
    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&hellip;", "…"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&aacute;", "á"), ("&eacute;", "é"), ("&iacute;", "í"),
            ("&oacute;", "ó"), ("&uacute;", "ú"),
            ("&Aacute;", "Á"), ("&Eacute;", "É"), ("&Iacute;", "Í"),
            ("&Oacute;", "Ó"), ("&Uacute;", "Ú"),
            ("&ntilde;", "ñ"), ("&Ntilde;", "Ñ"),
            ("&uuml;", "ü"), ("&Uuml;", "Ü"),
            ("&iquest;", "¿"), ("&iexcl;", "¡"),
        ]
        for (k, v) in named {
            out = out.replacingOccurrences(of: k, with: v)
        }
        out = decodeNumericEntities(out)
        return out
    }

    private static func decodeNumericEntities(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].firstIndex(of: ";"),
               semi != i, s.distance(from: i, to: semi) < 10 {
                let inner = s[s.index(after: i)..<semi]
                if inner.hasPrefix("#") {
                    let numPart = inner.dropFirst()
                    let value: Int? = numPart.hasPrefix("x") || numPart.hasPrefix("X")
                        ? Int(numPart.dropFirst(), radix: 16)
                        : Int(numPart)
                    if let v = value, let scalar = Unicode.Scalar(v) {
                        result.append(Character(scalar))
                        i = s.index(after: semi)
                        continue
                    }
                }
            }
            result.append(s[i])
            i = s.index(after: i)
        }
        return result
    }
}
