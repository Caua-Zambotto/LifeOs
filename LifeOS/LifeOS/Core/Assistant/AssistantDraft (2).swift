import Foundation

enum DraftKind: String, Codable {
    case expense, income, bill, event, studySession, body, workout, groceries, habitCheck

    var label: String {
        switch self {
        case .expense: "Despesa"
        case .income: "Receita"
        case .bill: "Conta a pagar"
        case .event: "Agenda"
        case .studySession: "Sessão de estudo"
        case .body: "Medidas corporais"
        case .workout: "Treino"
        case .groceries: "Compras de mercado"
        case .habitCheck: "Hábito"
        }
    }

    var icon: String {
        switch self {
        case .expense: "arrow.up.right.circle.fill"
        case .income: "arrow.down.left.circle.fill"
        case .bill: "calendar.badge.exclamationmark"
        case .event: "calendar"
        case .studySession: "book.fill"
        case .body: "scalemass.fill"
        case .workout: "figure.strengthtraining.traditional"
        case .groceries: "cart.fill"
        case .habitCheck: "checkmark.circle.fill"
        }
    }
}

struct GroceryItem: Equatable, Hashable, Codable {
    var name: String
    var quantity: Double
    var unit: String
}

/// Registro preparado pelo assistente, aguardando confirmação do usuário.
struct AssistantDraft: Equatable {
    var kind: DraftKind
    var title: String = ""
    var amount: Double?
    var date: Date?
    var hasTime = false
    var financeCategory: FinanceCategory = .outros
    var eventCategory: EventCategory = .compromisso
    var priority: Priority = .media
    var subjectName: String?
    var subjectExists = false
    var cardName: String?
    var installments = 1
    var recurrence: Recurrence = .nenhuma
    var items: [GroceryItem] = []
    var weight: Double?
    var measurements: [String: Double] = [:]
    var muscleGroups: [String] = []
    var minutes: Int?
    var habitName: String?
    var sourceText = ""

    static let measurementLabels: [String: String] = [
        "waist": "Cintura", "arm": "Braço", "chest": "Peito", "leg": "Perna", "hip": "Quadril", "bodyFat": "Gordura corporal",
    ]

    /// Linhas exibidas no cartão de confirmação.
    var summary: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        switch kind {
        case .expense, .income:
            rows.append(("Descrição", title))
            if let amount { rows.append(("Valor", Fmt.currency(amount))) }
            rows.append(("Categoria", financeCategory.label))
            if let date { rows.append(("Data", Fmt.dayMonth(date))) }
            if let cardName { rows.append(("Cartão", cardName)) }
            if installments > 1, let amount {
                rows.append(("Parcelas", "\(installments)x de \(Fmt.currency(amount / Double(installments)))"))
            }
        case .bill:
            rows.append(("Conta", title))
            if let amount { rows.append(("Valor", Fmt.currency(amount))) }
            if let date { rows.append(("Vencimento", Fmt.dayMonth(date))) }
            rows.append(("Repetição", recurrence.label))
            rows.append(("Categoria", financeCategory.label))
        case .event:
            rows.append(("Tipo", eventCategory.label))
            rows.append(("Título", title))
            if let date { rows.append(("Quando", hasTime ? Fmt.dateTime(date) : Fmt.dayMonth(date) + " (dia inteiro)")) }
            if let subjectName { rows.append(("Matéria", subjectName + (subjectExists ? "" : " (nova)"))) }
            rows.append(("Prioridade", priority.label))
        case .studySession:
            if let subjectName { rows.append(("Assunto", subjectName)) }
            if let minutes { rows.append(("Duração", Fmt.duration(minutes: minutes))) }
            if let date { rows.append(("Data", Fmt.dayMonth(date))) }
        case .body:
            if let weight { rows.append(("Peso", "\(Fmt.number(weight)) kg")) }
            for (k, v) in measurements.sorted(by: { $0.key < $1.key }) {
                rows.append((Self.measurementLabels[k] ?? k, k == "bodyFat" ? "\(Fmt.number(v))%" : "\(Fmt.number(v)) cm"))
            }
            if let date { rows.append(("Data", Fmt.dayMonth(date))) }
        case .workout:
            rows.append(("Treino", title))
            if !muscleGroups.isEmpty { rows.append(("Grupos", muscleGroups.joined(separator: ", "))) }
            if let minutes { rows.append(("Duração", Fmt.duration(minutes: minutes))) }
            if let date { rows.append(("Data", Fmt.dayMonth(date))) }
        case .groceries:
            rows.append(("Itens", items.map { item in
                item.quantity == 1 && item.unit == "un" ? item.name : "\(Fmt.number(item.quantity)) \(item.unit) \(item.name)"
            }.joined(separator: ", ")))
            if let amount { rows.append(("Valor gasto", Fmt.currency(amount))) }
        case .habitCheck:
            rows.append(("Hábito", habitName ?? title))
            if let date { rows.append(("Data", Fmt.dayMonth(date))) }
        }
        return rows
    }

    var headline: String {
        switch kind {
        case .event: "Preparei este item para a agenda:"
        case .groceries: "Vou adicionar ao seu estoque de alimentos:"
        default: "Preparei este registro de \(kind.label.lowercased()):"
        }
    }
}

enum MissingField: String, Codable { case amount, date, items, duration, weight }

enum Interpretation: Equatable {
    case draft(AssistantDraft)
    case needsInfo(AssistantDraft, MissingField, String)
    case notUnderstood(String)
}

/// Informações do banco que ajudam a interpretar (nomes de matérias, hábitos, cartões).
struct InterpreterContext {
    var subjectNames: [String] = []
    var contestSubjectNames: [String] = []
    var habitNames: [String] = []
    var cardNames: [String] = []
    var now: Date = Date()
}

/// Ponto de extensão: hoje há um interpretador por regras; no futuro, um modelo de
/// linguagem local (Core ML / Apple Foundation Models) pode implementar o mesmo protocolo.
protocol IntentInterpreter {
    func interpret(_ text: String, context: InterpreterContext) -> Interpretation
    func complete(_ draft: AssistantDraft, missing: MissingField, answer: String, context: InterpreterContext) -> Interpretation
}
