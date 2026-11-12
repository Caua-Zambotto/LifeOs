import Foundation
import SwiftData
import CryptoKit

/// Migração: importa no iPhone os dados exportados pela versão web/PC (descontinuada) do LifeOS.
/// Aceita o backup cifrado (.lifeosbackup: JSON {header, data}) e a exportação aberta (JSON "lifeos-export").
/// Formato web: AES-256-GCM (iv 12 bytes | texto cifrado | tag 16) sobre gzip(JSON),
/// chave PBKDF2-SHA256 da senha, cabeçalho como dado autenticado (AAD) e SHA-256 do JSON.
enum WebImporter {
    struct Payload {
        var createdAt: Date?
        var data: [String: Any]
        var files: [String: String]

        var summary: [(String, Int)] {
            let n = { (k: String) in (data[k] as? [Any])?.count ?? 0 }
            return [("Eventos", n("events")), ("Matérias", n("subjects")), ("Conteúdos", n("topics")), ("Concursos", n("contests")),
                    ("Transações", n("transactions")), ("Contas", n("recurring")), ("Dívidas", n("debts")), ("Treinos", n("workoutSessions")),
                    ("Fichas", n("workoutPlans")), ("Medidas", n("body")), ("Estoque", n("pantry")), ("Metas", n("goals")),
                    ("Hábitos", n("habits")), ("Documentos", n("documents"))].filter { $0.1 > 0 }
        }
    }

    enum ImportError: Error, LocalizedError {
        case notWebBackup, wrongPassword, integrity, gzip
        var errorDescription: String? {
            switch self {
            case .notWebBackup: "Este arquivo não é um backup da versão web do LifeOS."
            case .wrongPassword: "Senha incorreta ou arquivo corrompido."
            case .integrity: "A verificação de integridade falhou: arquivo corrompido."
            case .gzip: "Não foi possível descompactar o backup."
            }
        }
    }

    // MARK: Detecção

    private static func json(_ data: Data) -> [String: Any]? {
        guard let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 || $0 == 0xEF || $0 == 0xBB || $0 == 0xBF) }),
              first == UInt8(ascii: "{") else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func isEncryptedWebBackup(_ data: Data) -> Bool {
        guard let o = json(data), let h = o["header"] as? String, o["data"] is String,
              let hd = h.data(using: .utf8), let header = json(hd) else { return false }
        return header["format"] as? String == "lifeos-backup"
    }

    static func plainExport(_ data: Data) -> Payload? {
        guard let o = json(data), o["format"] as? String == "lifeos-export", let d = o["data"] as? [String: Any] else { return nil }
        return Payload(createdAt: parseDate(o["createdAt"]), data: d, files: [:])
    }

    // MARK: Descriptografia

    static func decrypt(_ fileData: Data, password: String) throws -> Payload {
        guard let outer = json(fileData), let headerString = outer["header"] as? String, let b64 = outer["data"] as? String,
              let headerData = headerString.data(using: .utf8), let header = json(headerData),
              header["format"] as? String == "lifeos-backup",
              let saltB64 = header["salt"] as? String, let salt = Data(base64Encoded: saltB64),
              let iterations = header["iterations"] as? Int, let sealed = Data(base64Encoded: b64) else {
            throw ImportError.notWebBackup
        }
        let key = SymmetricKey(data: try CryptoService.pbkdf2(password: password, salt: salt, rounds: iterations))
        let plain: Data
        do { plain = try CryptoService.decrypt(sealed, key: key, aad: headerData) } catch { throw ImportError.wrongPassword }
        let jsonData = (header["compression"] as? String) == "gzip" ? try gunzip(plain) : plain
        if let sha = header["sha256"] as? String, CryptoService.sha256Hex(jsonData) != sha { throw ImportError.integrity }
        guard let payload = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
              let d = payload["data"] as? [String: Any] else { throw ImportError.notWebBackup }
        return Payload(createdAt: parseDate(payload["createdAt"]), data: d, files: payload["files"] as? [String: String] ?? [:])
    }

    /// Remove o cabeçalho gzip (RFC 1952) e descompacta o DEFLATE bruto.
    static func gunzip(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { throw ImportError.gzip }
        let flags = b[3]
        var pos = 10
        if flags & 0x04 != 0 { guard pos + 2 <= b.count else { throw ImportError.gzip }; pos += 2 + Int(b[pos]) + Int(b[pos + 1]) << 8 }
        if flags & 0x08 != 0 { while pos < b.count && b[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 0x10 != 0 { while pos < b.count && b[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 0x02 != 0 { pos += 2 }
        guard pos < b.count - 8 else { throw ImportError.gzip }
        let deflate = Data(b[pos..<(b.count - 8)])
        // No Foundation, ".zlib" corresponde ao DEFLATE bruto (RFC 1951).
        guard let out = try? (deflate as NSData).decompressed(using: .zlib) as Data else { throw ImportError.gzip }
        return out
    }

    // MARK: Leitura de valores

    private static let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    static func parseDate(_ v: Any?) -> Date? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        return isoFrac.date(from: s) ?? iso.date(from: s)
    }
    private static func str(_ d: [String: Any], _ k: String, _ def: String = "") -> String { (d[k] as? String) ?? def }
    private static func dbl(_ d: [String: Any], _ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
    private static func int(_ d: [String: Any], _ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }
    private static func bool(_ d: [String: Any], _ k: String, _ def: Bool = false) -> Bool { (d[k] as? Bool) ?? def }
    private static func date(_ d: [String: Any], _ k: String) -> Date? { parseDate(d[k]) }
    private static func uuid(_ d: [String: Any], _ k: String = "id") -> UUID? { (d[k] as? String).flatMap(UUID.init(uuidString:)) }
    private static func list(_ p: Payload, _ k: String) -> [[String: Any]] { p.data[k] as? [[String: Any]] ?? [] }
    private static func hex(_ s: String, _ def: String) -> String {
        let h = s.replacingOccurrences(of: "#", with: "").uppercased()
        return h.count == 6 ? h : def
    }
    /// Web: 0 = domingo … 6 = sábado. iOS (Calendar.weekday): 1 = domingo … 7 = sábado.
    private static func weekdays(_ v: Any?) -> Set<Int> { Set(((v as? [NSNumber]) ?? []).map { $0.intValue + 1 }.filter { (1...7).contains($0) }) }
    private static func timeToday(_ hhmm: String) -> Date? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return Fmt.calendar.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date())
    }
    private static let habitSymbols: [String: String] = [
        "📖": "book.fill", "💧": "drop.fill", "🚶": "figure.walk", "🧠": "brain.head.profile", "😴": "moon.fill",
        "🗣️": "character.bubble.fill", "🥗": "leaf.fill", "🏋️": "dumbbell.fill", "✍️": "pencil", "🎵": "music.note", "❤️": "heart.fill",
    ]

    // MARK: Restauração

    /// Substitui TODOS os dados atuais pelos dados da versão web.
    @MainActor
    static func restore(_ p: Payload, context: ModelContext) throws {
        try Persistence.deleteAllRecords(in: context)
        VaultStorage.deleteAllFiles()

        let prof = p.data["profile"] as? [String: Any] ?? [:]
        let profile = UserProfile()
        profile.name = str(prof, "name"); profile.course = str(prof, "course")
        profile.institution = str(prof, "institution"); profile.semester = str(prof, "semester")
        profile.heightCm = dbl(prof, "heightCm"); profile.targetWeight = dbl(prof, "targetWeight")
        profile.initialBalance = dbl(prof, "initialBalance") ?? 0
        profile.balanceDate = date(prof, "balanceDate") ?? Date()
        profile.monthlySavingsTarget = dbl(prof, "monthlySavingsTarget") ?? 0
        context.insert(profile)

        var subjects: [String: Subject] = [:]
        for d in list(p, "subjects") {
            let m = Subject(name: str(d, "name")); m.id = uuid(d) ?? UUID()
            m.professor = str(d, "professor"); m.semester = str(d, "semester"); m.notes = str(d, "notes")
            m.colorHex = hex(str(d, "color"), "8B5CF6"); m.createdAt = date(d, "createdAt") ?? Date()
            context.insert(m); subjects[str(d, "id")] = m
        }
        var contests: [String: Contest] = [:]
        for d in list(p, "contests") {
            let m = Contest(organ: str(d, "organ"), role: str(d, "role")); m.id = uuid(d) ?? UUID()
            m.area = str(d, "area"); m.board = str(d, "board"); m.salary = dbl(d, "salary"); m.vacancies = int(d, "vacancies")
            m.requirements = str(d, "requirements"); m.officialLink = str(d, "link"); m.notes = str(d, "notes")
            m.registrationStart = date(d, "regStart"); m.registrationEnd = date(d, "regEnd"); m.examDate = date(d, "examDate")
            m.statusRaw = ContestStatus(rawValue: str(d, "status"))?.rawValue ?? ContestStatus.previsto.rawValue
            m.createdAt = date(d, "createdAt") ?? Date()
            context.insert(m); contests[str(d, "id")] = m
        }
        var contestSubjects: [String: ContestSubject] = [:]
        for d in list(p, "contestSubjects") {
            let m = ContestSubject(name: str(d, "name"), order: int(d, "order") ?? 0); m.id = uuid(d) ?? UUID()
            context.insert(m); m.contest = contests[str(d, "contestId")]; contestSubjects[str(d, "id")] = m
        }
        var topics: [String: StudyTopic] = [:]
        let topicRows = list(p, "topics")
        for d in topicRows {
            let m = StudyTopic(title: str(d, "title"), order: int(d, "order") ?? 0); m.id = uuid(d) ?? UUID()
            m.statusRaw = TopicStatus(rawValue: str(d, "status"))?.rawValue ?? TopicStatus.naoIniciado.rawValue
            m.lastStudied = date(d, "lastStudied"); m.nextReview = date(d, "nextReview"); m.reviewStage = int(d, "reviewStage") ?? 0
            context.insert(m); topics[str(d, "id")] = m
        }
        for d in topicRows {
            guard let m = topics[str(d, "id")] else { continue }
            m.subject = subjects[str(d, "subjectId")]
            m.contestSubject = contestSubjects[str(d, "contestSubjectId")]
            m.parent = topics[str(d, "parentId")]
        }
        for d in list(p, "grades") {
            let m = Grade(title: str(d, "title"), value: dbl(d, "value") ?? 0, maxValue: dbl(d, "maxValue") ?? 10,
                          weight: dbl(d, "weight") ?? 1, date: date(d, "date") ?? Date())
            context.insert(m); m.subject = subjects[str(d, "subjectId")]
        }
        for d in list(p, "studySessions") {
            let m = StudySession(date: date(d, "date") ?? Date(), minutes: int(d, "minutes") ?? 0, note: str(d, "note"))
            context.insert(m)
            m.subject = subjects[str(d, "subjectId")]; m.contest = contests[str(d, "contestId")]
            m.contestSubject = contestSubjects[str(d, "contestSubjectId")]
        }
        for d in list(p, "questionLogs") {
            let m = QuestionLog(date: date(d, "date") ?? Date(), total: int(d, "total") ?? 0, correct: int(d, "correct") ?? 0)
            context.insert(m); m.contestSubject = contestSubjects[str(d, "contestSubjectId")]
        }
        for d in list(p, "mockExams") {
            let m = MockExam(title: str(d, "title", "Simulado"), date: date(d, "date") ?? Date(), total: int(d, "total") ?? 0, correct: int(d, "correct") ?? 0)
            context.insert(m); m.contest = contests[str(d, "contestId")]
        }
        for d in list(p, "events") {
            let m = AgendaEvent(title: str(d, "title"), start: date(d, "start") ?? Date(),
                                category: EventCategory(rawValue: str(d, "category")) ?? .compromisso)
            m.id = uuid(d) ?? UUID(); m.details = str(d, "details"); m.isAllDay = bool(d, "allDay")
            m.priorityRaw = int(d, "priority") ?? 1
            m.recurrenceRaw = Recurrence(rawValue: str(d, "recurrence"))?.rawValue ?? Recurrence.nenhuma.rawValue
            m.notify = bool(d, "notify", true); m.leadMinutes = int(d, "lead") ?? 60; m.isDone = bool(d, "done")
            context.insert(m)
            m.subject = subjects[str(d, "subjectId")]; m.contest = contests[str(d, "contestId")]
        }

        var cards: [String: CreditCard] = [:]
        for d in list(p, "cards") {
            let m = CreditCard(name: str(d, "name"), limit: dbl(d, "limit") ?? 0, closingDay: int(d, "closingDay") ?? 1, dueDay: int(d, "dueDay") ?? 10)
            m.id = uuid(d) ?? UUID(); m.colorHex = hex(str(d, "color"), "1C1C1E")
            context.insert(m); cards[str(d, "id")] = m
        }
        for d in list(p, "transactions") {
            let kind = FinanceKind(rawValue: str(d, "kind")) ?? .despesa
            let m = FinanceTransaction(title: str(d, "title"), amount: dbl(d, "amount") ?? 0, kind: kind,
                                       category: FinanceCategory(rawValue: str(d, "category")) ?? .outros, date: date(d, "date") ?? Date())
            m.id = uuid(d) ?? UUID(); m.note = str(d, "note"); m.isInvoicePayment = bool(d, "isInvoicePayment")
            m.installmentGroup = uuid(d, "installmentGroup"); m.installmentNumber = int(d, "installmentNumber") ?? 0
            m.installmentCount = int(d, "installmentCount") ?? 0
            context.insert(m); m.card = cards[str(d, "cardId")]
        }
        for d in list(p, "recurring") {
            let m = RecurringEntry(title: str(d, "title"), amount: dbl(d, "amount") ?? 0, kind: FinanceKind(rawValue: str(d, "kind")) ?? .despesa,
                                   category: FinanceCategory(rawValue: str(d, "category")) ?? .outros, dueDate: date(d, "dueDate") ?? Date(),
                                   recurrence: Recurrence(rawValue: str(d, "recurrence")) ?? .mensal)
            m.isActive = bool(d, "isActive", true); m.notify = bool(d, "notify", true); m.lastSettledAt = date(d, "lastSettledAt")
            context.insert(m)
        }
        for d in list(p, "debts") {
            let original = dbl(d, "original") ?? 0
            let m = Debt(creditor: str(d, "creditor"), originalAmount: original, remainingAmount: dbl(d, "remainingAmount") ?? original,
                         monthlyPayment: dbl(d, "monthlyPayment") ?? 0, dueDay: int(d, "dueDay") ?? 10)
            m.monthlyInterestRate = dbl(d, "interest") ?? 0
            context.insert(m)
            for pay in (d["payments"] as? [[String: Any]] ?? []) {
                m.payments.append(DebtPayment(date: date(pay, "date") ?? Date(), amount: dbl(pay, "amount") ?? 0, remainingAfter: dbl(pay, "remainingAfter") ?? 0))
            }
        }
        for d in list(p, "savingsGoals") {
            let m = SavingsGoal(title: str(d, "title"), target: dbl(d, "target") ?? 0); m.saved = dbl(d, "saved") ?? 0
            context.insert(m)
        }

        for (i, d) in list(p, "workoutPlans").enumerated() {
            let m = WorkoutPlan(name: str(d, "name")); m.id = uuid(d) ?? UUID(); m.order = i
            m.weekdays = weekdays(d["weekdays"]); m.reminderTime = timeToday(str(d, "reminder"))
            context.insert(m)
            for (j, e) in (d["exercises"] as? [[String: Any]] ?? []).enumerated() {
                m.exercises.append(ExerciseTemplate(name: str(e, "name"), muscleGroup: str(e, "group"), sets: int(e, "sets") ?? 3,
                                                    reps: int(e, "reps") ?? 10, load: dbl(e, "load") ?? 0, restSeconds: int(e, "rest") ?? 60, order: j))
            }
        }
        for d in list(p, "workoutSessions") {
            let m = WorkoutSession(date: date(d, "date") ?? Date(), title: str(d, "title", "Treino"))
            m.durationMinutes = int(d, "minutes") ?? 0; m.notes = str(d, "notes"); m.planID = uuid(d, "planId")
            m.muscleGroups = (d["muscleGroups"] as? [String]) ?? []
            context.insert(m)
            for (j, e) in (d["entries"] as? [[String: Any]] ?? []).enumerated() {
                m.entries.append(ExerciseEntry(name: str(e, "name"), sets: int(e, "sets") ?? 3, reps: int(e, "reps") ?? 10, load: dbl(e, "load") ?? 0, order: j))
            }
        }
        for d in list(p, "body") {
            let m = BodyMeasurement(date: date(d, "date") ?? Date())
            m.weight = dbl(d, "weight"); m.waist = dbl(d, "waist"); m.arm = dbl(d, "arm"); m.chest = dbl(d, "chest")
            m.leg = dbl(d, "leg"); m.hip = dbl(d, "hip"); m.bodyFat = dbl(d, "bodyFat"); m.note = str(d, "note")
            context.insert(m)
        }
        for d in list(p, "pantry") {
            let m = PantryItem(name: str(d, "name"), quantity: dbl(d, "quantity") ?? 1, unit: str(d, "unit", "un"))
            m.expiresAt = date(d, "expiresAt")
            context.insert(m)
        }
        for d in list(p, "recipes") {
            let m = Recipe(name: str(d, "name"))
            let ingredients = d["ingredients"] as? [[String: Any]] ?? []
            m.ingredientNames = ingredients.map { str($0, "name") }
            m.ingredientQuantities = ingredients.map { str($0, "qty") }
            m.steps = d["steps"] as? [String] ?? []; m.minutes = int(d, "minutes") ?? 20; m.servings = int(d, "servings") ?? 1
            m.tags = d["tags"] as? [String] ?? []
            context.insert(m)
        }
        for d in list(p, "cookLogs") {
            context.insert(CookLog(recipeID: nil, recipeName: str(d, "name"), date: date(d, "date") ?? Date()))
        }
        for d in list(p, "goals") {
            let m = PersonalGoal(title: str(d, "title"))
            m.horizonRaw = GoalHorizon(rawValue: str(d, "horizon"))?.rawValue ?? GoalHorizon.curto.rawValue
            m.areaRaw = GoalArea(rawValue: str(d, "area"))?.rawValue ?? GoalArea.pessoal.rawValue
            m.targetValue = dbl(d, "target") ?? 100; m.currentValue = dbl(d, "current") ?? 0; m.unit = str(d, "unit", "%")
            m.deadline = date(d, "deadline"); m.notes = str(d, "notes"); m.isCompleted = bool(d, "completed")
            context.insert(m)
            for l in (d["logs"] as? [[String: Any]] ?? []) {
                m.logs.append(GoalLog(date: date(l, "date") ?? Date(), delta: dbl(l, "delta") ?? 0, note: str(l, "note")))
            }
        }
        for d in list(p, "habits") {
            let m = Habit(name: str(d, "name"))
            m.icon = habitSymbols[str(d, "icon")] ?? "checkmark.circle.fill"
            m.colorHex = hex(str(d, "color"), "34C759"); m.weekdays = weekdays(d["weekdays"])
            m.reminderTime = timeToday(str(d, "reminder")); m.isArchived = bool(d, "archived")
            context.insert(m)
            for c in (d["checkins"] as? [String] ?? []) {
                if let day = parseDate(c) { m.checkins.append(HabitCheckin(date: day)) }
            }
        }
        for d in list(p, "documents") {
            let m = VaultDocument(title: str(d, "title", "Documento"))
            m.folder = str(d, "folder", "Geral"); m.categoryRaw = DocumentCategory(rawValue: str(d, "category"))?.rawValue ?? DocumentCategory.outro.rawValue
            m.originalFileName = VaultStorage.sanitizeFileName(str(d, "fileName", "arquivo"))
            m.fileExtension = (m.originalFileName as NSString).pathExtension.lowercased()
            m.isSensitive = bool(d, "sensitive"); m.notes = str(d, "notes")
            if let b64 = p.files[str(d, "id")], let bytes = Data(base64Encoded: b64), let stored = try? VaultStorage.store(bytes) {
                m.storedFileName = stored; m.byteSize = bytes.count
            } else {
                m.notes = (m.notes.isEmpty ? "" : m.notes + "\n") + "Arquivo não incluído no backup."
            }
            context.insert(m)
            m.subject = subjects[str(d, "subjectId")]; m.contest = contests[str(d, "contestId")]
        }
        // Histórico do assistente: mantém as mensagens (sem "desfazer", que dependia da versão web).
        for d in list(p, "chat") {
            let m = ChatMessage(text: str(d, "text"), role: ChatRole(rawValue: str(d, "role")) ?? .assistant)
            m.date = date(d, "date") ?? Date()
            context.insert(m)
        }

        try context.save()
        DataSeeder.seedIfNeeded(context)
        NotificationScheduler.rescheduleAll(context: context)
    }
}
