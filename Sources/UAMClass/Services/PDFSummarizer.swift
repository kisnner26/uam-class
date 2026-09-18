import Foundation
import PDFKit
import NaturalLanguage

/// Extrae texto de un PDF y arma un resumen minimalista usando NL nativo:
/// - Top keywords por frecuencia lemática (sin stop-words)
/// - Primeras oraciones con más señal
/// - Fechas y URLs detectadas
enum PDFSummarizer {

    struct Summary {
        let firstSentences: [String]
        let keywords: [String]
        let dates: [String]
        let urls: [URL]
        let wordCount: Int
    }

    private static let stopWords: Set<String> = [
        "de","la","el","los","las","que","y","en","a","o","u","un","una","del",
        "por","para","con","como","es","se","al","lo","su","sus","le","les","este",
        "esta","estos","estas","the","of","to","in","and","for","on","with","is","it",
        "as","this","that","are","be","or","from","by","an","at","not","which","have",
        "has","was","were","also","if","then","so","but","can","will","one","two"
    ]

    static func summarize(url: URL) async -> Summary? {
        await Task.detached(priority: .userInitiated) {
            guard let doc = PDFDocument(url: url) else { return nil as Summary? }
            var raw = ""
            for i in 0..<doc.pageCount {
                if let p = doc.page(at: i), let s = p.string {
                    raw.append(s)
                    raw.append("\n")
                    if raw.count > 40_000 { break }
                }
            }
            return summarize(text: raw)
        }.value
    }

    static func summarize(text: String) -> Summary {
        // Sentence tokenization
        let sentTokenizer = NLTokenizer(unit: .sentence)
        sentTokenizer.string = text
        var sentences: [String] = []
        sentTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if s.count > 40 && s.count < 500 {
                sentences.append(s)
            }
            return sentences.count < 12
        }

        // Word tokenization + lemmatization → keywords
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        var freq: [String: Int] = [:]
        let opts: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word, scheme: .lemma, options: opts) { tag, range in
            let word = (tag?.rawValue ?? String(text[range])).lowercased()
            if word.count >= 4, !stopWords.contains(word), Int(word) == nil {
                freq[word, default: 0] += 1
            }
            return true
        }
        let keywords = freq
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map(\.key)

        // Dates + URLs con NSDataDetector
        var dates: [String] = []
        var urls: [URL] = []
        if let detector = try? NSDataDetector(types:
                NSTextCheckingResult.CheckingType.date.rawValue |
                NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            detector.enumerateMatches(in: text, options: [], range: range) { m, _, _ in
                guard let m = m else { return }
                if let date = m.date {
                    let df = DateFormatter()
                    df.locale = Locale(identifier: "es_ES")
                    df.dateStyle = .medium
                    dates.append(df.string(from: date))
                } else if let url = m.url {
                    urls.append(url)
                }
            }
        }

        let wordCount = text.split { $0.isWhitespace }.count

        return Summary(
            firstSentences: Array(sentences.prefix(5)),
            keywords: keywords,
            dates: Array(Set(dates)).sorted().prefix(6).map { $0 },
            urls: Array(Set(urls)).prefix(6).map { $0 },
            wordCount: wordCount
        )
    }
}
