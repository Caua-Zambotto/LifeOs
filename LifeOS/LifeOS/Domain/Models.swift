import Foundation
import SwiftData

// Todos os modelos usam valores padrão (exigência do SwiftData para migração leve)
// e enums persistidos como String/Int brutos (mais robusto em predicados e migrações).
// Referências entre registros (ex.: prova -> matéria) evitam duplicidade de dados.

// MARK: - Perfil

@Model final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var course: String = ""
    var institution: String = ""
    var semester: String = ""
    var heightCm: Double? = nil
    var targetWeight: Double? = nil
    /// Saldo informado pelo usuário na data `balanceDate` (ponto de partida do cálculo).
    var initialBalance: Double = 0
    var balanceDate: Date = Date()
    /// Quanto o usuário quer guardar por mês (usado no planejamento semanal).
    var monthlySavingsTarget: Double = 0
    /// Metas semanais (novas; valores padrão garantem migração automática dos dados existentes).
    var weeklyStudyGoalMinutes: Int = 600
    var weeklyWorkoutGoal: Int = 4
    var createdAt: Date = Date()
    init() {}
}

// MARK: - Agenda

@Model final class AgendaEvent {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var start: Date = Date()
    var end: Date? = nil
    var isAllDay: Bool = false
    var categoryRaw: String = EventCategory.compromisso.rawValue
    var priorityRaw: Int = Priority.media.rawValue
    var recurrenceRaw: String = Recurrence.nenhuma.rawValue
    var notify: Bool = true
    var leadMinutes: Int = 60
    var isDone: Bool = false
    var createdAt: Date = Date()
    var subject: Subject? = nil
    var contest: Contest? = nil

    init(title: String, start: Date, category: EventCategory = .compromisso) {
        self.title = title
        self.start = start
        self.categoryRaw = category.rawValue
        self.leadMinutes = category.notificationCategory.defaultLead
    }

    var category: EventCategory {
        get { EventCategory(rawValue: categoryRaw) ?? .compromisso }
        set { categoryRaw = newValue.rawValue }
    }
    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .media }
        set { priorityRaw = newValue.rawValue }
    }
    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .nenhuma }
        set { recurrenceRaw = newValue.rawValue }
    }
}

// MARK: - Faculdade

@Model final class Subject {
    var id: UUID = UUID()
    var name: String = ""
    var professor: String = ""
    var semester: String = ""
    var colorHex: String = "7C5CFF"
    var notes: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \StudyTopic.subject) var topics: [StudyTopic] = []
    @Relationship(deleteRule: .cascade, inverse: \Grade.subject) var grades: [Grade] = []
    @Relationship(deleteRule: .nullify, inverse: \AgendaEvent.subject) var events: [AgendaEvent] = []
    @Relationship(deleteRule: .nullify, inverse: \StudySession.subject) var sessions: [StudySession] = []
    @Relationship(deleteRule: .nullify, inverse: \VaultDocument.subject) var documents: [VaultDocument] = []

    init(name: String) { self.name = name }
}

@Model final class StudyTopic {
    var id: UUID = UUID()
    var title: String = ""
    var statusRaw: String = TopicStatus.naoIniciado.rawValue
    var order: Int = 0
    var lastStudied: Date? = nil
    var nextReview: Date? = nil
    var reviewStage: Int = 0
    var createdAt: Date = Date()
    var subject: Subject? = nil
    var contestSubject: ContestSubject? = nil
    var parent: StudyTopic? = nil
    @Relationship(deleteRule: .cascade, inverse: \StudyTopic.parent) var children: [StudyTopic] = []

    init(title: String, order: Int = 0) { self.title = title; self.order = order }

    var status: TopicStatus {
        get { TopicStatus(rawValue: statusRaw) ?? .naoIniciado }
        set { statusRaw = newValue.rawValue }
    }
}

@Model final class Grade {
    var id: UUID = UUID()
    var title: String = ""
    var value: Double = 0
    var maxValue: Double = 10
    var weight: Double = 1
    var date: Date = Date()
    var subject: Subject? = nil
    init(title: String, value: Double, maxValue: Double = 10, weight: Double = 1, date: Date = Date()) {
        self.title = title; self.value = value; self.maxValue = maxValue; self.weight = weight; self.date = date
    }
    /// Nota normalizada de 0 a 10.
    var normalized: Double { maxValue > 0 ? value / maxValue * 10 : 0 }
}

@Model final class StudySession {
    var id: UUID = UUID()
    var date: Date = Date()
    var minutes: Int = 0
    var note: String = ""
    var subject: Subject? = nil
    var contest: Contest? = nil
    var contestSubject: ContestSubject? = nil
    init(date: Date = Date(), minutes: Int, note: String = "") { self.date = date; self.minutes = minutes; self.note = note }
}

// MARK: - Concursos

@Model final class Contest {
    var id: UUID = UUID()
    var organ: String = ""
    var role: String = ""
    var area: String = ""
    var salary: Double? = nil
    var vacancies: Int? = nil
    var requirements: String = ""
    var board: String = ""
    var officialLink: String = ""
    var registrationStart: Date? = nil
    var registrationEnd: Date? = nil
    var examDate: Date? = nil
    var statusRaw: String = ContestStatus.interesse.rawValue
    var notes: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \ContestSubject.contest) var subjects: [ContestSubject] = []
    @Relationship(deleteRule: .cascade, inverse: \MockExam.contest) var mockExams: [MockExam] = []
    @Relationship(deleteRule: .nullify, inverse: \StudySession.contest) var sessions: [StudySession] = []
    @Relationship(deleteRule: .nullify, inverse: \AgendaEvent.contest) var events: [AgendaEvent] = []
    @Relationship(deleteRule: .nullify, inverse: \VaultDocument.contest) var documents: [VaultDocument] = []

    init(organ: String, role: String) { self.organ = organ; self.role = role }

    var status: ContestStatus {
        get { ContestStatus(rawValue: statusRaw) ?? .interesse }
        set { statusRaw = newValue.rawValue }
    }
    var displayName: String { role.isEmpty ? organ : "\(organ) · \(role)" }
}

@Model final class ContestSubject {
    var id: UUID = UUID()
    var name: String = ""
    var weight: Double = 1
    var order: Int = 0
    var contest: Contest? = nil
    @Relationship(deleteRule: .cascade, inverse: \StudyTopic.contestSubject) var topics: [StudyTopic] = []
    @Relationship(deleteRule: .cascade, inverse: \QuestionLog.contestSubject) var questionLogs: [QuestionLog] = []
    @Relationship(deleteRule: .nullify, inverse: \StudySession.contestSubject) var sessions: [StudySession] = []
    init(name: String, order: Int = 0) { self.name = name; self.order = order }
}

@Model final class QuestionLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var total: Int = 0
    var correct: Int = 0
    var contestSubject: ContestSubject? = nil
    init(date: Date = Date(), total: Int, correct: Int) { self.date = date; self.total = total; self.correct = correct }
}

@Model final class MockExam {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()
    var total: Int = 0
    var correct: Int = 0
    var notes: String = ""
    var contest: Contest? = nil
    init(title: String, date: Date = Date(), total: Int, correct: Int) {
        self.title = title; self.date = date; self.total = total; self.correct = correct
    }
    var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0 }
}

// MARK: - Finanças

@Model final class FinanceTransaction {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Double = 0
    var kindRaw: String = FinanceKind.despesa.rawValue
    var categoryRaw: String = FinanceCategory.outros.rawValue
    var date: Date = Date()
    var note: String = ""
    var isInvoicePayment: Bool = false
    var installmentGroup: UUID? = nil
    var installmentNumber: Int = 0
    var installmentCount: Int = 0
    var createdAt: Date = Date()
    var card: CreditCard? = nil

    init(title: String, amount: Double, kind: FinanceKind, category: FinanceCategory, date: Date = Date()) {
        self.title = title; self.amount = amount; self.kindRaw = kind.rawValue
        self.categoryRaw = category.rawValue; self.date = date
    }

    var kind: FinanceKind {
        get { FinanceKind(rawValue: kindRaw) ?? .despesa }
        set { kindRaw = newValue.rawValue }
    }
    var category: FinanceCategory {
        get { FinanceCategory(rawValue: categoryRaw) ?? .outros }
        set { categoryRaw = newValue.rawValue }
    }
    /// Valor com sinal: receitas positivas, despesas negativas.
    var signedAmount: Double { kind == .receita ? amount : -amount }
    /// Afeta o saldo em conta? Compras no cartão só afetam quando a fatura é paga.
    var affectsBalance: Bool { card == nil || isInvoicePayment }
}

@Model final class CreditCard {
    var id: UUID = UUID()
    var name: String = ""
    var limit: Double = 0
    var closingDay: Int = 1
    var dueDay: Int = 10
    var colorHex: String = "1C1C1E"
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \FinanceTransaction.card) var transactions: [FinanceTransaction] = []
    init(name: String, limit: Double, closingDay: Int, dueDay: Int) {
        self.name = name; self.limit = limit; self.closingDay = closingDay; self.dueDay = dueDay
    }
}

/// Contas a pagar (internet, aluguel...) e receitas previstas (salário), únicas ou recorrentes.
@Model final class RecurringEntry {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Double = 0
    var kindRaw: String = FinanceKind.despesa.rawValue
    var categoryRaw: String = FinanceCategory.outros.rawValue
    var dueDate: Date = Date()
    var recurrenceRaw: String = Recurrence.mensal.rawValue
    var isActive: Bool = true
    var notify: Bool = true
    var lastSettledAt: Date? = nil
    var createdAt: Date = Date()

    init(title: String, amount: Double, kind: FinanceKind, category: FinanceCategory, dueDate: Date, recurrence: Recurrence) {
        self.title = title; self.amount = amount; self.kindRaw = kind.rawValue
        self.categoryRaw = category.rawValue; self.dueDate = dueDate; self.recurrenceRaw = recurrence.rawValue
    }
    var kind: FinanceKind {
        get { FinanceKind(rawValue: kindRaw) ?? .despesa }
        set { kindRaw = newValue.rawValue }
    }
    var category: FinanceCategory {
        get { FinanceCategory(rawValue: categoryRaw) ?? .outros }
        set { categoryRaw = newValue.rawValue }
    }
    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .mensal }
        set { recurrenceRaw = newValue.rawValue }
    }
}

@Model final class Debt {
    var id: UUID = UUID()
    var creditor: String = ""
    var originalAmount: Double = 0
    var remainingAmount: Double = 0
    var monthlyPayment: Double = 0
    var monthlyInterestRate: Double = 0
    var dueDay: Int = 10
    var notes: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \DebtPayment.debt) var payments: [DebtPayment] = []
    init(creditor: String, originalAmount: Double, remainingAmount: Double, monthlyPayment: Double, dueDay: Int) {
        self.creditor = creditor; self.originalAmount = originalAmount; self.remainingAmount = remainingAmount
        self.monthlyPayment = monthlyPayment; self.dueDay = dueDay
    }
    var progress: Double { originalAmount > 0 ? min(1, max(0, 1 - remainingAmount / originalAmount)) : 0 }
}

@Model final class DebtPayment {
    var id: UUID = UUID()
    var date: Date = Date()
    var amount: Double = 0
    var remainingAfter: Double = 0
    var debt: Debt? = nil
    init(date: Date, amount: Double, remainingAfter: Double) {
        self.date = date; self.amount = amount; self.remainingAfter = remainingAfter
    }
}

@Model final class SavingsGoal {
    var id: UUID = UUID()
    var title: String = ""
    var target: Double = 0
    var saved: Double = 0
    var deadline: Date? = nil
    var createdAt: Date = Date()
    init(title: String, target: Double, deadline: Date? = nil) {
        self.title = title; self.target = target; self.deadline = deadline
    }
    var progress: Double { target > 0 ? min(1, saved / target) : 0 }
}

// MARK: - Treinos e corpo

@Model final class WorkoutPlan {
    var id: UUID = UUID()
    var name: String = ""
    /// Dias da semana (Calendar.weekday 1=domingo...7=sábado), separados por vírgula.
    var weekdaysRaw: String = ""
    var reminderTime: Date? = nil
    var order: Int = 0
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \ExerciseTemplate.plan) var exercises: [ExerciseTemplate] = []
    init(name: String) { self.name = name }

    var weekdays: Set<Int> {
        get { Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { weekdaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }
    var sortedExercises: [ExerciseTemplate] { exercises.sorted { $0.order < $1.order } }
}

@Model final class ExerciseTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var muscleGroup: String = ""
    var sets: Int = 3
    var reps: Int = 10
    var load: Double = 0
    var restSeconds: Int = 60
    var order: Int = 0
    var plan: WorkoutPlan? = nil
    init(name: String, muscleGroup: String = "", sets: Int = 3, reps: Int = 10, load: Double = 0, restSeconds: Int = 60, order: Int = 0) {
        self.name = name; self.muscleGroup = muscleGroup; self.sets = sets; self.reps = reps
        self.load = load; self.restSeconds = restSeconds; self.order = order
    }
}

@Model final class WorkoutSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var muscleGroupsRaw: String = ""
    var durationMinutes: Int = 0
    var notes: String = ""
    var planID: UUID? = nil
    @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.session) var entries: [ExerciseEntry] = []
    init(date: Date = Date(), title: String) { self.date = date; self.title = title }

    var muscleGroups: [String] {
        get { muscleGroupsRaw.split(separator: ",").map { String($0) } }
        set { muscleGroupsRaw = newValue.joined(separator: ",") }
    }
    var sortedEntries: [ExerciseEntry] { entries.sorted { $0.order < $1.order } }
}

@Model final class ExerciseEntry {
    var id: UUID = UUID()
    var name: String = ""
    var sets: Int = 3
    var reps: Int = 10
    var load: Double = 0
    var order: Int = 0
    var session: WorkoutSession? = nil
    init(name: String, sets: Int, reps: Int, load: Double, order: Int) {
        self.name = name; self.sets = sets; self.reps = reps; self.load = load; self.order = order
    }
}

@Model final class BodyMeasurement {
    var id: UUID = UUID()
    var date: Date = Date()
    var weight: Double? = nil
    var waist: Double? = nil
    var arm: Double? = nil
    var chest: Double? = nil
    var leg: Double? = nil
    var hip: Double? = nil
    var bodyFat: Double? = nil
    var note: String = ""
    init(date: Date = Date()) { self.date = date }
}

// MARK: - Alimentação

@Model final class PantryItem {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double = 1
    var unit: String = "un"
    var addedAt: Date = Date()
    var expiresAt: Date? = nil
    init(name: String, quantity: Double = 1, unit: String = "un") {
        self.name = name; self.quantity = quantity; self.unit = unit
    }
}

@Model final class Recipe {
    var id: UUID = UUID()
    /// Chave estável para receitas do catálogo embutido (vazia para receitas do usuário).
    var catalogKey: String = ""
    var name: String = ""
    var ingredientNames: [String] = []
    var ingredientQuantities: [String] = []
    var steps: [String] = []
    var minutes: Int = 20
    var servings: Int = 1
    var kcal: Double? = nil
    var protein: Double? = nil
    var carbs: Double? = nil
    var fat: Double? = nil
    var tags: [String] = []
    var isBuiltIn: Bool = false
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    init(name: String) { self.name = name }
}

@Model final class CookLog {
    var id: UUID = UUID()
    var recipeID: UUID? = nil
    var recipeName: String = ""
    var date: Date = Date()
    init(recipeID: UUID?, recipeName: String, date: Date = Date()) {
        self.recipeID = recipeID; self.recipeName = recipeName; self.date = date
    }
}

// MARK: - Desenvolvimento pessoal

@Model final class PersonalGoal {
    var id: UUID = UUID()
    var title: String = ""
    var horizonRaw: String = GoalHorizon.curto.rawValue
    var areaRaw: String = GoalArea.pessoal.rawValue
    var targetValue: Double = 100
    var currentValue: Double = 0
    var unit: String = "%"
    var deadline: Date? = nil
    var notes: String = ""
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \GoalLog.goal) var logs: [GoalLog] = []
    init(title: String) { self.title = title }

    var horizon: GoalHorizon {
        get { GoalHorizon(rawValue: horizonRaw) ?? .curto }
        set { horizonRaw = newValue.rawValue }
    }
    var area: GoalArea {
        get { GoalArea(rawValue: areaRaw) ?? .pessoal }
        set { areaRaw = newValue.rawValue }
    }
    var progress: Double { targetValue > 0 ? min(1, max(0, currentValue / targetValue)) : 0 }
}

@Model final class GoalLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var delta: Double = 0
    var note: String = ""
    var goal: PersonalGoal? = nil
    init(date: Date = Date(), delta: Double, note: String) { self.date = date; self.delta = delta; self.note = note }
}

@Model final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "checkmark.circle.fill"
    var colorHex: String = "34C759"
    /// Dias da semana (1...7). Vazio = todos os dias.
    var weekdaysRaw: String = ""
    var reminderTime: Date? = nil
    var isArchived: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \HabitCheckin.habit) var checkins: [HabitCheckin] = []
    init(name: String) { self.name = name }

    var weekdays: Set<Int> {
        get { Set(weekdaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { weekdaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }
    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: date))
    }
    func isDone(on date: Date, calendar: Calendar = .current) -> Bool {
        checkins.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

@Model final class HabitCheckin {
    var id: UUID = UUID()
    var date: Date = Date()
    var habit: Habit? = nil
    init(date: Date) { self.date = date }
}

// MARK: - Documentos

@Model final class VaultDocument {
    var id: UUID = UUID()
    var title: String = ""
    var folder: String = "Geral"
    var categoryRaw: String = DocumentCategory.outro.rawValue
    /// Nome do arquivo criptografado dentro do cofre.
    var storedFileName: String = ""
    var originalFileName: String = ""
    var fileExtension: String = ""
    var byteSize: Int = 0
    var isSensitive: Bool = false
    var notes: String = ""
    var createdAt: Date = Date()
    var subject: Subject? = nil
    var contest: Contest? = nil
    init(title: String) { self.title = title }

    var category: DocumentCategory {
        get { DocumentCategory(rawValue: categoryRaw) ?? .outro }
        set { categoryRaw = newValue.rawValue }
    }
}

// MARK: - Assistente

@Model final class ChatMessage {
    var id: UUID = UUID()
    var date: Date = Date()
    var text: String = ""
    var roleRaw: String = ChatRole.user.rawValue
    /// Referências "tipo:uuid" para os registros criados (permite desfazer).
    var recordRefs: [String] = []
    var isUndone: Bool = false
    init(text: String, role: ChatRole, recordRefs: [String] = []) {
        self.text = text; self.roleRaw = role.rawValue; self.recordRefs = recordRefs
    }
    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
}
