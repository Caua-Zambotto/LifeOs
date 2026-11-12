import Foundation

// Representações Codable de todos os modelos. Relacionamentos viram IDs,
// permitindo exportação completa em JSON e restauração fiel.

struct ProfileDTO: Codable {
    var id: UUID; var name, course, institution, semester: String
    var heightCm, targetWeight: Double?; var initialBalance: Double; var balanceDate: Date
    var monthlySavingsTarget: Double; var createdAt: Date
    // Opcionais: backups antigos não têm estes campos.
    var weeklyStudyGoalMinutes: Int?; var weeklyWorkoutGoal: Int?
    init(_ m: UserProfile) {
        id = m.id; name = m.name; course = m.course; institution = m.institution; semester = m.semester
        heightCm = m.heightCm; targetWeight = m.targetWeight; initialBalance = m.initialBalance
        balanceDate = m.balanceDate; monthlySavingsTarget = m.monthlySavingsTarget; createdAt = m.createdAt
        weeklyStudyGoalMinutes = m.weeklyStudyGoalMinutes; weeklyWorkoutGoal = m.weeklyWorkoutGoal
    }
    func make() -> UserProfile {
        let m = UserProfile(); m.id = id; m.name = name; m.course = course; m.institution = institution
        m.semester = semester; m.heightCm = heightCm; m.targetWeight = targetWeight; m.initialBalance = initialBalance
        m.balanceDate = balanceDate; m.monthlySavingsTarget = monthlySavingsTarget; m.createdAt = createdAt
        m.weeklyStudyGoalMinutes = weeklyStudyGoalMinutes ?? 600; m.weeklyWorkoutGoal = weeklyWorkoutGoal ?? 4
        return m
    }
}

struct EventDTO: Codable {
    var id: UUID; var title, details: String; var start: Date; var end: Date?; var isAllDay: Bool
    var category: String; var priority: Int; var recurrence: String; var notify: Bool; var leadMinutes: Int
    var isDone: Bool; var createdAt: Date; var subjectID, contestID: UUID?
    init(_ m: AgendaEvent) {
        id = m.id; title = m.title; details = m.details; start = m.start; end = m.end; isAllDay = m.isAllDay
        category = m.categoryRaw; priority = m.priorityRaw; recurrence = m.recurrenceRaw; notify = m.notify
        leadMinutes = m.leadMinutes; isDone = m.isDone; createdAt = m.createdAt
        subjectID = m.subject?.id; contestID = m.contest?.id
    }
    func make() -> AgendaEvent {
        let m = AgendaEvent(title: title, start: start); m.id = id; m.details = details; m.end = end
        m.isAllDay = isAllDay; m.categoryRaw = category; m.priorityRaw = priority; m.recurrenceRaw = recurrence
        m.notify = notify; m.leadMinutes = leadMinutes; m.isDone = isDone; m.createdAt = createdAt
        return m
    }
}

struct SubjectDTO: Codable {
    var id: UUID; var name, professor, semester, colorHex, notes: String; var createdAt: Date
    init(_ m: Subject) {
        id = m.id; name = m.name; professor = m.professor; semester = m.semester
        colorHex = m.colorHex; notes = m.notes; createdAt = m.createdAt
    }
    func make() -> Subject {
        let m = Subject(name: name); m.id = id; m.professor = professor; m.semester = semester
        m.colorHex = colorHex; m.notes = notes; m.createdAt = createdAt
        return m
    }
}

struct TopicDTO: Codable {
    var id: UUID; var title, status: String; var order: Int; var lastStudied, nextReview: Date?
    var reviewStage: Int; var createdAt: Date; var subjectID, contestSubjectID, parentID: UUID?
    init(_ m: StudyTopic) {
        id = m.id; title = m.title; status = m.statusRaw; order = m.order; lastStudied = m.lastStudied
        nextReview = m.nextReview; reviewStage = m.reviewStage; createdAt = m.createdAt
        subjectID = m.subject?.id; contestSubjectID = m.contestSubject?.id; parentID = m.parent?.id
    }
    func make() -> StudyTopic {
        let m = StudyTopic(title: title, order: order); m.id = id; m.statusRaw = status
        m.lastStudied = lastStudied; m.nextReview = nextReview; m.reviewStage = reviewStage; m.createdAt = createdAt
        return m
    }
}

struct GradeDTO: Codable {
    var id: UUID; var title: String; var value, maxValue, weight: Double; var date: Date; var subjectID: UUID?
    init(_ m: Grade) {
        id = m.id; title = m.title; value = m.value; maxValue = m.maxValue; weight = m.weight; date = m.date; subjectID = m.subject?.id
    }
    func make() -> Grade { let m = Grade(title: title, value: value, maxValue: maxValue, weight: weight, date: date); m.id = id; return m }
}

struct StudySessionDTO: Codable {
    var id: UUID; var date: Date; var minutes: Int; var note: String; var subjectID, contestID, contestSubjectID: UUID?
    init(_ m: StudySession) {
        id = m.id; date = m.date; minutes = m.minutes; note = m.note
        subjectID = m.subject?.id; contestID = m.contest?.id; contestSubjectID = m.contestSubject?.id
    }
    func make() -> StudySession { let m = StudySession(date: date, minutes: minutes, note: note); m.id = id; return m }
}

struct ContestDTO: Codable {
    var id: UUID; var organ, role, area: String; var salary: Double?; var vacancies: Int?
    var requirements, board, officialLink: String; var registrationStart, registrationEnd, examDate: Date?
    var status, notes: String; var createdAt: Date
    init(_ m: Contest) {
        id = m.id; organ = m.organ; role = m.role; area = m.area; salary = m.salary; vacancies = m.vacancies
        requirements = m.requirements; board = m.board; officialLink = m.officialLink
        registrationStart = m.registrationStart; registrationEnd = m.registrationEnd; examDate = m.examDate
        status = m.statusRaw; notes = m.notes; createdAt = m.createdAt
    }
    func make() -> Contest {
        let m = Contest(organ: organ, role: role); m.id = id; m.area = area; m.salary = salary; m.vacancies = vacancies
        m.requirements = requirements; m.board = board; m.officialLink = officialLink
        m.registrationStart = registrationStart; m.registrationEnd = registrationEnd; m.examDate = examDate
        m.statusRaw = status; m.notes = notes; m.createdAt = createdAt
        return m
    }
}

struct ContestSubjectDTO: Codable {
    var id: UUID; var name: String; var weight: Double; var order: Int; var contestID: UUID?
    init(_ m: ContestSubject) { id = m.id; name = m.name; weight = m.weight; order = m.order; contestID = m.contest?.id }
    func make() -> ContestSubject { let m = ContestSubject(name: name, order: order); m.id = id; m.weight = weight; return m }
}

struct QuestionLogDTO: Codable {
    var id: UUID; var date: Date; var total, correct: Int; var contestSubjectID: UUID?
    init(_ m: QuestionLog) { id = m.id; date = m.date; total = m.total; correct = m.correct; contestSubjectID = m.contestSubject?.id }
    func make() -> QuestionLog { let m = QuestionLog(date: date, total: total, correct: correct); m.id = id; return m }
}

struct MockExamDTO: Codable {
    var id: UUID; var title: String; var date: Date; var total, correct: Int; var notes: String; var contestID: UUID?
    init(_ m: MockExam) { id = m.id; title = m.title; date = m.date; total = m.total; correct = m.correct; notes = m.notes; contestID = m.contest?.id }
    func make() -> MockExam { let m = MockExam(title: title, date: date, total: total, correct: correct); m.id = id; m.notes = notes; return m }
}

struct TransactionDTO: Codable {
    var id: UUID; var title: String; var amount: Double; var kind, category: String; var date: Date; var note: String
    var isInvoicePayment: Bool; var installmentGroup: UUID?; var installmentNumber, installmentCount: Int
    var createdAt: Date; var cardID: UUID?
    init(_ m: FinanceTransaction) {
        id = m.id; title = m.title; amount = m.amount; kind = m.kindRaw; category = m.categoryRaw; date = m.date
        note = m.note; isInvoicePayment = m.isInvoicePayment; installmentGroup = m.installmentGroup
        installmentNumber = m.installmentNumber; installmentCount = m.installmentCount; createdAt = m.createdAt; cardID = m.card?.id
    }
    func make() -> FinanceTransaction {
        let m = FinanceTransaction(title: title, amount: amount, kind: FinanceKind(rawValue: kind) ?? .despesa,
                                   category: FinanceCategory(rawValue: category) ?? .outros, date: date)
        m.id = id; m.note = note; m.isInvoicePayment = isInvoicePayment; m.installmentGroup = installmentGroup
        m.installmentNumber = installmentNumber; m.installmentCount = installmentCount; m.createdAt = createdAt
        return m
    }
}

struct CardDTO: Codable {
    var id: UUID; var name: String; var limit: Double; var closingDay, dueDay: Int; var colorHex: String; var createdAt: Date
    init(_ m: CreditCard) { id = m.id; name = m.name; limit = m.limit; closingDay = m.closingDay; dueDay = m.dueDay; colorHex = m.colorHex; createdAt = m.createdAt }
    func make() -> CreditCard {
        let m = CreditCard(name: name, limit: limit, closingDay: closingDay, dueDay: dueDay)
        m.id = id; m.colorHex = colorHex; m.createdAt = createdAt
        return m
    }
}

struct RecurringDTO: Codable {
    var id: UUID; var title: String; var amount: Double; var kind, category: String; var dueDate: Date
    var recurrence: String; var isActive, notify: Bool; var lastSettledAt: Date?; var createdAt: Date
    init(_ m: RecurringEntry) {
        id = m.id; title = m.title; amount = m.amount; kind = m.kindRaw; category = m.categoryRaw; dueDate = m.dueDate
        recurrence = m.recurrenceRaw; isActive = m.isActive; notify = m.notify; lastSettledAt = m.lastSettledAt; createdAt = m.createdAt
    }
    func make() -> RecurringEntry {
        let m = RecurringEntry(title: title, amount: amount, kind: FinanceKind(rawValue: kind) ?? .despesa,
                               category: FinanceCategory(rawValue: category) ?? .outros, dueDate: dueDate,
                               recurrence: Recurrence(rawValue: recurrence) ?? .mensal)
        m.id = id; m.isActive = isActive; m.notify = notify; m.lastSettledAt = lastSettledAt; m.createdAt = createdAt
        return m
    }
}

struct DebtDTO: Codable {
    var id: UUID; var creditor: String; var originalAmount, remainingAmount, monthlyPayment, monthlyInterestRate: Double
    var dueDay: Int; var notes: String; var createdAt: Date
    init(_ m: Debt) {
        id = m.id; creditor = m.creditor; originalAmount = m.originalAmount; remainingAmount = m.remainingAmount
        monthlyPayment = m.monthlyPayment; monthlyInterestRate = m.monthlyInterestRate; dueDay = m.dueDay; notes = m.notes; createdAt = m.createdAt
    }
    func make() -> Debt {
        let m = Debt(creditor: creditor, originalAmount: originalAmount, remainingAmount: remainingAmount, monthlyPayment: monthlyPayment, dueDay: dueDay)
        m.id = id; m.monthlyInterestRate = monthlyInterestRate; m.notes = notes; m.createdAt = createdAt
        return m
    }
}

struct DebtPaymentDTO: Codable {
    var id: UUID; var date: Date; var amount, remainingAfter: Double; var debtID: UUID?
    init(_ m: DebtPayment) { id = m.id; date = m.date; amount = m.amount; remainingAfter = m.remainingAfter; debtID = m.debt?.id }
    func make() -> DebtPayment { let m = DebtPayment(date: date, amount: amount, remainingAfter: remainingAfter); m.id = id; return m }
}

struct SavingsGoalDTO: Codable {
    var id: UUID; var title: String; var target, saved: Double; var deadline: Date?; var createdAt: Date
    init(_ m: SavingsGoal) { id = m.id; title = m.title; target = m.target; saved = m.saved; deadline = m.deadline; createdAt = m.createdAt }
    func make() -> SavingsGoal { let m = SavingsGoal(title: title, target: target, deadline: deadline); m.id = id; m.saved = saved; m.createdAt = createdAt; return m }
}

struct WorkoutPlanDTO: Codable {
    var id: UUID; var name, weekdays: String; var reminderTime: Date?; var order: Int; var createdAt: Date
    init(_ m: WorkoutPlan) { id = m.id; name = m.name; weekdays = m.weekdaysRaw; reminderTime = m.reminderTime; order = m.order; createdAt = m.createdAt }
    func make() -> WorkoutPlan {
        let m = WorkoutPlan(name: name); m.id = id; m.weekdaysRaw = weekdays; m.reminderTime = reminderTime; m.order = order; m.createdAt = createdAt
        return m
    }
}

struct ExerciseTemplateDTO: Codable {
    var id: UUID; var name, muscleGroup: String; var sets, reps: Int; var load: Double; var restSeconds, order: Int; var planID: UUID?
    init(_ m: ExerciseTemplate) {
        id = m.id; name = m.name; muscleGroup = m.muscleGroup; sets = m.sets; reps = m.reps; load = m.load
        restSeconds = m.restSeconds; order = m.order; planID = m.plan?.id
    }
    func make() -> ExerciseTemplate {
        let m = ExerciseTemplate(name: name, muscleGroup: muscleGroup, sets: sets, reps: reps, load: load, restSeconds: restSeconds, order: order)
        m.id = id; return m
    }
}

struct WorkoutSessionDTO: Codable {
    var id: UUID; var date: Date; var title, muscleGroups: String; var durationMinutes: Int; var notes: String; var planID: UUID?
    init(_ m: WorkoutSession) {
        id = m.id; date = m.date; title = m.title; muscleGroups = m.muscleGroupsRaw
        durationMinutes = m.durationMinutes; notes = m.notes; planID = m.planID
    }
    func make() -> WorkoutSession {
        let m = WorkoutSession(date: date, title: title); m.id = id; m.muscleGroupsRaw = muscleGroups
        m.durationMinutes = durationMinutes; m.notes = notes; m.planID = planID
        return m
    }
}

struct ExerciseEntryDTO: Codable {
    var id: UUID; var name: String; var sets, reps: Int; var load: Double; var order: Int; var sessionID: UUID?
    init(_ m: ExerciseEntry) { id = m.id; name = m.name; sets = m.sets; reps = m.reps; load = m.load; order = m.order; sessionID = m.session?.id }
    func make() -> ExerciseEntry { let m = ExerciseEntry(name: name, sets: sets, reps: reps, load: load, order: order); m.id = id; return m }
}

struct BodyDTO: Codable {
    var id: UUID; var date: Date; var weight, waist, arm, chest, leg, hip, bodyFat: Double?; var note: String
    init(_ m: BodyMeasurement) {
        id = m.id; date = m.date; weight = m.weight; waist = m.waist; arm = m.arm; chest = m.chest
        leg = m.leg; hip = m.hip; bodyFat = m.bodyFat; note = m.note
    }
    func make() -> BodyMeasurement {
        let m = BodyMeasurement(date: date); m.id = id; m.weight = weight; m.waist = waist; m.arm = arm
        m.chest = chest; m.leg = leg; m.hip = hip; m.bodyFat = bodyFat; m.note = note
        return m
    }
}

struct PantryDTO: Codable {
    var id: UUID; var name: String; var quantity: Double; var unit: String; var addedAt: Date; var expiresAt: Date?
    init(_ m: PantryItem) { id = m.id; name = m.name; quantity = m.quantity; unit = m.unit; addedAt = m.addedAt; expiresAt = m.expiresAt }
    func make() -> PantryItem { let m = PantryItem(name: name, quantity: quantity, unit: unit); m.id = id; m.addedAt = addedAt; m.expiresAt = expiresAt; return m }
}

struct RecipeDTO: Codable {
    var id: UUID; var catalogKey, name: String; var ingredientNames, ingredientQuantities, steps: [String]
    var minutes, servings: Int; var kcal, protein, carbs, fat: Double?; var tags: [String]
    var isBuiltIn, isFavorite: Bool; var createdAt: Date
    init(_ m: Recipe) {
        id = m.id; catalogKey = m.catalogKey; name = m.name; ingredientNames = m.ingredientNames
        ingredientQuantities = m.ingredientQuantities; steps = m.steps; minutes = m.minutes; servings = m.servings
        kcal = m.kcal; protein = m.protein; carbs = m.carbs; fat = m.fat; tags = m.tags
        isBuiltIn = m.isBuiltIn; isFavorite = m.isFavorite; createdAt = m.createdAt
    }
    func make() -> Recipe {
        let m = Recipe(name: name); m.id = id; m.catalogKey = catalogKey; m.ingredientNames = ingredientNames
        m.ingredientQuantities = ingredientQuantities; m.steps = steps; m.minutes = minutes; m.servings = servings
        m.kcal = kcal; m.protein = protein; m.carbs = carbs; m.fat = fat; m.tags = tags
        m.isBuiltIn = isBuiltIn; m.isFavorite = isFavorite; m.createdAt = createdAt
        return m
    }
}

struct CookLogDTO: Codable {
    var id: UUID; var recipeID: UUID?; var recipeName: String; var date: Date
    init(_ m: CookLog) { id = m.id; recipeID = m.recipeID; recipeName = m.recipeName; date = m.date }
    func make() -> CookLog { let m = CookLog(recipeID: recipeID, recipeName: recipeName, date: date); m.id = id; return m }
}

struct GoalDTO: Codable {
    var id: UUID; var title, horizon, area: String; var targetValue, currentValue: Double; var unit: String
    var deadline: Date?; var notes: String; var isCompleted: Bool; var createdAt: Date
    init(_ m: PersonalGoal) {
        id = m.id; title = m.title; horizon = m.horizonRaw; area = m.areaRaw; targetValue = m.targetValue
        currentValue = m.currentValue; unit = m.unit; deadline = m.deadline; notes = m.notes
        isCompleted = m.isCompleted; createdAt = m.createdAt
    }
    func make() -> PersonalGoal {
        let m = PersonalGoal(title: title); m.id = id; m.horizonRaw = horizon; m.areaRaw = area
        m.targetValue = targetValue; m.currentValue = currentValue; m.unit = unit; m.deadline = deadline
        m.notes = notes; m.isCompleted = isCompleted; m.createdAt = createdAt
        return m
    }
}

struct GoalLogDTO: Codable {
    var id: UUID; var date: Date; var delta: Double; var note: String; var goalID: UUID?
    init(_ m: GoalLog) { id = m.id; date = m.date; delta = m.delta; note = m.note; goalID = m.goal?.id }
    func make() -> GoalLog { let m = GoalLog(date: date, delta: delta, note: note); m.id = id; return m }
}

struct HabitDTO: Codable {
    var id: UUID; var name, icon, colorHex, weekdays: String; var reminderTime: Date?; var isArchived: Bool; var createdAt: Date
    init(_ m: Habit) {
        id = m.id; name = m.name; icon = m.icon; colorHex = m.colorHex; weekdays = m.weekdaysRaw
        reminderTime = m.reminderTime; isArchived = m.isArchived; createdAt = m.createdAt
    }
    func make() -> Habit {
        let m = Habit(name: name); m.id = id; m.icon = icon; m.colorHex = colorHex; m.weekdaysRaw = weekdays
        m.reminderTime = reminderTime; m.isArchived = isArchived; m.createdAt = createdAt
        return m
    }
}

struct CheckinDTO: Codable {
    var id: UUID; var date: Date; var habitID: UUID?
    init(_ m: HabitCheckin) { id = m.id; date = m.date; habitID = m.habit?.id }
    func make() -> HabitCheckin { let m = HabitCheckin(date: date); m.id = id; return m }
}

struct DocumentDTO: Codable {
    var id: UUID; var title, folder, category, storedFileName, originalFileName, fileExtension: String
    var byteSize: Int; var isSensitive: Bool; var notes: String; var createdAt: Date; var subjectID, contestID: UUID?
    init(_ m: VaultDocument) {
        id = m.id; title = m.title; folder = m.folder; category = m.categoryRaw; storedFileName = m.storedFileName
        originalFileName = m.originalFileName; fileExtension = m.fileExtension; byteSize = m.byteSize
        isSensitive = m.isSensitive; notes = m.notes; createdAt = m.createdAt; subjectID = m.subject?.id; contestID = m.contest?.id
    }
    func make() -> VaultDocument {
        let m = VaultDocument(title: title); m.id = id; m.folder = folder; m.categoryRaw = category
        m.originalFileName = originalFileName; m.fileExtension = fileExtension; m.byteSize = byteSize
        m.isSensitive = isSensitive; m.notes = notes; m.createdAt = createdAt
        return m
    }
}

struct ChatDTO: Codable {
    var id: UUID; var date: Date; var text, role: String; var recordRefs: [String]; var isUndone: Bool
    init(_ m: ChatMessage) { id = m.id; date = m.date; text = m.text; role = m.roleRaw; recordRefs = m.recordRefs; isUndone = m.isUndone }
    func make() -> ChatMessage {
        let m = ChatMessage(text: text, role: ChatRole(rawValue: role) ?? .user, recordRefs: recordRefs)
        m.id = id; m.date = date; m.isUndone = isUndone
        return m
    }
}

/// Conteúdo completo de um backup.
struct BackupPayload: Codable {
    var formatVersion = 1
    var createdAt = Date()
    var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    var profiles: [ProfileDTO] = []
    var events: [EventDTO] = []
    var subjects: [SubjectDTO] = []
    var topics: [TopicDTO] = []
    var grades: [GradeDTO] = []
    var studySessions: [StudySessionDTO] = []
    var contests: [ContestDTO] = []
    var contestSubjects: [ContestSubjectDTO] = []
    var questionLogs: [QuestionLogDTO] = []
    var mockExams: [MockExamDTO] = []
    var transactions: [TransactionDTO] = []
    var cards: [CardDTO] = []
    var recurring: [RecurringDTO] = []
    var debts: [DebtDTO] = []
    var debtPayments: [DebtPaymentDTO] = []
    var savingsGoals: [SavingsGoalDTO] = []
    var workoutPlans: [WorkoutPlanDTO] = []
    var exerciseTemplates: [ExerciseTemplateDTO] = []
    var workoutSessions: [WorkoutSessionDTO] = []
    var exerciseEntries: [ExerciseEntryDTO] = []
    var body: [BodyDTO] = []
    var pantry: [PantryDTO] = []
    var recipes: [RecipeDTO] = []
    var cookLogs: [CookLogDTO] = []
    var goals: [GoalDTO] = []
    var goalLogs: [GoalLogDTO] = []
    var habits: [HabitDTO] = []
    var checkins: [CheckinDTO] = []
    var documents: [DocumentDTO] = []
    var chat: [ChatDTO] = []
    /// Conteúdo dos documentos (descriptografado do cofre; protegido pela criptografia do backup).
    var documentFiles: [String: Data]? = nil

    var summary: [(String, Int)] {
        [("Eventos", events.count), ("Matérias", subjects.count), ("Assuntos", topics.count),
         ("Concursos", contests.count), ("Transações", transactions.count), ("Contas", recurring.count),
         ("Dívidas", debts.count), ("Treinos", workoutSessions.count), ("Medidas", body.count),
         ("Estoque", pantry.count), ("Metas", goals.count), ("Hábitos", habits.count),
         ("Documentos", documents.count)]
    }
}
