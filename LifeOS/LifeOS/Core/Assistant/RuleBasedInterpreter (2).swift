import Foundation

/// Interpretador local baseado em regras e expressões regulares (pt-BR).
/// Não usa internet nem APIs. Quando falta informação, pede apenas o campo faltante.
struct RuleBasedInterpreter: IntentInterpreter {

    static let helpText = """
    Ainda não entendi. Tente frases como:
    • "Gastei 35 reais no almoço"
    • "Tenho prova de cálculo na próxima quinta às 19h"
    • "Minha conta de internet vence dia 15 e custa 120 reais"
    • "Meu peso é 77,5 kg"
    • "Hoje treinei peito e tríceps"
    • "Preciso estudar redes amanhã"
    • "Comprei ovos, arroz e frango no mercado"
    """

    // MARK: - Entrada principal

    func interpret(_ raw: String, context: InterpreterContext) -> Interpretation {
        var t = NormalizedText(raw)
        let f = t.folded
        guard f.trimmed.count >= 3 else { return .notUnderstood(Self.helpText) }
        let dp = PTDateParser(now: context.now)

        if let habit = matchHabit(f, context: context) {
            var d = AssistantDraft(kind: .habitCheck, sourceText: raw)
            d.habitName = habit
            d.title = habit
            d.date = dp.parse(&t, preferPast: true).date ?? context.now
            return .draft(d)
        }
        if isBill(f) { return parseBill(&t, dp: dp, raw: raw) }
        if isIncome(f) { return parseIncome(&t, dp: dp, raw: raw) }
        if isGroceries(f) { return parseGroceries(&t, dp: dp, raw: raw) }
        if isBody(f) { return parseBody(&t, dp: dp, raw: raw) }
        if isExpense(f) { return parseExpense(&t, dp: dp, raw: raw, context: context) }
        if isWorkoutDone(f) { return parseWorkout(&t, dp: dp, raw: raw) }
        if RX.test(#"\bestudei\b"#, f) { return parseStudySession(&t, dp: dp, raw: raw, context: context) }
        if let event = parseEvent(&t, dp: dp, raw: raw, context: context) { return event }
        return .notUnderstood(Self.helpText)
    }

    /// Completa um rascunho com a resposta a uma pergunta ("Qual foi o valor?").
    func complete(_ draft: AssistantDraft, missing: MissingField, answer: String, context: InterpreterContext) -> Interpretation {
        var d = draft
        var t = NormalizedText(answer)
        let dp = PTDateParser(now: context.now)
        switch missing {
        case .amount:
            d.amount = extractAmount(&t, allowBare: true)
        case .date:
            let past = [.expense, .income, .body, .workout, .studySession].contains(d.kind)
            let r = dp.parse(&t, preferPast: past)
            if let date = r.date { d.date = date; d.hasTime = r.hasTime }
            else if let n = Int(t.folded.trimmed), (1...31).contains(n) {
                var tt = NormalizedText("dia \(n)")
                let r2 = dp.parse(&tt, preferPast: past)
                d.date = r2.date
            }
        case .items:
            d.items = splitItems(answer)
        case .duration:
            d.minutes = extractDuration(&t) ?? Int(t.folded.trimmed).map { $0 <= 12 ? $0 * 60 : $0 }
        case .weight:
            d.weight = firstNumber(t.folded).flatMap { (20...400).contains($0) ? $0 : nil }
        }
        return validate(d)
    }

    /// Verifica campos obrigatórios. Nunca preenche dados inventados.
    func validate(_ d: AssistantDraft) -> Interpretation {
        switch d.kind {
        case .expense, .income:
            if d.amount == nil || d.amount! <= 0 { return .needsInfo(d, .amount, "Qual foi o valor?") }
        case .bill:
            if d.amount == nil || d.amount! <= 0 { return .needsInfo(d, .amount, "Qual o valor da conta \(d.title.lowercased())?") }
            if d.date == nil { return .needsInfo(d, .date, "Qual o dia do vencimento?") }
        case .event:
            if d.date == nil { return .needsInfo(d, .date, "Para quando? (ex.: amanhã às 19h, dia 20)") }
        case .studySession:
            if d.minutes == nil || d.minutes! <= 0 { return .needsInfo(d, .duration, "Quanto tempo você estudou? (ex.: 1h30, 45 min)") }
        case .body:
            if d.weight == nil && d.measurements.isEmpty { return .needsInfo(d, .weight, "Qual o seu peso, em kg?") }
        case .groceries:
            if d.items.isEmpty { return .needsInfo(d, .items, "Quais itens você comprou? (separe por vírgula)") }
        case .workout, .habitCheck:
            break
        }
        return .draft(d)
    }

    // MARK: - Detecção de intenção

    private func isBill(_ f: String) -> Bool {
        if RX.test(#"\b(gastei|paguei|recebi)\b"#, f) { return false }
        return RX.test(#"\b(vence|vencimento|vencendo|boleto|mensalidade)\b"#, f)
            || RX.test(#"\bconta\s+d[aeo]s?\s+\w+.*\b(custa|e de|valor)\b"#, f)
    }

    private func isIncome(_ f: String) -> Bool {
        RX.test(#"\b(recebi|ganhei|entrou|caiu|recebimento|me pagaram|me pagou)\b"#, f)
    }

    private func isGroceries(_ f: String) -> Bool {
        guard RX.test(#"\bcomprei\b"#, f), !RX.test(#"\bgastei\b"#, f) else { return false }
        if RX.test(#"\b(mercado|supermercado|feira|hortifruti|sacolao|acougue|padaria|atacad\w*|quitanda)\b"#, f) { return true }
        // lista de itens sem valor ("comprei ovos, arroz e batata")
        return f.contains(",") && extractAmountPreview(f) == nil
    }

    private func isBody(_ f: String) -> Bool {
        if RX.test(#"\bpes(?:o|ei|ando|agem)\b"#, f) && firstNumber(f) != nil { return true }
        if RX.test(#"\b(cintura|braco|biceps|peito|torax|coxa|perna|quadril)\b[^\d]{0,20}\d{2,3}(?:[.,]\d)?\s*cm\b"#, f) { return true }
        return RX.test(#"\b(gordura|bf|percentual de gordura)\b[^\d]{0,20}\d{1,2}(?:[.,]\d)?\s*%"#, f)
    }

    private func isExpense(_ f: String) -> Bool {
        if RX.test(#"\b(gastei|paguei|gasto|comprei|custou|torrei|despesa|pago)\b"#, f) { return true }
        // valor explícito em reais sem outro contexto ("35 reais almoço")
        return RX.test(#"r\$\s*\d|\d\s*(reais|real)\b"#, f)
    }

    private func isWorkoutDone(_ f: String) -> Bool {
        RX.test(#"\b(treinei|malhei|corri|pedalei|nadei|fiz (?:o\s+)?treino|fiz (?:uma\s+)?(?:corrida|caminhada|musculacao|academia)|treino (?:de|foi)\s+\w+\s+(?:hoje|ontem)|caminhei)\b"#, f)
            || (RX.test(#"\b(hoje|ontem)\b"#, f) && RX.test(#"\btreino\b"#, f) && !RX.test(#"\b(tenho|vou|preciso|amanha)\b"#, f))
    }

    // MARK: - Finanças

    private func parseExpense(_ t: inout NormalizedText, dp: PTDateParser, raw: String, context: InterpreterContext) -> Interpretation {
        var d = AssistantDraft(kind: .expense, sourceText: raw)
        let f = t.folded

        // Cartão: "no cartão nubank", "no crédito"
        if let m = RX.first(#"\b(?:no|pelo|com o|com|via)\s+(?:cartao|credito)(?:\s+(?:de credito\s+)?(?:do\s+|da\s+)?([a-z0-9]+))?"#, in: f) {
            let hint = m.group(1) ?? ""
            d.cardName = context.cardNames.first { !hint.isEmpty && $0.folded.contains(hint) }
                ?? (context.cardNames.count == 1 ? context.cardNames.first : nil)
            if d.cardName == nil && !context.cardNames.isEmpty { d.cardName = context.cardNames.first }
            t.blank(m.range)
        }
        if let m = RX.first(#"\b(?:em\s+)?(\d{1,2})\s*(?:x|vezes)\b"#, in: t.folded), let n = Int(m.group(1) ?? ""), n > 1 {
            d.installments = min(n, 48)
            t.blank(m.range)
        }
        d.amount = extractAmount(&t, allowBare: false)
        let r = dp.parse(&t, preferPast: true)
        d.date = r.date ?? context.now
        d.hasTime = r.hasTime
        if d.amount == nil { d.amount = extractAmount(&t, allowBare: true) }
        d.financeCategory = CategoryGuesser.expense(f)
        d.title = expenseDescription(t) ?? d.financeCategory.label
        if d.cardName == nil { d.installments = 1 }
        return validate(d)
    }

    private func expenseDescription(_ t: NormalizedText) -> String? {
        if let s = phrase(after: #"\b(?:comprei|paguei|gastei com|paguei o|paguei a)\s+(?:(?:um|uma|uns|umas|o|a|os|as)\s+)?"#, in: t), !s.isEmpty,
           !RX.test(#"^(no|na|em|com|de)\b"#, s.folded) {
            return s
        }
        return phrase(after: #"\b(?:no|na|nos|nas|num|numa|em|com|de|do|da|dos|das|pra|para|pro)\s+"#, in: t)
    }

    private func parseIncome(_ t: inout NormalizedText, dp: PTDateParser, raw: String) -> Interpretation {
        var d = AssistantDraft(kind: .income, sourceText: raw)
        let f = t.folded
        d.amount = extractAmount(&t, allowBare: false)
        let r = dp.parse(&t, preferPast: true)
        d.date = r.date ?? dp.now
        if d.amount == nil { d.amount = extractAmount(&t, allowBare: true) }
        d.financeCategory = CategoryGuesser.income(f)
        let desc = phrase(after: #"\b(?:de|do|da|com|pelo|pela)\s+"#, in: t)
        d.title = desc ?? d.financeCategory.label
        return validate(d)
    }

    private func parseBill(_ t: inout NormalizedText, dp: PTDateParser, raw: String) -> Interpretation {
        var d = AssistantDraft(kind: .bill, sourceText: raw)
        let f = t.folded
        d.amount = extractAmount(&t, allowBare: false)
        let r = dp.parse(&t, preferPast: false)
        d.date = r.date
        if d.amount == nil { d.amount = extractAmount(&t, allowBare: true) }
        let stops = [" vence", " venc", " custa", " que ", " no valor", " de r", " todo", " e ", " com "]
        let name = phrase(after: #"\b(?:conta|boleto|fatura|mensalidade)\s+(?:d[aeo]s?\s+)?"#, in: t, stops: stops)
        d.title = (name ?? "Conta").capitalizedFirst
        d.financeCategory = CategoryGuesser.expense(f)
        if d.financeCategory == .outros && RX.test(#"\bmensalidade\b"#, f) { d.financeCategory = .faculdade }
        d.recurrence = RX.test(#"\b(boleto|unica|so uma vez|parcela unica)\b"#, f) && !RX.test(#"\b(todo mes|mensal)\b"#, f) ? .nenhuma : .mensal
        return validate(d)
    }

    // MARK: - Mercado

    private func parseGroceries(_ t: inout NormalizedText, dp: PTDateParser, raw: String) -> Interpretation {
        var d = AssistantDraft(kind: .groceries, sourceText: raw)
        d.amount = extractAmount(&t, allowBare: false)
        let r = dp.parse(&t, preferPast: true)
        d.date = r.date ?? dp.now
        if d.amount == nil, let m = RX.first(#"\b(?:por|paguei|gastei|total(?: de)?)\s+(\d+(?:[.,]\d+)*)"#, in: t.folded) {
            d.amount = NumberParsing.parse(m.group(1) ?? "", money: true)
            t.blank(m.range)
        }
        if let m = RX.first(#"\bcomprei\s+(.+)$"#, in: t.folded), let range = m.groupRange(1) {
            var text = t.originalText(range)
            let ft = text.folded
            let stopPattern = #"\s+(?:n[oa]s?|em)\s+(?:mercado|supermercado|feira|hortifruti|sacolao|acougue|padaria|atacad\w*|quitanda)\b|\s+(?:por|e gastei|gastei|paguei)\b|[.;!?]"#
            if let s = RX.first(stopPattern, in: ft) {
                text = String(text.prefix(s.range.location))
            }
            d.items = splitItems(text)
        }
        d.title = "Compras de mercado"
        d.financeCategory = .alimentacao
        return validate(d)
    }

    func splitItems(_ text: String) -> [GroceryItem] {
        let parts = text.replacingOccurrences(of: #"\s+e\s+"#, with: ",", options: [.regularExpression, .caseInsensitive])
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
        return parts.compactMap { part in
            var name = part
            var qty = 1.0
            var unit = "un"
            // "uma" antes de "um" (alternância é avaliada da esquerda para a direita); exige espaço após palavras-número.
            let pattern = #"^(\d+(?:[.,]\d+)?|(?:uma|um|duas|dois|tres|três|meia|meio)(?=\s))\s*(?:(kg|g|gr|l|litros?|ml|un|unidades?|duzias?|dúzias?|pacotes?|pct|caixas?|latas?|garrafas?|bandejas?|sacos?)(?![\p{L}]))?\s*(?:de\s+)?(.+)$"#
            if let m = RX.first(pattern, in: part) {
                let q = (m.group(1) ?? "").folded
                if let n = NumberParsing.parse(q, money: false) { qty = n }
                else if q == "meia" || q == "meio" { qty = 0.5 }
                else if let w = NumberParsing.numberWords[q] { qty = Double(w) }
                if let u = m.group(2)?.folded {
                    unit = Self.normalizeUnit(u)
                    if unit == "dz" { qty *= 12; unit = "un" }
                }
                name = m.group(3) ?? part
            }
            name = name.replacingOccurrences(of: #"^(?:o|a|os|as|um|uma|uns|umas)\s+"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmed
            guard name.count >= 2 else { return nil }
            return GroceryItem(name: name.capitalizedFirst, quantity: qty, unit: unit)
        }
    }

    static func normalizeUnit(_ u: String) -> String {
        switch u {
        case "kg": "kg"
        case "g", "gr": "g"
        case "l", "litro", "litros": "L"
        case "ml": "ml"
        case "duzia", "duzias": "dz"
        case "pacote", "pacotes", "pct": "pct"
        case "caixa", "caixas": "cx"
        case "lata", "latas": "lata"
        case "garrafa", "garrafas": "garrafa"
        case "bandeja", "bandejas": "bandeja"
        case "saco", "sacos": "saco"
        default: "un"
        }
    }

    // MARK: - Corpo

    private func parseBody(_ t: inout NormalizedText, dp: PTDateParser, raw: String) -> Interpretation {
        var d = AssistantDraft(kind: .body, sourceText: raw)
        let fields: [(String, String)] = [
            ("waist", "cintura"), ("arm", "braco|biceps"), ("chest", "peito|torax"), ("leg", "coxa|perna"), ("hip", "quadril"),
        ]
        for (key, words) in fields {
            if let m = RX.first(#"\b(?:\#(words))\b[^\d]{0,20}(\d{2,3}(?:[.,]\d)?)\s*(?:cm)?"#, in: t.folded),
               let v = NumberParsing.parse(m.group(1) ?? "", money: false), (10...250).contains(v) {
                d.measurements[key] = v
                t.blank(m.range)
            }
        }
        if let m = RX.first(#"\b(?:gordura|bf|percentual de gordura)\b[^\d]{0,20}(\d{1,2}(?:[.,]\d)?)\s*%?"#, in: t.folded),
           let v = NumberParsing.parse(m.group(1) ?? "", money: false), (2...70).contains(v) {
            d.measurements["bodyFat"] = v
            t.blank(m.range)
        }
        if let m = RX.first(#"(\d{2,3}(?:[.,]\d{1,2})?)\s*(?:kg|quilos?|kilos?)\b"#, in: t.folded)
            ?? RX.first(#"\bpes(?:o|ei|ando|agem)\b[^\d]{0,30}(\d{2,3}(?:[.,]\d{1,2})?)"#, in: t.folded),
           let v = NumberParsing.parse(m.group(1) ?? "", money: false), (20...400).contains(v) {
            d.weight = v
            t.blank(m.range)
        }
        d.date = dp.parse(&t, preferPast: true).date ?? dp.now
        return validate(d)
    }

    // MARK: - Treino

    static let muscleGroups: [(pattern: String, name: String)] = [
        ("peito|peitoral", "Peito"), ("triceps", "Tríceps"), ("biceps", "Bíceps"), ("costas|dorsal", "Costas"),
        ("ombros?|deltoides?", "Ombros"), ("pernas?", "Pernas"), ("gluteos?", "Glúteos"),
        ("abdomen|abdominais?|abs", "Abdômen"), ("posteriores?", "Posterior"), ("quadriceps", "Quadríceps"),
        ("panturrilhas?", "Panturrilha"), ("cardio|aerobico", "Cardio"), ("corri|corrida", "Corrida"),
        ("caminhei|caminhada", "Caminhada"), ("pedalei|bike|bicicleta", "Bike"), ("nadei|natacao", "Natação"),
        ("full ?body|corpo todo|corpo inteiro", "Corpo inteiro"), ("superiores", "Superiores"),
        ("inferiores", "Inferiores"), ("funcional", "Funcional"), ("trapezio", "Trapézio"), ("antebraco", "Antebraço"),
    ]

    private func parseWorkout(_ t: inout NormalizedText, dp: PTDateParser, raw: String) -> Interpretation {
        var d = AssistantDraft(kind: .workout, sourceText: raw)
        d.minutes = extractDuration(&t)
        d.date = dp.parse(&t, preferPast: true).date ?? dp.now
        let f = t.folded
        d.muscleGroups = Self.muscleGroups.filter { RX.test(#"\b(?:\#($0.pattern))\b"#, f) }.map(\.name)
        d.title = d.muscleGroups.isEmpty ? "Treino" : Self.joinNatural(d.muscleGroups)
        return validate(d)
    }

    static func joinNatural(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " e " + items.last!
    }

    // MARK: - Estudos

    private func parseStudySession(_ t: inout NormalizedText, dp: PTDateParser, raw: String, context: InterpreterContext) -> Interpretation {
        var d = AssistantDraft(kind: .studySession, sourceText: raw)
        d.minutes = extractDuration(&t)
        d.date = dp.parse(&t, preferPast: true).date ?? dp.now
        let topic = phrase(after: #"\bestudei\s+(?:(?:um pouco|bastante|muito)\s+)?(?:(?:de|sobre|da|do|o|a)\s+)?"#, in: t)
            ?? phrase(after: #"\b(?:de|sobre)\s+"#, in: t)
        if let topic {
            if let match = Self.bestMatch(topic, in: context.subjectNames + context.contestSubjectNames) {
                d.subjectName = match; d.subjectExists = true
            } else {
                d.subjectName = topic
            }
        }
        d.title = d.subjectName ?? "Estudo"
        return validate(d)
    }

    func extractDuration(_ t: inout NormalizedText) -> Int? {
        if let m = RX.first(#"\b(\d+(?:[.,]\d+)?)\s*(?:h|hs|hrs?|horas?)\s*(?:e\s*)?(\d{1,2})?\s*(?:min|minutos)?\b"#, in: t.folded),
           let h = NumberParsing.parse(m.group(1) ?? "", money: false) {
            let extra = Int(m.group(2) ?? "") ?? 0
            t.blank(m.range)
            return Int((h * 60).rounded()) + extra
        }
        if let m = RX.first(#"\b(\d{1,3})\s*(?:min|mins|minutos?)\b"#, in: t.folded), let n = Int(m.group(1) ?? "") {
            t.blank(m.range)
            return n
        }
        if let m = RX.first(#"\b(?:uma|1)\s+hora\s+e\s+meia\b"#, in: t.folded) { t.blank(m.range); return 90 }
        if let m = RX.first(#"\bmeia\s+hora\b"#, in: t.folded) { t.blank(m.range); return 30 }
        if let m = RX.first(#"\b(uma|duas|tres|quatro|cinco)\s+horas?\b"#, in: t.folded), let n = NumberParsing.numberWords[m.group(1) ?? ""] {
            t.blank(m.range); return n * 60
        }
        return nil
    }

    // MARK: - Agenda

    private func parseEvent(_ t: inout NormalizedText, dp: PTDateParser, raw: String, context: InterpreterContext) -> Interpretation? {
        let f = t.folded
        var d = AssistantDraft(kind: .event, sourceText: raw)
        let wantsTask = RX.test(#"\b(preciso|tenho que|tenho de|vou|devo|quero|lembrar de)\b"#, f)

        if RX.test(#"\b(prova|avaliacao|p1|p2|p3|teste|exame(?! de sangue| medico| de rotina))\b"#, f) && !RX.test(#"\b(medico|sangue|laboratorio)\b"#, f) {
            d.eventCategory = .prova
            d.priority = .alta
        } else if RX.test(#"\b(entrega|entregar|prazo)\b"#, f) {
            d.eventCategory = .entrega
            d.priority = .alta
        } else if RX.test(#"\b(trabalho|seminario|relatorio|tcc|atividade|lista de exercicios)\b"#, f) && !RX.test(#"\b(reuniao|no trabalho)\b"#, f) {
            d.eventCategory = .trabalho
            d.priority = .alta
        } else if RX.test(#"\b(reuniao|call|meet|videochamada)\b"#, f) {
            d.eventCategory = .reuniao
        } else if RX.test(#"\b(consulta|dentista|medico|medica|exame|psicologo|psicologa|terapia|fisioterapia|nutricionista)\b"#, f) {
            d.eventCategory = .consulta
        } else if RX.test(#"\btreino\b"#, f) {
            d.eventCategory = .treino
        } else if wantsTask && RX.test(#"\b(estudar|revisar|revisao|ler|resolver|fazer exercicios|fazer questoes)\b"#, f) {
            d.eventCategory = .estudo
        } else if RX.test(#"\b(aniversario|casamento|formatura)\b"#, f) {
            d.eventCategory = .dataImportante
        } else if RX.test(#"\b(me lembre|lembre-me|lembrete|lembrar|me avise|me avisa)\b"#, f) {
            d.eventCategory = .lembrete
        } else if RX.test(#"\b(tenho|vou ter|marcar|agendar|agende|marque|compromisso|encontro|evento)\b"#, f) {
            d.eventCategory = .compromisso
        } else {
            return nil
        }
        if RX.test(#"\b(urgente|importante|prioridade)\b"#, f) { d.priority = .alta }

        let r = dp.parse(&t, preferPast: false)
        d.date = r.date
        d.hasTime = r.hasTime
        let stops = [" na ", " no ", " para ", " pra ", " ate ", " que ", " as ", " em "]

        switch d.eventCategory {
        case .prova:
            let subj = phrase(after: #"\b(?:prova|avaliacao|exame|teste|p1|p2|p3)\s+(?:de|da|do|sobre)\s+"#, in: t, stops: stops)
            applySubject(subj, to: &d, context: context, createIfMissing: true)
            d.title = subj.map { "Prova de \(d.subjectName ?? $0)" } ?? "Prova"
        case .trabalho:
            let subj = phrase(after: #"\b(?:trabalho|seminario|relatorio|atividade|lista de exercicios)\s+(?:de|da|do|sobre)\s+"#, in: t, stops: stops)
            applySubject(subj, to: &d, context: context, createIfMissing: true)
            d.title = subj.map { "Trabalho de \(d.subjectName ?? $0)" } ?? "Trabalho"
        case .entrega:
            let what = phrase(after: #"\b(?:entrega|entregar)\s+(?:(?:d[aeo]s?|o|a|os|as)\s+)?"#, in: t, stops: stops)
            if let what { applySubject(what, to: &d, context: context, createIfMissing: false) }
            d.title = what.map { "Entrega: \($0)" } ?? "Entrega"
        case .estudo:
            let verb = RX.test(#"\brevis"#, f) ? "Revisar" : "Estudar"
            let what = phrase(after: #"\b(?:estudar|revisar|revisao de|ler|resolver|fazer)\s+(?:(?:a|o|as|os|sobre|de|da|do|um pouco de)\s+)?"#, in: t, stops: stops)
            if let what { applySubject(what, to: &d, context: context, createIfMissing: false) }
            d.title = what.map { "\(verb) \(d.subjectExists ? (d.subjectName ?? $0) : $0)" } ?? verb
        case .lembrete:
            let what = phrase(after: #"\b(?:me lembre|lembre-me|lembrete|lembrar|me avise|me avisa)\s*(?:(?:de|que|para|pra|:)\s+)?"#, in: t, stops: [" as "])
            d.title = what ?? "Lembrete"
        default:
            let cleaned = phrase(after: #"^(?:\s*(?:eu|hoje|amanha))*\s*(?:tenho|vou ter|vou|marcar|agendar|agende|marque)?\s*(?:(?:uma?|o|a)\s+)?"#, in: t, stops: stops)
            d.title = cleaned ?? d.eventCategory.label
        }
        d.title = d.title.trimmed.capitalizedFirst
        return validate(d)
    }

    private func applySubject(_ name: String?, to d: inout AssistantDraft, context: InterpreterContext, createIfMissing: Bool) {
        guard let name, !name.isEmpty else { return }
        if let match = Self.bestMatch(name, in: context.subjectNames) {
            d.subjectName = match
            d.subjectExists = true
        } else if createIfMissing {
            d.subjectName = name.capitalizedFirst
            d.subjectExists = false
        }
    }

    // MARK: - Hábitos

    private func matchHabit(_ f: String, context: InterpreterContext) -> String? {
        guard RX.test(#"\b(fiz|feito|conclui|completei|cumpri|marcar|marque|marca|check|li|meditei|bebi|pratiquei)\b"#, f) else { return nil }
        return context.habitNames
            .filter { $0.count >= 3 && f.contains($0.folded) }
            .max { $0.count < $1.count }
    }

    // MARK: - Utilidades

    /// Extrai valor monetário. `allowBare` aceita número sem "R$"/"reais" (após remover datas).
    func extractAmount(_ t: inout NormalizedText, allowBare: Bool) -> Double? {
        let patterns = [
            #"r\$\s*(\d+(?:[.,]\d+)*)"#,
            #"(\d+(?:[.,]\d+)*)\s*(?:reais|real|conto|contos|pila|pilas|brl)\b"#,
        ]
        for p in patterns {
            if let m = RX.first(p, in: t.folded), let v = NumberParsing.parse(m.group(1) ?? "", money: true) {
                t.blank(m.range)
                return v
            }
        }
        if allowBare, let m = RX.first(#"(?<![\d/:])(\d+(?:[.,]\d+)*)(?![\d/:])(?!\s*(?:x\b|vezes|h\b|hs\b|horas|min|kg|cm|%|anos))"#, in: t.folded),
           let v = NumberParsing.parse(m.group(1) ?? "", money: true) {
            t.blank(m.range)
            return v
        }
        return nil
    }

    private func extractAmountPreview(_ f: String) -> Double? {
        var t = NormalizedText(f)
        return extractAmount(&t, allowBare: false)
    }

    private func firstNumber(_ f: String) -> Double? {
        guard let m = RX.first(#"(\d+(?:[.,]\d+)?)"#, in: f) else { return nil }
        return NumberParsing.parse(m.group(1) ?? "", money: false)
    }

    /// Trecho após um padrão, com grafia original, cortado em palavras de parada.
    func phrase(after pattern: String, in t: NormalizedText,
                stops: [String] = [" no ", " na ", " com ", " pelo ", " pela ", " em ", " para ", " pra ", " e ", " que ", " por "],
                maxWords: Int = 6) -> String? {
        guard let m = RX.first(pattern + #"([^\d,.;!?]+)"#, in: t.folded),
              let range = m.groupRange(m.groups.count - 1) else { return nil }
        var s = t.originalText(range)
        let padded = " " + s.folded + " "
        var cut = s.count
        for stop in stops {
            if let r = padded.range(of: stop) {
                let pos = padded.distance(from: padded.startIndex, to: r.lowerBound)
                cut = min(cut, max(0, pos))
            }
        }
        s = String(s.prefix(cut))
        let words = s.split(whereSeparator: \.isWhitespace).prefix(maxWords)
        let result = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " -:"))
        return result.count >= 2 ? result.capitalizedFirst : nil
    }

    /// Correspondência aproximada entre um nome digitado e nomes existentes.
    static func bestMatch(_ name: String, in candidates: [String]) -> String? {
        let n = name.folded.trimmed
        guard n.count >= 3 else { return nil }
        if let exact = candidates.first(where: { $0.folded.trimmed == n }) { return exact }
        let partial = candidates.filter {
            let c = $0.folded.trimmed
            return c.count >= 3 && (c.contains(n) || n.contains(c))
        }
        return partial.min { abs($0.count - name.count) < abs($1.count - name.count) }
    }
}

/// Sugestão de categoria financeira por palavras-chave.
enum CategoryGuesser {
    private static let expenseRules: [(FinanceCategory, String)] = [
        (.assinaturas, "netflix|spotify|prime video|amazon prime|disney|hbo|max|youtube premium|icloud|assinatura|deezer|globoplay|chatgpt|apple music|apple one|game pass"),
        (.internet, "internet|wi-?fi|banda larga|telefone|plano de celular|recarga|fibra"),
        (.alimentacao, "almoco|almocei|jantar|jantei|lanche|lanchei|cafe|comida|restaurante|mercado|supermercado|ifood|padaria|pizza|hamburguer|acougue|feira|marmita|refeicao|sorvete|acai|lanchonete|delivery|hortifruti|salgado"),
        (.transporte, "uber|99|onibus|metro|gasolina|combustivel|estacionamento|passagem|taxi|pedagio|etanol|posto|mecanico|oficina|brt|trem|bilhete unico"),
        (.moradia, "aluguel|condominio|luz|energia|conta de agua|agua|gas|iptu|reforma|moveis|movel|faxina|diarista"),
        (.faculdade, "faculdade|mensalidade|livro|apostila|curso|xerox|copias|material|matricula|cursinho|concurso|inscricao|universidade"),
        (.saude, "farmacia|remedio|medico|consulta|exame|dentista|plano de saude|academia|suplemento|whey|creatina|terapia|psicologo|hospital"),
        (.lazer, "cinema|bar|show|festa|viagem|jogo|cerveja|balada|passeio|teatro|ingresso|role|praia"),
        (.dividas, "emprestimo|divida|financiamento|acordo|parcela do|juros"),
        (.compras, "roupa|tenis|sapato|loja|shopping|presente|eletronico|celular|fone|amazon|shopee|mercado livre|camisa|calca|perfume"),
    ]

    static func expense(_ folded: String) -> FinanceCategory {
        for (cat, words) in expenseRules where RX.test(#"\b(?:\#(words))\b"#, folded) { return cat }
        return .outros
    }

    static func income(_ folded: String) -> FinanceCategory {
        if RX.test(#"\b(salario|pagamento do mes|holerite|contracheque)\b"#, folded) { return .salario }
        if RX.test(#"\b(freela|freelance|extra|bico|venda|vendi)\b"#, folded) { return .rendaExtra }
        if RX.test(#"\b(servico|aula particular|conserto|projeto)\b"#, folded) { return .servicos }
        return .outrasReceitas
    }
}
