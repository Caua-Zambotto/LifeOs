import XCTest
@testable import LifeOS

/// Data de referência fixa: quinta-feira, 12/11/2026, 10:00.
private let refDate: Date = {
    var c = DateComponents()
    c.year = 2026; c.month = 11; c.day = 12; c.hour = 10; c.minute = 0
    return Fmt.calendar.date(from: c)!
}()

private func ymdhm(_ d: Date?) -> [Int] {
    guard let d else { return [] }
    let c = Fmt.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
    return [c.year!, c.month!, c.day!, c.hour!, c.minute!]
}

final class InterpreterTests: XCTestCase {
    let interpreter = RuleBasedInterpreter()
    var ctx = InterpreterContext(now: refDate)

    private func draft(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> AssistantDraft? {
        if case .draft(let d) = interpreter.interpret(text, context: ctx) { return d }
        XCTFail("Esperava rascunho para: \(text) — obtido \(interpreter.interpret(text, context: ctx))", file: file, line: line)
        return nil
    }

    func testExpenseLunch() {
        let d = draft("Gastei 35 reais no almoço")
        XCTAssertEqual(d?.kind, .expense)
        XCTAssertEqual(d?.amount, 35)
        XCTAssertEqual(d?.financeCategory, .alimentacao)
        XCTAssertEqual(d?.title, "Almoço")
    }

    func testExpenseWithDecimalAndCurrencySymbol() {
        let d = draft("Paguei R$ 1.234,56 de aluguel")
        XCTAssertEqual(d?.amount ?? 0, 1234.56, accuracy: 0.001)
        XCTAssertEqual(d?.financeCategory, .moradia)
    }

    func testExpenseUber() {
        let d = draft("gastei 25 reais de uber ontem")
        XCTAssertEqual(d?.financeCategory, .transporte)
        XCTAssertEqual(ymdhm(d?.date).prefix(3), [2026, 11, 11])
    }

    func testCardInstallments() {
        ctx.cardNames = ["Nubank"]
        let d = draft("Comprei um tênis por 300 reais no cartão em 3x")
        XCTAssertEqual(d?.kind, .expense)
        XCTAssertEqual(d?.amount, 300)
        XCTAssertEqual(d?.installments, 3)
        XCTAssertEqual(d?.cardName, "Nubank")
        XCTAssertEqual(d?.financeCategory, .compras)
    }

    func testExamNextThursday() {
        let d = draft("Tenho prova de cálculo na próxima quinta às 19h")
        XCTAssertEqual(d?.kind, .event)
        XCTAssertEqual(d?.eventCategory, .prova)
        XCTAssertEqual(d?.subjectName, "Cálculo")
        XCTAssertEqual(d?.subjectExists, false)
        XCTAssertEqual(d?.hasTime, true)
        XCTAssertEqual(ymdhm(d?.date), [2026, 11, 19, 19, 0])
        XCTAssertEqual(d?.title, "Prova de Cálculo")
    }

    func testExamMatchesExistingSubject() {
        ctx.subjectNames = ["Eletrônica Digital"]
        let d = draft("Tenho prova de eletrônica digital dia 20 às 19h")
        XCTAssertEqual(d?.subjectName, "Eletrônica Digital")
        XCTAssertEqual(d?.subjectExists, true)
        XCTAssertEqual(ymdhm(d?.date), [2026, 11, 20, 19, 0])
    }

    func testBillInternet() {
        let d = draft("Minha conta de internet vence dia 15 e custa 120 reais")
        XCTAssertEqual(d?.kind, .bill)
        XCTAssertEqual(d?.amount, 120)
        XCTAssertEqual(d?.title, "Internet")
        XCTAssertEqual(d?.financeCategory, .internet)
        XCTAssertEqual(d?.recurrence, .mensal)
        XCTAssertEqual(ymdhm(d?.date).prefix(3), [2026, 11, 15])
    }

    func testWeight() {
        let d = draft("Meu peso atual é 77,5 kg")
        XCTAssertEqual(d?.kind, .body)
        XCTAssertEqual(d?.weight, 77.5)
    }

    func testWorkout() {
        let d = draft("Hoje fiz treino de peito e tríceps")
        XCTAssertEqual(d?.kind, .workout)
        XCTAssertEqual(d?.muscleGroups, ["Peito", "Tríceps"])
        XCTAssertEqual(d?.title, "Peito e Tríceps")
    }

    func testWorkoutLegs() {
        let d = draft("Hoje treinei pernas")
        XCTAssertEqual(d?.kind, .workout)
        XCTAssertEqual(d?.muscleGroups, ["Pernas"])
    }

    func testStudyTask() {
        let d = draft("Preciso estudar segurança da informação amanhã")
        XCTAssertEqual(d?.kind, .event)
        XCTAssertEqual(d?.eventCategory, .estudo)
        XCTAssertEqual(d?.title, "Estudar Segurança da informação")
        XCTAssertEqual(ymdhm(d?.date).prefix(3), [2026, 11, 13])
        XCTAssertEqual(d?.hasTime, false)
    }

    func testReviewTask() {
        let d = draft("Preciso revisar redes amanhã")
        XCTAssertEqual(d?.eventCategory, .estudo)
        XCTAssertEqual(d?.title, "Revisar Redes")
    }

    func testGroceries() {
        let d = draft("Comprei ovos, arroz, frango e batata no mercado")
        XCTAssertEqual(d?.kind, .groceries)
        XCTAssertEqual(d?.items.map(\.name), ["Ovos", "Arroz", "Frango", "Batata"])
        XCTAssertNil(d?.amount)
    }

    func testGroceriesWithQuantities() {
        let items = interpreter.splitItems("2 kg de frango, uma dúzia de ovos e 1 litro de leite")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0], GroceryItem(name: "Frango", quantity: 2, unit: "kg"))
        XCTAssertEqual(items[1], GroceryItem(name: "Ovos", quantity: 12, unit: "un"))
        XCTAssertEqual(items[2].unit, "L")
    }

    func testStudySession() {
        let d = draft("Estudei 1h30 de português")
        XCTAssertEqual(d?.kind, .studySession)
        XCTAssertEqual(d?.minutes, 90)
        XCTAssertEqual(d?.subjectName, "Português")
    }

    func testIncome() {
        let d = draft("Recebi 2500 reais de salário")
        XCTAssertEqual(d?.kind, .income)
        XCTAssertEqual(d?.amount, 2500)
        XCTAssertEqual(d?.financeCategory, .salario)
    }

    func testAsksForMissingAmountAndCompletes() {
        let result = interpreter.interpret("Gastei no mercado", context: ctx)
        guard case .needsInfo(let d, let field, _) = result else { return XCTFail("deveria perguntar o valor") }
        XCTAssertEqual(field, .amount)
        guard case .draft(let done) = interpreter.complete(d, missing: field, answer: "50", context: ctx) else {
            return XCTFail("deveria completar")
        }
        XCTAssertEqual(done.amount, 50)
    }

    func testAsksForMissingDateAndCompletes() {
        let result = interpreter.interpret("Tenho prova de física", context: ctx)
        guard case .needsInfo(let d, let field, _) = result else { return XCTFail("deveria perguntar a data") }
        XCTAssertEqual(field, .date)
        guard case .draft(let done) = interpreter.complete(d, missing: .date, answer: "dia 20", context: ctx) else {
            return XCTFail("deveria completar")
        }
        XCTAssertEqual(ymdhm(done.date).prefix(3), [2026, 11, 20])
    }

    func testNotUnderstood() {
        if case .notUnderstood = interpreter.interpret("olá tudo bem", context: ctx) { } else { XCTFail() }
    }

    func testHabitCheck() {
        ctx.habitNames = ["Meditar"]
        let d = draft("Hoje fiz meditar")
        XCTAssertEqual(d?.kind, .habitCheck)
        XCTAssertEqual(d?.habitName, "Meditar")
    }
}

final class DateParserTests: XCTestCase {
    private func parse(_ s: String, past: Bool = false) -> DateParseResult {
        var t = NormalizedText(s)
        return PTDateParser(now: refDate).parse(&t, preferPast: past)
    }

    func testTomorrowAt8() {
        XCTAssertEqual(ymdhm(parse("amanhã às 8h").date), [2026, 11, 13, 8, 0])
    }

    func testDayAlreadyPassedGoesToNextMonth() {
        XCTAssertEqual(ymdhm(parse("dia 5").date).prefix(3), [2026, 12, 5])
    }

    func testDayPastPreference() {
        XCTAssertEqual(ymdhm(parse("dia 20", past: true).date).prefix(3), [2026, 10, 20])
    }

    func testSlashDate() {
        XCTAssertEqual(ymdhm(parse("20/11").date).prefix(3), [2026, 11, 20])
        XCTAssertEqual(ymdhm(parse("10/01/2027 14:30").date), [2027, 1, 10, 14, 30])
    }

    func testWeekday() {
        XCTAssertEqual(ymdhm(parse("sexta").date).prefix(3), [2026, 11, 13])
        XCTAssertEqual(ymdhm(parse("segunda que vem").date).prefix(3), [2026, 11, 16])
        XCTAssertEqual(ymdhm(parse("na quinta").date).prefix(3), [2026, 11, 12])
        XCTAssertEqual(ymdhm(parse("próxima quinta").date).prefix(3), [2026, 11, 19])
    }

    func testMonthName() {
        XCTAssertEqual(ymdhm(parse("15 de dezembro às 7 da noite").date), [2026, 12, 15, 19, 0])
    }

    func testInvalidDateIsRejected() {
        XCTAssertNil(parse("31/02").date)
    }

    func testNoDate() {
        XCTAssertNil(parse("comprar pão").date)
    }

    func testTimeOnlyInThePastMovesToTomorrow() {
        XCTAssertEqual(ymdhm(parse("às 8h").date), [2026, 11, 13, 8, 0])
    }
}

final class NumberParsingTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(NumberParsing.parse("1.234,56", money: true), 1234.56)
        XCTAssertEqual(NumberParsing.parse("77,5", money: false), 77.5)
        XCTAssertEqual(NumberParsing.parse("1.200", money: true), 1200)
        XCTAssertEqual(NumberParsing.parse("77.5", money: false), 77.5)
        XCTAssertEqual(Fmt.parseDecimal("R$ 35,90"), 35.9)
    }

    func testCategoryGuesser() {
        XCTAssertEqual(CategoryGuesser.expense("uber pro trabalho"), .transporte)
        XCTAssertEqual(CategoryGuesser.expense("netflix"), .assinaturas)
        XCTAssertEqual(CategoryGuesser.expense("farmacia"), .saude)
        XCTAssertEqual(CategoryGuesser.expense("coisa aleatoria"), .outros)
        XCTAssertEqual(CategoryGuesser.income("freela de design"), .rendaExtra)
    }
}
