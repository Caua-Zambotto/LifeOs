import XCTest
import SwiftData
import CryptoKit
@testable import LifeOS

final class CryptoTests: XCTestCase {
    func testPBKDF2KnownVector() throws {
        // Vetor de teste público: PBKDF2-HMAC-SHA256("password", "salt", 1 iteração, 32 bytes)
        let key = try CryptoService.pbkdf2(password: "password", salt: Data("salt".utf8), rounds: 1, length: 32)
        XCTAssertEqual(key.map { String(format: "%02x", $0) }.joined(),
                       "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    func testEncryptDecryptRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let data = Data("dados sensíveis".utf8)
        let sealed = try CryptoService.encrypt(data, key: key, aad: Data("cabecalho".utf8))
        XCTAssertNotEqual(sealed, data)
        XCTAssertEqual(try CryptoService.decrypt(sealed, key: key, aad: Data("cabecalho".utf8)), data)
    }

    func testWrongKeyOrTamperedAADFails() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try CryptoService.encrypt(Data("x".utf8), key: key, aad: Data("a".utf8))
        XCTAssertThrowsError(try CryptoService.decrypt(sealed, key: SymmetricKey(size: .bits256), aad: Data("a".utf8)))
        XCTAssertThrowsError(try CryptoService.decrypt(sealed, key: key, aad: Data("b".utf8)))
    }

    func testConstantTimeEquals() {
        XCTAssertTrue(CryptoService.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 3])))
        XCTAssertFalse(CryptoService.constantTimeEquals(Data([1, 2, 3]), Data([1, 2, 4])))
        XCTAssertFalse(CryptoService.constantTimeEquals(Data([1, 2]), Data([1, 2, 3])))
    }

    func testTrivialPasscodes() {
        XCTAssertTrue(PasscodeManager.isTrivial("000000"))
        XCTAssertTrue(PasscodeManager.isTrivial("123456"))
        XCTAssertTrue(PasscodeManager.isTrivial("654321"))
        XCTAssertFalse(PasscodeManager.isTrivial("274915"))
        XCTAssertFalse(PasscodeManager.isValidFormat("12a456"))
        XCTAssertFalse(PasscodeManager.isValidFormat("27491"))
    }

    func testSanitizeFileName() {
        XCTAssertEqual(VaultStorage.sanitizeFileName("../../etc/passwd"), "____etc_passwd")
        XCTAssertFalse(VaultStorage.sanitizeFileName("a/b\\c:d").contains("/"))
        XCTAssertEqual(VaultStorage.sanitizeFileName("   "), "arquivo")
    }

    func testCSVEscapesFormulas() {
        XCTAssertEqual(CSVExporter.escape("=SOMA(A1)"), "'=SOMA(A1)")
        XCTAssertEqual(CSVExporter.escape("a;b"), "\"a;b\"")
    }
}

@MainActor
final class FinanceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        container = try Persistence.makeInMemory()
        context = container.mainContext
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Fmt.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testInvoiceMonth() {
        // fechamento dia 5: compra dia 3 entra na fatura do mês; dia 10 vai para o mês seguinte
        XCTAssertEqual(FinanceCalculator.invoiceKey(FinanceCalculator.invoiceMonth(for: date(2026, 11, 3), closingDay: 5)), "2026-11")
        XCTAssertEqual(FinanceCalculator.invoiceKey(FinanceCalculator.invoiceMonth(for: date(2026, 11, 10), closingDay: 5)), "2026-12")
        XCTAssertEqual(FinanceCalculator.invoiceKey(FinanceCalculator.invoiceMonth(for: date(2026, 12, 20), closingDay: 5)), "2027-01")
    }

    func testInstallmentsSumExactly() {
        let card = CreditCard(name: "Teste", limit: 1000, closingDay: 5, dueDay: 12)
        context.insert(card)
        let txs = FinanceService.addTransaction(title: "Notebook", amount: 1000, kind: .despesa, category: .compras,
                                                date: date(2026, 11, 1), card: card, installments: 3, context: context)
        XCTAssertEqual(txs.count, 3)
        XCTAssertEqual(txs.reduce(0) { $0 + $1.amount }, 1000, accuracy: 0.001)
        XCTAssertEqual(Set(txs.map(\.installmentGroup)).count, 1)
        XCTAssertEqual(txs.map(\.installmentNumber), [1, 2, 3])
        XCTAssertEqual(Fmt.calendar.component(.month, from: txs[2].date), 1)
    }

    func testBalanceIgnoresCardPurchasesUntilInvoicePaid() {
        let card = CreditCard(name: "C", limit: 1000, closingDay: 5, dueDay: 12)
        context.insert(card)
        let now = date(2026, 11, 20)
        FinanceService.addTransaction(title: "Salário", amount: 3000, kind: .receita, category: .salario, date: date(2026, 11, 5), card: nil, installments: 1, context: context)
        FinanceService.addTransaction(title: "Mercado", amount: 200, kind: .despesa, category: .alimentacao, date: date(2026, 11, 6), card: nil, installments: 1, context: context)
        FinanceService.addTransaction(title: "Roupa", amount: 300, kind: .despesa, category: .compras, date: date(2026, 11, 7), card: card, installments: 1, context: context)
        let all = try! context.fetch(FetchDescriptor<FinanceTransaction>())
        XCTAssertEqual(FinanceCalculator.balance(initial: 100, since: date(2026, 11, 1), transactions: all, now: now), 2900, accuracy: 0.001)
        XCTAssertEqual(FinanceCalculator.outstanding(card: card, now: now), 300, accuracy: 0.001)
        // gastos por categoria incluem compras no cartão
        let month = DateInterval(start: date(2026, 11, 1), end: now)
        XCTAssertEqual(FinanceCalculator.spending(all, in: month), 500, accuracy: 0.001)
    }

    func testWeeklyPlan() {
        let profile = UserProfile()
        profile.initialBalance = 1000
        profile.balanceDate = date(2026, 11, 1)
        context.insert(profile)
        let bill = RecurringEntry(title: "Internet", amount: 100, kind: .despesa, category: .internet, dueDate: date(2026, 11, 25), recurrence: .mensal)
        context.insert(bill)
        let now = date(2026, 11, 16) // segunda-feira
        let plan = FinanceCalculator.weeklyPlan(profile: profile, transactions: [], recurring: [bill], debts: [], cards: [], now: now)
        XCTAssertEqual(plan.available, 900, accuracy: 0.001)
        // de 16 a 30/11 = 15 dias -> 3 semanas
        XCTAssertEqual(plan.weeksRemaining, 3)
        XCTAssertEqual(plan.weeklyAllowance, 300, accuracy: 0.001)
        XCTAssertFalse(plan.isOverBudget)
    }

    func testSettleRecurringAdvancesDueDate() {
        let bill = RecurringEntry(title: "Luz", amount: 150, kind: .despesa, category: .moradia, dueDate: date(2026, 11, 10), recurrence: .mensal)
        context.insert(bill)
        FinanceService.settle(bill, context: context, date: date(2026, 11, 9))
        XCTAssertEqual(Fmt.calendar.component(.month, from: bill.dueDate), 12)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinanceTransaction>()), 1)
    }
}

final class StudyAndRecipeTests: XCTestCase {
    func testSpacedReviewSchedule() {
        let t = StudyTopic(title: "Redes")
        let now = Date()
        StudyReview.setStatus(.concluido, for: t, now: now)
        XCTAssertEqual(Fmt.daysUntil(t.nextReview!, now: now), 1)
        StudyReview.markReviewed(t, now: now)
        XCTAssertEqual(Fmt.daysUntil(t.nextReview!, now: now), 7)
    }

    func testWeightedAverage() {
        let g1 = Grade(title: "P1", value: 8, maxValue: 10, weight: 1)
        let g2 = Grade(title: "P2", value: 30, maxValue: 50, weight: 2) // 6,0
        XCTAssertEqual(StudyReview.weightedAverage([g1, g2])!, (8 + 6 * 2) / 3, accuracy: 0.0001)
    }

    func testRecipeSuggestions() {
        let recipes = RecipeCatalog.all.map { $0.makeModel() }
        let pantry = [PantryItem(name: "Ovos", quantity: 6), PantryItem(name: "Tomate"), PantryItem(name: "Cebola")]
        let s = RecipeEngine.suggestions(recipes: recipes, pantry: pantry)
        XCTAssertEqual(s.first?.recipe.catalogKey, "omelete-legumes")
        XCTAssertEqual(s.first?.score, 1)
    }

    func testCanonicalNames() {
        XCTAssertEqual(RecipeEngine.canonical("Ovos"), "ovo")
        XCTAssertEqual(RecipeEngine.canonical("Feijão"), "feijao")
        XCTAssertTrue(RecipeEngine.has("Sal", in: []))
    }

    func testFoodDictionary() {
        XCTAssertEqual(FoodDictionary.fromVisionLabel("banana"), "Banana")
        XCTAssertEqual(FoodDictionary.fromText("ARROZ TIPO 1 5KG"), ["Arroz"])
        XCTAssertEqual(FoodDictionary.fromText("MACARRAO ESPAGUETE"), ["Macarrão"])
    }
}

final class WebImporterTests: XCTestCase {
    func testGunzipStandardHeader() throws {
        // gzip de {"ok":"LifeOS"} (cabeçalho RFC 1952 sem flags, como gera o navegador)
        let gz = Data(base64Encoded: "H4sIAAAAAAAC/6tWys9WslLyyUxL9Q9WqgUAotP8lQ8AAAA=")!
        let out = try WebImporter.gunzip(gz)
        XCTAssertEqual(String(data: out, encoding: .utf8), "{\"ok\":\"LifeOS\"}")
    }

    func testRejectsNonGzip() {
        XCTAssertThrowsError(try WebImporter.gunzip(Data("nao e gzip, apenas texto qualquer".utf8)))
    }

    func testDetectsWebFormats() {
        let header = #"{"format":"lifeos-backup","version":1,"iterations":1,"salt":"AAAA","sha256":"x","compression":"gzip"}"#
        let enc = try! JSONSerialization.data(withJSONObject: ["header": header, "data": "AAAA"])
        XCTAssertTrue(WebImporter.isEncryptedWebBackup(enc))
        let plain = Data(#"{"format":"lifeos-export","version":1,"createdAt":"2026-11-12T10:00:00.000Z","data":{"events":[{"title":"A"}]}}"#.utf8)
        XCTAssertEqual(WebImporter.plainExport(plain)?.summary.first?.1, 1)
        XCTAssertNotNil(WebImporter.plainExport(plain)?.createdAt)
        XCTAssertFalse(WebImporter.isEncryptedWebBackup(Data("LIFEOSBK".utf8)))
    }

    @MainActor
    func testImportMapsRelationshipsAndWeekdays() throws {
        let container = try Persistence.makeInMemory()
        let ctx = container.mainContext
        let subjectID = UUID().uuidString
        let json = """
        {"format":"lifeos-export","version":1,"data":{
          "profile":{"name":"Teste","initialBalance":1000},
          "subjects":[{"id":"\(subjectID)","name":"Cálculo","color":"#8b5cf6"}],
          "events":[{"id":"\(UUID().uuidString)","title":"Prova de Cálculo","start":"2026-11-19T22:00:00.000Z","category":"prova","priority":2,"recurrence":"nenhuma","subjectId":"\(subjectID)"}],
          "habits":[{"name":"Ler","icon":"📖","color":"#22c55e","weekdays":[1,3,5],"checkins":["2026-11-12T03:00:00.000Z"]}],
          "transactions":[{"title":"Almoço","amount":35.5,"kind":"despesa","category":"alimentacao","date":"2026-11-12T15:00:00.000Z"}]
        }}
        """
        let payload = try XCTUnwrap(WebImporter.plainExport(Data(json.utf8)))
        try WebImporter.restore(payload, context: ctx)
        let subject = try XCTUnwrap(ctx.fetch(FetchDescriptor<Subject>()).first)
        XCTAssertEqual(subject.events.first?.title, "Prova de Cálculo")
        XCTAssertEqual(subject.colorHex, "8B5CF6")
        let habit = try XCTUnwrap(ctx.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertEqual(habit.weekdays, [2, 4, 6]) // seg, qua, sex
        XCTAssertEqual(habit.icon, "book.fill")
        XCTAssertEqual(habit.checkins.count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<FinanceTransaction>()).first?.amount, 35.5)
        XCTAssertEqual(ctx.profile().initialBalance, 1000)
    }
}

@MainActor
final class BackupTests: XCTestCase {
    // Os contêineres precisam ficar vivos enquanto os contextos são usados.
    private var containers: [ModelContainer] = []

    private func newContext() throws -> ModelContext {
        let c = try Persistence.makeInMemory()
        containers.append(c)
        return c.mainContext
    }

    func testBackupRoundTripPreservesRelationships() throws {
        let source = try newContext()
        let subject = Subject(name: "Cálculo")
        source.insert(subject)
        let exam = AgendaEvent(title: "Prova de Cálculo", start: Date(), category: .prova)
        source.insert(exam)
        exam.subject = subject
        let topic = StudyTopic(title: "Limites")
        source.insert(topic)
        topic.subject = subject
        let child = StudyTopic(title: "Limites laterais")
        source.insert(child)
        child.parent = topic
        child.subject = subject
        FinanceService.addTransaction(title: "Almoço", amount: 35, kind: .despesa, category: .alimentacao, date: Date(), card: nil, installments: 1, context: source)
        try source.save()

        let payload = try BackupService.snapshot(context: source, includeDocuments: false)
        let encrypted = try BackupService.encrypt(payload, password: "senha-forte-123")
        XCTAssertThrowsError(try BackupService.decrypt(encrypted, password: "errada-123"))
        let decrypted = try BackupService.decrypt(encrypted, password: "senha-forte-123")

        let target = try newContext()
        try BackupService.restore(decrypted, context: target)

        let subjects = try target.fetch(FetchDescriptor<Subject>())
        XCTAssertEqual(subjects.count, 1)
        XCTAssertEqual(subjects.first?.events.first?.title, "Prova de Cálculo")
        let topics = try target.fetch(FetchDescriptor<StudyTopic>())
        XCTAssertEqual(topics.first { $0.title == "Limites laterais" }?.parent?.title, "Limites")
        XCTAssertEqual(try target.fetch(FetchDescriptor<FinanceTransaction>()).first?.amount, 35)
    }

    func testTamperedBackupIsRejected() throws {
        let ctx = try newContext()
        var data = try BackupService.encrypt(try BackupService.snapshot(context: ctx, includeDocuments: false), password: "12345678")
        data[data.count - 5] ^= 0xFF
        XCTAssertThrowsError(try BackupService.decrypt(data, password: "12345678"))
    }

    func testWeakPasswordRejected() throws {
        let ctx = try newContext()
        XCTAssertThrowsError(try BackupService.encrypt(try BackupService.snapshot(context: ctx, includeDocuments: false), password: "123"))
    }

    func testAssistantSaveAndUndo() throws {
        let ctx = try newContext()
        var d = AssistantDraft(kind: .event)
        d.title = "Prova de Física"
        d.eventCategory = .prova
        d.date = Date().adding(days: 3)
        d.subjectName = "Física"
        d.subjectExists = false
        let outcome = try AssistantExecutor.save(d, context: ctx)
        let subject = try ctx.fetch(FetchDescriptor<Subject>()).first
        XCTAssertEqual(subject?.name, "Física")
        XCTAssertEqual(subject?.events.count, 1, "a prova deve aparecer na agenda E na matéria, sem duplicar")
        try AssistantExecutor.undo(refs: outcome.refs, context: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<AgendaEvent>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Subject>()), 0)
    }
}
