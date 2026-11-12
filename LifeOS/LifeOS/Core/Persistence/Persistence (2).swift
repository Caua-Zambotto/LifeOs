import Foundation
import SwiftData

/// Diretórios do app. Tudo fica no próprio iPhone, dentro do sandbox.
enum AppPaths {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LifeOS", isDirectory: true)
        ensure(dir, protection: .completeUntilFirstUserAuthentication)
        return dir
    }

    /// Banco de dados SwiftData (SQLite).
    static var database: URL {
        let dir = root.appendingPathComponent("Database", isDirectory: true)
        ensure(dir, protection: .completeUntilFirstUserAuthentication)
        return dir
    }

    /// Cofre de documentos: arquivos já criptografados + proteção "complete".
    static var vault: URL {
        let dir = root.appendingPathComponent("Vault", isDirectory: true)
        ensure(dir, protection: .complete)
        return dir
    }

    /// Arquivos temporários descriptografados (visualização/exportação). Limpos ao sair.
    static var temp: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LifeOS-tmp", isDirectory: true)
        ensure(dir, protection: .complete)
        return dir
    }

    static func ensure(_ url: URL, protection: FileProtectionType) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: protection])
        }
    }

    /// Aplica a classe de proteção a todos os arquivos de um diretório.
    static func harden(_ dir: URL, protection: FileProtectionType) {
        let fm = FileManager.default
        try? fm.setAttributes([.protectionKey: protection], ofItemAtPath: dir.path)
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files {
            try? fm.setAttributes([.protectionKey: protection], ofItemAtPath: dir.appendingPathComponent(f).path)
        }
    }

    static func protectionLevel(of url: URL) -> FileProtectionType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.protectionKey] as? FileProtectionType
    }

    static func size(of dir: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in en {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func clearTemp() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil) else { return }
        files.forEach { try? fm.removeItem(at: $0) }
    }
}

enum Persistence {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self,
        AgendaEvent.self,
        Subject.self, StudyTopic.self, Grade.self, StudySession.self,
        Contest.self, ContestSubject.self, QuestionLog.self, MockExam.self,
        FinanceTransaction.self, CreditCard.self, RecurringEntry.self, Debt.self, DebtPayment.self, SavingsGoal.self,
        WorkoutPlan.self, ExerciseTemplate.self, WorkoutSession.self, ExerciseEntry.self, BodyMeasurement.self,
        PantryItem.self, Recipe.self, CookLog.self,
        PersonalGoal.self, GoalLog.self, Habit.self, HabitCheckin.self,
        VaultDocument.self,
        ChatMessage.self,
    ]

    static var schema: Schema { Schema(models) }

    static var storeURL: URL { AppPaths.database.appendingPathComponent("LifeOS.store") }

    /// Banco local persistente. Sem CloudKit: nenhum dado sai do aparelho.
    static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration("LifeOS", schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        AppPaths.harden(AppPaths.database, protection: .completeUntilFirstUserAuthentication)
        return container
    }

    /// Usado em testes e previews.
    static func makeInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Apaga todos os registros de todos os modelos.
    @MainActor
    static func deleteAllRecords(in context: ModelContext) throws {
        // Ordem: filhos antes dos pais, evitando violações de relacionamento.
        try deleteAll(ChatMessage.self, context)
        try deleteAll(HabitCheckin.self, context)
        try deleteAll(Habit.self, context)
        try deleteAll(GoalLog.self, context)
        try deleteAll(PersonalGoal.self, context)
        try deleteAll(CookLog.self, context)
        try deleteAll(Recipe.self, context)
        try deleteAll(PantryItem.self, context)
        try deleteAll(BodyMeasurement.self, context)
        try deleteAll(ExerciseEntry.self, context)
        try deleteAll(WorkoutSession.self, context)
        try deleteAll(ExerciseTemplate.self, context)
        try deleteAll(WorkoutPlan.self, context)
        try deleteAll(SavingsGoal.self, context)
        try deleteAll(DebtPayment.self, context)
        try deleteAll(Debt.self, context)
        try deleteAll(RecurringEntry.self, context)
        try deleteAll(FinanceTransaction.self, context)
        try deleteAll(CreditCard.self, context)
        try deleteAll(VaultDocument.self, context)
        try deleteAll(QuestionLog.self, context)
        try deleteAll(MockExam.self, context)
        try deleteAll(StudySession.self, context)
        try deleteAll(StudyTopic.self, context)
        try deleteAll(ContestSubject.self, context)
        try deleteAll(Contest.self, context)
        try deleteAll(Grade.self, context)
        try deleteAll(AgendaEvent.self, context)
        try deleteAll(Subject.self, context)
        try deleteAll(UserProfile.self, context)
        try context.save()
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        for item in items { context.delete(item) }
    }
}

extension ModelContext {
    /// Perfil único do usuário (cria se não existir).
    @MainActor
    func profile() -> UserProfile {
        if let p = try? fetch(FetchDescriptor<UserProfile>()).first { return p }
        let p = UserProfile()
        insert(p)
        try? save()
        return p
    }

    func saveQuietly() {
        do { try save() } catch { SafeLog.error("Falha ao salvar contexto") }
    }
}

/// Dados de referência carregados na primeira execução (catálogo de receitas).
/// Não são dados fictícios do usuário: são conteúdo de referência do app.
enum DataSeeder {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        _ = context.profile()
        let existing = (try? context.fetch(FetchDescriptor<Recipe>()))?.filter(\.isBuiltIn) ?? []
        let keys = Set(existing.map(\.catalogKey))
        for item in RecipeCatalog.all where !keys.contains(item.key) {
            context.insert(item.makeModel())
        }
        context.saveQuietly()
    }
}
