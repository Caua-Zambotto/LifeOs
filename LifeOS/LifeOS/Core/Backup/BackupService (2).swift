import Foundation
import SwiftData
import CryptoKit

/// Formato do arquivo .lifeosbackup:
///   "LIFEOSBK" (8 bytes) | versão (1 byte) | tamanho do cabeçalho (UInt32 big-endian) | cabeçalho JSON | dados
/// Dados = AES-256-GCM( LZFSE( JSON do BackupPayload ) ), chave derivada da senha com PBKDF2-SHA256.
/// O cabeçalho é autenticado (AAD): qualquer alteração invalida o arquivo.
/// Integridade adicional: SHA-256 do JSON é conferido após descriptografar.
enum BackupError: Error, LocalizedError {
    case invalidFormat, unsupportedVersion, integrityFailed, weakPassword, emptyPassword
    var errorDescription: String? {
        switch self {
        case .invalidFormat: "Este arquivo não é um backup do LifeOS."
        case .unsupportedVersion: "Backup criado por uma versão mais nova do LifeOS."
        case .integrityFailed: "A verificação de integridade falhou: o arquivo está corrompido."
        case .weakPassword: "Use uma senha de backup com pelo menos 8 caracteres."
        case .emptyPassword: "Informe a senha do backup."
        }
    }
}

struct BackupHeader: Codable {
    var formatVersion: Int
    var createdAt: Date
    var appVersion: String
    var kdf: String
    var iterations: Int
    var salt: String
    var payloadSHA256: String
    var compression: String
    var includesDocuments: Bool
}

enum BackupService {
    static let magic = Data("LIFEOSBK".utf8)
    static let fileVersion: UInt8 = 1
    static let iterations = 310_000
    static let fileExtension = "lifeosbackup"

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Captura

    @MainActor
    static func snapshot(context: ModelContext, includeDocuments: Bool) throws -> BackupPayload {
        func all<T: PersistentModel>(_ t: T.Type) throws -> [T] { try context.fetch(FetchDescriptor<T>()) }
        var p = BackupPayload()
        p.profiles = try all(UserProfile.self).map(ProfileDTO.init)
        p.events = try all(AgendaEvent.self).map(EventDTO.init)
        p.subjects = try all(Subject.self).map(SubjectDTO.init)
        p.topics = try all(StudyTopic.self).map(TopicDTO.init)
        p.grades = try all(Grade.self).map(GradeDTO.init)
        p.studySessions = try all(StudySession.self).map(StudySessionDTO.init)
        p.contests = try all(Contest.self).map(ContestDTO.init)
        p.contestSubjects = try all(ContestSubject.self).map(ContestSubjectDTO.init)
        p.questionLogs = try all(QuestionLog.self).map(QuestionLogDTO.init)
        p.mockExams = try all(MockExam.self).map(MockExamDTO.init)
        p.transactions = try all(FinanceTransaction.self).map(TransactionDTO.init)
        p.cards = try all(CreditCard.self).map(CardDTO.init)
        p.recurring = try all(RecurringEntry.self).map(RecurringDTO.init)
        p.debts = try all(Debt.self).map(DebtDTO.init)
        p.debtPayments = try all(DebtPayment.self).map(DebtPaymentDTO.init)
        p.savingsGoals = try all(SavingsGoal.self).map(SavingsGoalDTO.init)
        p.workoutPlans = try all(WorkoutPlan.self).map(WorkoutPlanDTO.init)
        p.exerciseTemplates = try all(ExerciseTemplate.self).map(ExerciseTemplateDTO.init)
        p.workoutSessions = try all(WorkoutSession.self).map(WorkoutSessionDTO.init)
        p.exerciseEntries = try all(ExerciseEntry.self).map(ExerciseEntryDTO.init)
        p.body = try all(BodyMeasurement.self).map(BodyDTO.init)
        p.pantry = try all(PantryItem.self).map(PantryDTO.init)
        p.recipes = try all(Recipe.self).map(RecipeDTO.init)
        p.cookLogs = try all(CookLog.self).map(CookLogDTO.init)
        p.goals = try all(PersonalGoal.self).map(GoalDTO.init)
        p.goalLogs = try all(GoalLog.self).map(GoalLogDTO.init)
        p.habits = try all(Habit.self).map(HabitDTO.init)
        p.checkins = try all(HabitCheckin.self).map(CheckinDTO.init)
        let docs = try all(VaultDocument.self)
        p.documents = docs.map(DocumentDTO.init)
        p.chat = try all(ChatMessage.self).map(ChatDTO.init)
        if includeDocuments {
            var files: [String: Data] = [:]
            for d in docs { if let data = try? VaultStorage.load(d.storedFileName) { files[d.id.uuidString] = data } }
            p.documentFiles = files
        }
        return p
    }

    // MARK: - Criptografia do arquivo

    static func validatePassword(_ password: String) throws {
        if password.isEmpty { throw BackupError.emptyPassword }
        if password.count < 8 { throw BackupError.weakPassword }
    }

    static func encrypt(_ payload: BackupPayload, password: String) throws -> Data {
        try validatePassword(password)
        let json = try encoder.encode(payload)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        let salt = CryptoService.randomBytes(16)
        let header = BackupHeader(formatVersion: payload.formatVersion, createdAt: payload.createdAt,
                                  appVersion: payload.appVersion, kdf: "PBKDF2-HMAC-SHA256", iterations: iterations,
                                  salt: salt.base64EncodedString(), payloadSHA256: CryptoService.sha256Hex(json),
                                  compression: "lzfse", includesDocuments: payload.documentFiles != nil)
        let headerData = try encoder.encode(header)
        let key = SymmetricKey(data: try CryptoService.pbkdf2(password: password, salt: salt, rounds: iterations))
        let sealed = try CryptoService.encrypt(compressed, key: key, aad: headerData)

        var out = Data()
        out.append(magic)
        out.append(fileVersion)
        var len = UInt32(headerData.count).bigEndian
        out.append(Data(bytes: &len, count: 4))
        out.append(headerData)
        out.append(sealed)
        return out
    }

    static func readHeader(_ data: Data) throws -> (BackupHeader, Data, Data) {
        guard data.count > 13, data.prefix(8) == magic else { throw BackupError.invalidFormat }
        let version = data[data.startIndex + 8]
        guard version <= fileVersion else { throw BackupError.unsupportedVersion }
        let lenBytes = data.subdata(in: (data.startIndex + 9)..<(data.startIndex + 13))
        let len = lenBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let headerStart = data.startIndex + 13
        let headerEnd = headerStart + Int(len)
        guard headerEnd < data.endIndex else { throw BackupError.invalidFormat }
        let headerData = data.subdata(in: headerStart..<headerEnd)
        let header = try decoder.decode(BackupHeader.self, from: headerData)
        return (header, headerData, data.subdata(in: headerEnd..<data.endIndex))
    }

    /// Descriptografa e verifica a integridade. Lança erro se a senha estiver errada.
    static func decrypt(_ data: Data, password: String) throws -> BackupPayload {
        if password.isEmpty { throw BackupError.emptyPassword }
        let (header, headerData, sealed) = try readHeader(data)
        guard let salt = Data(base64Encoded: header.salt) else { throw BackupError.invalidFormat }
        let key = SymmetricKey(data: try CryptoService.pbkdf2(password: password, salt: salt, rounds: header.iterations))
        let compressed = try CryptoService.decrypt(sealed, key: key, aad: headerData)
        let json = try (compressed as NSData).decompressed(using: .lzfse) as Data
        guard CryptoService.sha256Hex(json) == header.payloadSHA256 else { throw BackupError.integrityFailed }
        return try decoder.decode(BackupPayload.self, from: json)
    }

    // MARK: - Exportação aberta (JSON)

    static func plainJSON(_ payload: BackupPayload) throws -> Data {
        let e = encoder
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(payload)
    }

    static func plainPayload(from data: Data) throws -> BackupPayload {
        try decoder.decode(BackupPayload.self, from: data)
    }

    // MARK: - Restauração

    /// Substitui TODOS os dados atuais pelo conteúdo do backup.
    @MainActor
    static func restore(_ p: BackupPayload, context: ModelContext) throws {
        try Persistence.deleteAllRecords(in: context)
        VaultStorage.deleteAllFiles()

        p.profiles.forEach { context.insert($0.make()) }

        var subjects: [UUID: Subject] = [:]
        for d in p.subjects { let m = d.make(); context.insert(m); subjects[d.id] = m }
        var contests: [UUID: Contest] = [:]
        for d in p.contests { let m = d.make(); context.insert(m); contests[d.id] = m }
        var contestSubjects: [UUID: ContestSubject] = [:]
        for d in p.contestSubjects {
            let m = d.make(); context.insert(m); contestSubjects[d.id] = m
            m.contest = d.contestID.flatMap { contests[$0] }
        }
        var topics: [UUID: StudyTopic] = [:]
        for d in p.topics { let m = d.make(); context.insert(m); topics[d.id] = m }
        for d in p.topics {
            guard let m = topics[d.id] else { continue }
            m.subject = d.subjectID.flatMap { subjects[$0] }
            m.contestSubject = d.contestSubjectID.flatMap { contestSubjects[$0] }
            m.parent = d.parentID.flatMap { topics[$0] }
        }
        for d in p.grades { let m = d.make(); context.insert(m); m.subject = d.subjectID.flatMap { subjects[$0] } }
        for d in p.studySessions {
            let m = d.make(); context.insert(m)
            m.subject = d.subjectID.flatMap { subjects[$0] }
            m.contest = d.contestID.flatMap { contests[$0] }
            m.contestSubject = d.contestSubjectID.flatMap { contestSubjects[$0] }
        }
        for d in p.questionLogs { let m = d.make(); context.insert(m); m.contestSubject = d.contestSubjectID.flatMap { contestSubjects[$0] } }
        for d in p.mockExams { let m = d.make(); context.insert(m); m.contest = d.contestID.flatMap { contests[$0] } }
        for d in p.events {
            let m = d.make(); context.insert(m)
            m.subject = d.subjectID.flatMap { subjects[$0] }
            m.contest = d.contestID.flatMap { contests[$0] }
        }

        var cards: [UUID: CreditCard] = [:]
        for d in p.cards { let m = d.make(); context.insert(m); cards[d.id] = m }
        for d in p.transactions { let m = d.make(); context.insert(m); m.card = d.cardID.flatMap { cards[$0] } }
        p.recurring.forEach { context.insert($0.make()) }
        var debts: [UUID: Debt] = [:]
        for d in p.debts { let m = d.make(); context.insert(m); debts[d.id] = m }
        for d in p.debtPayments { let m = d.make(); context.insert(m); m.debt = d.debtID.flatMap { debts[$0] } }
        p.savingsGoals.forEach { context.insert($0.make()) }

        var plans: [UUID: WorkoutPlan] = [:]
        for d in p.workoutPlans { let m = d.make(); context.insert(m); plans[d.id] = m }
        for d in p.exerciseTemplates { let m = d.make(); context.insert(m); m.plan = d.planID.flatMap { plans[$0] } }
        var sessions: [UUID: WorkoutSession] = [:]
        for d in p.workoutSessions { let m = d.make(); context.insert(m); sessions[d.id] = m }
        for d in p.exerciseEntries { let m = d.make(); context.insert(m); m.session = d.sessionID.flatMap { sessions[$0] } }
        p.body.forEach { context.insert($0.make()) }

        p.pantry.forEach { context.insert($0.make()) }
        p.recipes.forEach { context.insert($0.make()) }
        p.cookLogs.forEach { context.insert($0.make()) }

        var goals: [UUID: PersonalGoal] = [:]
        for d in p.goals { let m = d.make(); context.insert(m); goals[d.id] = m }
        for d in p.goalLogs { let m = d.make(); context.insert(m); m.goal = d.goalID.flatMap { goals[$0] } }
        var habits: [UUID: Habit] = [:]
        for d in p.habits { let m = d.make(); context.insert(m); habits[d.id] = m }
        for d in p.checkins { let m = d.make(); context.insert(m); m.habit = d.habitID.flatMap { habits[$0] } }

        for d in p.documents {
            let m = d.make()
            // Os arquivos são recriptografados com a chave do cofre DESTE aparelho.
            if let data = p.documentFiles?[d.id.uuidString], let stored = try? VaultStorage.store(data) {
                m.storedFileName = stored
                m.byteSize = data.count
            } else {
                m.storedFileName = ""
                m.notes = (m.notes.isEmpty ? "" : m.notes + "\n") + "Arquivo não incluído no backup."
            }
            context.insert(m)
            m.subject = d.subjectID.flatMap { subjects[$0] }
            m.contest = d.contestID.flatMap { contests[$0] }
        }
        p.chat.forEach { context.insert($0.make()) }

        try context.save()
        DataSeeder.seedIfNeeded(context)
        NotificationScheduler.rescheduleAll(context: context)
    }

    // MARK: - Arquivo temporário para exportar

    static func writeTemporary(_ data: Data, name: String) throws -> URL {
        let url = AppPaths.temp.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func defaultFileName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "LifeOS-backup-\(f.string(from: date)).\(fileExtension)"
    }

    static var lastBackupDate: Date? {
        get { UserDefaults.standard.object(forKey: "backup.last") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "backup.last") }
    }
}
