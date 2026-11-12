import Foundation

/// Interpreta datas e horários em português ("amanhã às 19h", "próxima quinta", "dia 15", "20/11").
/// Nunca inventa: se não encontrar data, retorna `date == nil`.
struct DateParseResult: Equatable {
    var date: Date?
    var hasDate = false
    var hasTime = false
}

struct PTDateParser {
    var now: Date
    var calendar: Calendar

    init(now: Date = Date(), calendar: Calendar = Fmt.calendar) {
        self.now = now
        self.calendar = calendar
    }

    static let weekdays: [String: Int] = [
        "domingo": 1, "segunda": 2, "terca": 3, "quarta": 4, "quinta": 5, "sexta": 6, "sabado": 7,
    ]
    static let months = ["janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho",
                         "agosto", "setembro", "outubro", "novembro", "dezembro"]
    private static var monthPattern: String { months.joined(separator: "|") }

    /// - Parameter preferPast: verbos no passado ("gastei", "treinei") resolvem datas ambíguas para trás.
    func parse(_ text: inout NormalizedText, preferPast: Bool) -> DateParseResult {
        var result = DateParseResult()
        let today = calendar.startOfDay(for: now)
        var day: Date?

        func consume(_ m: TextMatch) { text.blank(m.range) }

        // 1. Relativos
        let relatives: [(String, Int)] = [
            (#"\bdepois de amanha\b"#, 2), (#"\banteontem\b"#, -2), (#"\bamanha\b"#, 1),
            (#"\bhoje\b"#, 0), (#"\bontem\b"#, -1),
        ]
        for (pattern, offset) in relatives {
            if let m = RX.first(pattern, in: text.folded) {
                day = calendar.date(byAdding: .day, value: offset, to: today)
                consume(m)
                break
            }
        }

        // 2. "daqui a 3 dias" / "em 3 dias"
        if day == nil, let m = RX.first(#"\b(?:daqui a|daqui|em)\s+(\d{1,3})\s+dias?\b"#, in: text.folded),
           let n = Int(m.group(1) ?? "") {
            day = calendar.date(byAdding: .day, value: n, to: today)
            consume(m)
        }

        // 3. dd/mm(/aaaa)
        // (o ponto não é aceito como separador para não confundir com "77.5 kg" ou "1.200")
        if day == nil, let m = RX.first(#"\b(\d{1,2})[/\-](\d{1,2})(?:[/\-](\d{2,4}))?\b"#, in: text.folded),
           let d = Int(m.group(1) ?? ""), let mo = Int(m.group(2) ?? "") {
            var year = calendar.component(.year, from: today)
            if let ys = m.group(3), let y = Int(ys) { year = y < 100 ? 2000 + y : y }
            if var date = makeDate(year: year, month: mo, day: d) {
                if m.group(3) == nil {
                    if !preferPast && date < today { date = calendar.date(byAdding: .year, value: 1, to: date) ?? date }
                    if preferPast && date > today { date = calendar.date(byAdding: .year, value: -1, to: date) ?? date }
                }
                day = date
                consume(m)
            }
        }

        // 4. "15 de novembro (de 2026)"
        if day == nil, let m = RX.first(#"\b(?:dia\s+)?(\d{1,2})\s+de\s+(\#(Self.monthPattern))(?:\s+de\s+(\d{4}))?\b"#, in: text.folded),
           let d = Int(m.group(1) ?? ""), let monthName = m.group(2),
           let mi = Self.months.firstIndex(of: monthName) {
            var year = calendar.component(.year, from: today)
            if let ys = m.group(3), let y = Int(ys) { year = y }
            if var date = makeDate(year: year, month: mi + 1, day: d) {
                if m.group(3) == nil, !preferPast, date < today {
                    date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
                }
                day = date
                consume(m)
            }
        }

        // 5. "dia 15"
        if day == nil, let m = RX.first(#"\bdia\s+(\d{1,2})\b"#, in: text.folded), let d = Int(m.group(1) ?? "") {
            let comps = calendar.dateComponents([.year, .month], from: today)
            if var date = makeDate(year: comps.year!, month: comps.month!, day: d) {
                if !preferPast && date < today { date = nextMonthDay(d, after: today) ?? date }
                if preferPast && date > today { date = calendar.date(byAdding: .month, value: -1, to: date) ?? date }
                day = date
                consume(m)
            }
        }

        // 6. Dia da semana ("próxima quinta", "na sexta-feira", "segunda que vem")
        if day == nil, let m = RX.first(#"\b(?:(?:na|no|nesta|neste|nessa|nesse|esta|este|essa|esse)\s+)?(proxim[oa]\s+)?(domingo|segunda|terca|quarta|quinta|sexta|sabado)(?:[\s\-]feira)?(\s+que vem)?\b"#, in: text.folded),
           let name = m.group(2), let wd = Self.weekdays[name] {
            let isNext = m.group(1) != nil || m.group(3) != nil
            let current = calendar.component(.weekday, from: today)
            var diff: Int
            if preferPast && !isNext {
                diff = -((current - wd + 7) % 7)
            } else {
                diff = (wd - current + 7) % 7
                if diff == 0 && isNext { diff = 7 }
            }
            day = calendar.date(byAdding: .day, value: diff, to: today)
            consume(m)
        }

        // 7. "semana que vem" / "próxima semana" / "mês que vem"
        if day == nil, let m = RX.first(#"\b(?:semana que vem|proxima semana)\b"#, in: text.folded) {
            day = calendar.date(byAdding: .day, value: 7, to: today)
            consume(m)
        }
        if day == nil, let m = RX.first(#"\b(?:mes que vem|proximo mes)\b"#, in: text.folded) {
            day = calendar.date(byAdding: .month, value: 1, to: today)
            consume(m)
        }

        // Horário
        var hour: Int?
        var minute = 0
        if let m = RX.first(#"\b(?:as\s+|a\s+partir\s+das\s+)?(\d{1,2}):(\d{2})\b"#, in: text.folded) {
            hour = Int(m.group(1) ?? ""); minute = Int(m.group(2) ?? "") ?? 0
            consume(m)
        } else if let m = RX.first(#"\b(?:as\s+)?(\d{1,2})\s*h(?:oras?)?(?:\s*(\d{2}))?(?![a-z])"#, in: text.folded),
                  !RX.test(#"^\s*(?:de|em)\b"#, String(text.folded.dropFirst(m.range.location + m.range.length))) {
            // evita confundir com duração ("estudei 2h de português")
            hour = Int(m.group(1) ?? ""); minute = Int(m.group(2) ?? "") ?? 0
            consume(m)
        } else if let m = RX.first(#"\b(?:as|a partir das)\s+(\d{1,2})\b(?!\s*(?:reais|real|kg|x|vezes))"#, in: text.folded) {
            hour = Int(m.group(1) ?? "")
            consume(m)
        } else if let m = RX.first(#"\b(?:ao\s+)?meio[\s\-]dia\b"#, in: text.folded) {
            hour = 12
            consume(m)
        } else if let m = RX.first(#"\bmeia[\s\-]noite\b"#, in: text.folded) {
            hour = 0
            consume(m)
        }
        if var h = hour {
            if let m = RX.first(#"\b(?:da|de)\s+(manha|tarde|noite|madrugada)\b"#, in: text.folded) {
                let period = m.group(1) ?? ""
                if (period == "tarde" || period == "noite") && h < 12 { h += 12 }
                if period == "noite" && h == 24 { h = 0 }
                consume(m)
            }
            if (0...23).contains(h) && (0...59).contains(minute) {
                hour = h
            } else {
                hour = nil
            }
        }

        if let h = hour {
            var base = day ?? today
            if day == nil, !preferPast,
               let candidate = calendar.date(bySettingHour: h, minute: minute, second: 0, of: today), candidate < now {
                base = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            }
            result.date = calendar.date(bySettingHour: h, minute: minute, second: 0, of: base)
            result.hasTime = true
            result.hasDate = day != nil
        } else if let day {
            result.date = day
            result.hasDate = true
        }
        return result
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        guard let date = calendar.date(from: c),
              calendar.component(.day, from: date) == day else { return nil } // rejeita 31/02
        return date
    }

    private func nextMonthDay(_ d: Int, after date: Date) -> Date? {
        for offset in 1...3 {
            guard let m = calendar.date(byAdding: .month, value: offset, to: date) else { continue }
            let c = calendar.dateComponents([.year, .month], from: m)
            if let r = makeDate(year: c.year!, month: c.month!, day: d) { return r }
        }
        return nil
    }
}
