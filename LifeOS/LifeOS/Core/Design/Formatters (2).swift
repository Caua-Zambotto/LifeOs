import Foundation

enum Fmt {
    static let locale = Locale(identifier: "pt_BR")

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = locale
        c.timeZone = .current
        c.firstWeekday = 1
        return c
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = "BRL"
        return f
    }()

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.maximumFractionDigits = 2
        // Sem separador de milhar: o texto pode ser reeditado e relido por parseDecimal.
        f.usesGroupingSeparator = false
        return f
    }()

    static func currency(_ v: Double) -> String { currencyFormatter.string(from: NSNumber(value: v)) ?? "R$ 0,00" }

    static func signedCurrency(_ v: Double) -> String { (v >= 0 ? "+ " : "− ") + currency(abs(v)) }

    static func number(_ v: Double, digits: Int = 1) -> String {
        decimalFormatter.maximumFractionDigits = digits
        return decimalFormatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    /// Converte texto digitado ("1.234,56", "35", "77.5") em Double.
    static func parseDecimal(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "R$", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.contains(",") {
            return Double(t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        }
        return Double(t)
    }

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let fDayMonth = formatter("d MMM")
    private static let fFull = formatter("EEEE d MMMM")
    private static let fDateTime = formatter("d MMM HH:mm")
    private static let fTime = formatter("HH:mm")
    private static let fMonthYear = formatter("MMMM yyyy")
    private static let fShort = formatter("dd/MM/yy")
    private static let fWeekdayShort = formatter("EEE")
    private static let fMonthShort = formatter("MMM")

    static func dayMonth(_ d: Date) -> String { fDayMonth.string(from: d) }
    static func fullDate(_ d: Date) -> String { fFull.string(from: d).capitalizedFirst }
    static func dateTime(_ d: Date) -> String { fDateTime.string(from: d) }
    static func time(_ d: Date) -> String { fTime.string(from: d) }
    static func monthYear(_ d: Date) -> String { fMonthYear.string(from: d).capitalizedFirst }
    static func short(_ d: Date) -> String { fShort.string(from: d) }
    static func weekdayShort(_ d: Date) -> String { fWeekdayShort.string(from: d).capitalizedFirst }
    static func monthShort(_ d: Date) -> String { fMonthShort.string(from: d).capitalizedFirst }

    static func relativeDay(_ d: Date, now: Date = Date()) -> String {
        let cal = calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
        switch days {
        case 0: return "hoje"
        case 1: return "amanhã"
        case -1: return "ontem"
        case 2...6: return "em \(days) dias"
        case let x where x < -1: return "há \(-x) dias"
        default: return dayMonth(d)
        }
    }

    static func daysUntil(_ d: Date, now: Date = Date()) -> Int {
        let cal = calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: d)).day ?? 0
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func greeting(for date: Date = Date()) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return "Bom dia"
        case 12..<18: return "Boa tarde"
        default: return "Boa noite"
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Minúsculas e sem acentos: usado em buscas e comparações.
    var folded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Fmt.locale).lowercased()
    }
}

extension Date {
    var startOfDay: Date { Fmt.calendar.startOfDay(for: self) }
    func adding(days: Int) -> Date { Fmt.calendar.date(byAdding: .day, value: days, to: self) ?? self }
    func adding(months: Int) -> Date { Fmt.calendar.date(byAdding: .month, value: months, to: self) ?? self }
    var startOfWeek: Date {
        let cal = Fmt.calendar
        return cal.dateInterval(of: .weekOfYear, for: self)?.start ?? startOfDay
    }
    var startOfMonth: Date {
        let cal = Fmt.calendar
        return cal.date(from: cal.dateComponents([.year, .month], from: self)) ?? startOfDay
    }
    var endOfMonth: Date { startOfMonth.adding(months: 1).addingTimeInterval(-1) }
    func isSameDay(_ other: Date) -> Bool { Fmt.calendar.isDate(self, inSameDayAs: other) }
}

/// Períodos de relatório.
enum ReportPeriod: String, CaseIterable, Identifiable {
    case semana, mes, trimestre, ano
    var id: String { rawValue }
    var label: String {
        switch self { case .semana: "Semana"; case .mes: "Mês"; case .trimestre: "Trimestre"; case .ano: "Ano" }
    }
    func interval(now: Date = Date()) -> DateInterval {
        let end = now
        let start: Date
        switch self {
        case .semana: start = now.startOfWeek
        case .mes: start = now.startOfMonth
        case .trimestre: start = now.startOfMonth.adding(months: -2)
        case .ano: start = now.startOfMonth.adding(months: -11)
        }
        return DateInterval(start: start, end: max(start, end))
    }
}
