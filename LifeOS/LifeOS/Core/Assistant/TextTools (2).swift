import Foundation

/// Resultado de uma busca por expressão regular.
struct TextMatch {
    let range: NSRange
    let groups: [String?]
    let groupRanges: [NSRange]

    func group(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    func groupRange(_ i: Int) -> NSRange? {
        guard i < groupRanges.count, groupRanges[i].location != NSNotFound else { return nil }
        return groupRanges[i]
    }
}

enum RX {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        cache[pattern] = r
        return r
    }

    static func first(_ pattern: String, in text: String) -> TextMatch? {
        guard let re = regex(pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return makeMatch(m, ns)
    }

    static func all(_ pattern: String, in text: String) -> [TextMatch] {
        guard let re = regex(pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { makeMatch($0, ns) }
    }

    static func test(_ pattern: String, _ text: String) -> Bool { first(pattern, in: text) != nil }

    private static func makeMatch(_ m: NSTextCheckingResult, _ ns: NSString) -> TextMatch {
        var groups: [String?] = []
        var ranges: [NSRange] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            ranges.append(r)
            groups.append(r.location == NSNotFound ? nil : ns.substring(with: r))
        }
        return TextMatch(range: m.range, groups: groups, groupRanges: ranges)
    }
}

/// Texto normalizado para interpretação. `folded` (minúsculo, sem acentos) e `original`
/// têm o mesmo comprimento UTF-16, permitindo recuperar trechos com acentuação original.
struct NormalizedText {
    let original: String
    private(set) var folded: String
    /// Original com os mesmos trechos "apagados" que `folded`.
    private(set) var originalMasked: String
    private let aligned: Bool

    init(_ text: String) {
        let pre = text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        original = pre
        originalMasked = pre
        let f = pre.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Fmt.locale).lowercased()
        folded = f
        aligned = (f as NSString).length == (pre as NSString).length
    }

    /// Substitui trechos já interpretados por espaços (preserva posições).
    mutating func blank(_ range: NSRange) {
        let ns = folded as NSString
        guard range.location != NSNotFound, range.location + range.length <= ns.length else { return }
        let spaces = String(repeating: " ", count: range.length)
        folded = ns.replacingCharacters(in: range, with: spaces)
        if aligned {
            originalMasked = (originalMasked as NSString).replacingCharacters(in: range, with: spaces)
        }
    }

    /// Trecho com a grafia original (acentos e maiúsculas), respeitando os trechos apagados.
    func originalText(_ range: NSRange) -> String {
        let src = (aligned ? originalMasked : folded) as NSString
        guard range.location != NSNotFound, range.location + range.length <= src.length else { return "" }
        return src.substring(with: range)
    }
}

enum NumberParsing {
    /// "1.234,56" -> 1234.56 ; "77,5" -> 77.5 ; "1.200" (dinheiro) -> 1200 ; "77.5" -> 77.5
    static func parse(_ s: String, money: Bool) -> Double? {
        var x = s.trimmingCharacters(in: .whitespaces)
        if x.contains(",") {
            x = x.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if money, x.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
            x = x.replacingOccurrences(of: ".", with: "")
        }
        return Double(x)
    }

    static let numberWords: [String: Int] = [
        "um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
        "sete": 7, "oito": 8, "nove": 9, "dez": 10, "onze": 11, "doze": 12, "meia": 6,
    ]
}
