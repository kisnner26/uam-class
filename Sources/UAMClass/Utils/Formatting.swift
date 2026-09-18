import Foundation

enum Fmt {

    /// "1" en vez de "1.0", pero "1.5" se mantiene. Para puntajes de preguntas.
    static func trimNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    /// Cuenta regresiva mm:ss, o h:mm:ss si pasa la hora.
    static func countdown(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// "KISNNER VARONY" → "Kisnner Varony". Respeta acentos y ñ.
    static func properName(_ s: String) -> String {
        s.lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { part -> String in
                guard let first = part.first else { return "" }
                // Los números romanos van enteros en mayúscula. Sin esto,
                // "SALUD COMUNITARIA II" quedaba como "Salud Comunitaria Ii":
                // el nombre de media carrera salía mal escrito en toda la app.
                if isRomanNumeral(part) { return part.uppercased() }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    /// ¿Es un número romano? Se exige que TODAS las letras sean romanas y que
    /// la palabra sea corta, para no convertir "civil" (que es todo romanas)
    /// en "CIVIL".
    private static func isRomanNumeral<S: StringProtocol>(_ word: S) -> Bool {
        let w = word.uppercased()
        guard w.count <= 4, !w.isEmpty else { return false }
        guard w.allSatisfy({ "IVXLC".contains($0) }) else { return false }
        // "I", "II", "III", "IV", "V"… son los que aparecen en nombres de
        // materia. Se descartan combinaciones que en español son palabras.
        let real: Set<String> = ["I","II","III","IV","V","VI","VII","VIII","IX","X",
                                 "XI","XII","XIII","XIV","XV"]
        return real.contains(w)
    }

    /// Toma la primera palabra (útil para saludo).
    static func firstWord(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? s
    }

    /// Iniciales de un nombre: "Kisnner Varony Obando" -> "KV"
    static func initials(_ s: String, max: Int = 2) -> String {
        let words = s.split(separator: " ", omittingEmptySubsequences: true)
        return words.prefix(max).compactMap { $0.first }.map { String($0) }.joined().uppercased()
    }
}

/// Parseo de datos de una materia Moodle basándose en fullname y shortname.
/// Formatos observados en UAM:
///   fullname:  "SIS0401 - INGENIERIA DE SOFTWARE I - GRUPO 2"
///   shortname: "2026-1-LTEC03-SIS0401-2-95082"
struct CourseInfo {
    let code: String            // "SIS0401"
    let name: String            // "Ingenieria de Software I"
    let group: String?          // "2"
    let year: String?           // "2026"
    let period: String?         // "1"
    let program: String?        // "LTEC03"

    init(course: MoodleCourse) {
        let fullParts = course.fullname
            .components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        self.code = fullParts.first ?? course.shortname

        let nameRaw: String = fullParts.count >= 2 ? fullParts[1] : course.fullname
        self.name = Fmt.properName(nameRaw)

        if let last = fullParts.last, last.uppercased().hasPrefix("GRUPO ") {
            self.group = String(last.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else {
            self.group = nil
        }

        let shortParts = course.shortname.split(separator: "-").map(String.init)
        self.year    = shortParts.indices.contains(0) ? shortParts[0] : nil
        self.period  = shortParts.indices.contains(1) ? shortParts[1] : nil
        self.program = shortParts.indices.contains(2) ? shortParts[2] : nil
    }

    var meta: String {
        var parts: [String] = []
        if let g = group   { parts.append("Grupo \(g)") }
        if let p = period, let y = year { parts.append("\(p)C · \(y)") }
        else if let y = year            { parts.append(y) }
        return parts.joined(separator: "  ·  ")
    }
}
