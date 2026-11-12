import Foundation
import SwiftData

/// Grava rascunhos confirmados na área correta e permite desfazer.
/// Cada registro é criado uma única vez e referenciado pelas demais áreas
/// (ex.: a prova é um AgendaEvent ligado à matéria, aparecendo na agenda e na faculdade).
@MainActor
enum AssistantExecutor {

    struct Outcome {
        var refs: [String]
        var message: String
    }

    static func save(_ d: AssistantDraft, context: ModelContext) throws -> Outcome {
        var refs: [String] = []
        var message = "Pronto! Registro salvo."

        switch d.kind {
        case .expense, .income:
            let card = d.cardName.flatMap { name in
                (try? context.fetch(FetchDescriptor<CreditCard>()))?.first { $0.name == name }
            }
            let created = FinanceService.addTransaction(
                title: d.title, amount: d.amount ?? 0, kind: d.kind == .income ? .receita : .despesa,
                category: d.financeCategory, date: d.date ?? Date(), card: card,
                installments: d.installments, context: context)
            refs = created.map { "transaction:\($0.id.uuidString)" }
            message = d.kind == .income ? "Receita registrada em Finanças." : "Despesa registrada em Finanças."
            if d.kind == .expense { FinanceService.checkBudgetAlert(context: context) }

        case .bill:
            let entry = RecurringEntry(title: d.title, amount: d.amount ?? 0, kind: .despesa,
                                       category: d.financeCategory, dueDate: d.date ?? Date(), recurrence: d.recurrence)
            context.insert(entry)
            NotificationScheduler.schedule(entry)
            refs = ["recurring:\(entry.id.uuidString)"]
            message = "Conta adicionada. Vou avisar antes do vencimento."

        case .event:
            let event = AgendaEvent(title: d.title, start: d.date ?? Date(), category: d.eventCategory)
            event.isAllDay = !d.hasTime
            event.priority = d.priority
            event.details = d.sourceText
            if let name = d.subjectName {
                if let subject = findSubject(named: name, context: context) {
                    event.subject = subject
                } else if !d.subjectExists, d.eventCategory == .prova || d.eventCategory == .trabalho {
                    let subject = Subject(name: name)
                    context.insert(subject)
                    event.subject = subject
                    refs.append("subject:\(subject.id.uuidString)")
                }
            }
            context.insert(event)
            NotificationScheduler.schedule(event)
            refs.insert("event:\(event.id.uuidString)", at: 0)
            message = event.subject != nil
                ? "Salvo na Agenda e na matéria \(event.subject!.name)."
                : "Salvo na Agenda."

        case .studySession:
            let session = StudySession(date: d.date ?? Date(), minutes: d.minutes ?? 0, note: d.subjectName ?? "")
            if let name = d.subjectName {
                if let s = findSubject(named: name, context: context) { session.subject = s }
                else if let cs = findContestSubject(named: name, context: context) {
                    session.contestSubject = cs
                    session.contest = cs.contest
                }
            }
            context.insert(session)
            refs = ["study:\(session.id.uuidString)"]
            message = "Sessão de \(Fmt.duration(minutes: session.minutes)) registrada."

        case .body:
            let m = BodyMeasurement(date: d.date ?? Date())
            m.weight = d.weight
            m.waist = d.measurements["waist"]
            m.arm = d.measurements["arm"]
            m.chest = d.measurements["chest"]
            m.leg = d.measurements["leg"]
            m.hip = d.measurements["hip"]
            m.bodyFat = d.measurements["bodyFat"]
            context.insert(m)
            refs = ["body:\(m.id.uuidString)"]
            message = "Medidas registradas. O gráfico de evolução foi atualizado."

        case .workout:
            let session = WorkoutSession(date: d.date ?? Date(), title: d.title)
            session.muscleGroups = d.muscleGroups
            session.durationMinutes = d.minutes ?? 0
            // Se existir uma divisão de treino correspondente, copia os exercícios com as cargas atuais.
            if let plan = matchingPlan(for: d, context: context) {
                session.planID = plan.id
                for (i, ex) in plan.sortedExercises.enumerated() {
                    let entry = ExerciseEntry(name: ex.name, sets: ex.sets, reps: ex.reps, load: ex.load, order: i)
                    session.entries.append(entry)
                }
            }
            context.insert(session)
            refs = ["workout:\(session.id.uuidString)"]
            message = session.entries.isEmpty
                ? "Treino registrado no histórico."
                : "Treino registrado com os exercícios da divisão \"\(session.title)\". Ajuste as cargas em Treinos."

        case .groceries:
            let existing = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
            for item in d.items {
                if let same = existing.first(where: { $0.name.folded == item.name.folded && $0.unit == item.unit }) {
                    same.quantity += item.quantity
                    refs.append("pantryAdd:\(same.id.uuidString):\(item.quantity)")
                } else {
                    let p = PantryItem(name: item.name, quantity: item.quantity, unit: item.unit)
                    context.insert(p)
                    refs.append("pantry:\(p.id.uuidString)")
                }
            }
            if let amount = d.amount, amount > 0 {
                let tx = FinanceService.addTransaction(title: "Mercado", amount: amount, kind: .despesa,
                                                       category: .alimentacao, date: d.date ?? Date(), card: nil,
                                                       installments: 1, context: context)
                refs += tx.map { "transaction:\($0.id.uuidString)" }
            }
            message = "\(d.items.count) item(ns) no estoque." + (d.amount != nil ? " Gasto lançado em Finanças." : "")
                + " Veja sugestões de receitas em Alimentação."

        case .habitCheck:
            let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            if let habit = habits.first(where: { $0.name == d.habitName }) {
                let day = d.date ?? Date()
                if !habit.isDone(on: day) {
                    let c = HabitCheckin(date: day)
                    habit.checkins.append(c)
                    refs = ["checkin:\(c.id.uuidString)"]
                }
                message = "Hábito \"\(habit.name)\" marcado."
            }
        }
        try context.save()
        return Outcome(refs: refs, message: message)
    }

    /// Desfaz os registros criados por uma mensagem do assistente.
    static func undo(refs: [String], context: ModelContext) throws {
        for ref in refs {
            let parts = ref.split(separator: ":").map(String.init)
            guard parts.count >= 2, let id = UUID(uuidString: parts[1]) else { continue }
            switch parts[0] {
            case "transaction":
                if let o = fetch(FinanceTransaction.self, id, context) { context.delete(o) }
            case "recurring":
                if let o = fetch(RecurringEntry.self, id, context) { NotificationScheduler.cancel(entry: o); context.delete(o) }
            case "event":
                if let o = fetch(AgendaEvent.self, id, context) { NotificationScheduler.cancel(event: o); context.delete(o) }
            case "subject":
                if let o = fetch(Subject.self, id, context), o.events.isEmpty || o.events.allSatisfy({ refs.contains("event:\($0.id.uuidString)") }) {
                    context.delete(o)
                }
            case "study":
                if let o = fetch(StudySession.self, id, context) { context.delete(o) }
            case "body":
                if let o = fetch(BodyMeasurement.self, id, context) { context.delete(o) }
            case "workout":
                if let o = fetch(WorkoutSession.self, id, context) { context.delete(o) }
            case "pantry":
                if let o = fetch(PantryItem.self, id, context) { context.delete(o) }
            case "pantryAdd":
                if let o = fetch(PantryItem.self, id, context), parts.count >= 3, let q = Double(parts[2]) {
                    o.quantity = max(0, o.quantity - q)
                    if o.quantity == 0 { context.delete(o) }
                }
            case "checkin":
                if let o = fetch(HabitCheckin.self, id, context) { context.delete(o) }
            default:
                break
            }
        }
        try context.save()
    }

    // MARK: - Busca

    static func fetch<T: PersistentModel>(_ type: T.Type, _ id: UUID, _ context: ModelContext) -> T? {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return all.first { model in
            (model as? any IdentifiableModel)?.modelID == id
        }
    }

    static func findSubject(named name: String, context: ModelContext) -> Subject? {
        let all = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        guard let match = RuleBasedInterpreter.bestMatch(name, in: all.map(\.name)) else { return nil }
        return all.first { $0.name == match }
    }

    static func findContestSubject(named name: String, context: ModelContext) -> ContestSubject? {
        let all = (try? context.fetch(FetchDescriptor<ContestSubject>())) ?? []
        guard let match = RuleBasedInterpreter.bestMatch(name, in: all.map(\.name)) else { return nil }
        return all.first { $0.name == match }
    }

    private static func matchingPlan(for d: AssistantDraft, context: ModelContext) -> WorkoutPlan? {
        let plans = (try? context.fetch(FetchDescriptor<WorkoutPlan>())) ?? []
        let groups = Set(d.muscleGroups.map(\.folded))
        guard !groups.isEmpty else { return nil }
        return plans.first { plan in
            let name = plan.name.folded
            return groups.allSatisfy { name.contains($0) }
        }
    }

    /// Contexto atualizado para o interpretador.
    static func interpreterContext(_ context: ModelContext) -> InterpreterContext {
        InterpreterContext(
            subjectNames: ((try? context.fetch(FetchDescriptor<Subject>())) ?? []).map(\.name),
            contestSubjectNames: ((try? context.fetch(FetchDescriptor<ContestSubject>())) ?? []).map(\.name),
            habitNames: ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).filter { !$0.isArchived }.map(\.name),
            cardNames: ((try? context.fetch(FetchDescriptor<CreditCard>())) ?? []).map(\.name),
            now: Date()
        )
    }
}

/// Permite buscar qualquer modelo pelo `id` de forma genérica.
protocol IdentifiableModel { var modelID: UUID { get } }
extension FinanceTransaction: IdentifiableModel { var modelID: UUID { id } }
extension RecurringEntry: IdentifiableModel { var modelID: UUID { id } }
extension AgendaEvent: IdentifiableModel { var modelID: UUID { id } }
extension Subject: IdentifiableModel { var modelID: UUID { id } }
extension StudySession: IdentifiableModel { var modelID: UUID { id } }
extension BodyMeasurement: IdentifiableModel { var modelID: UUID { id } }
extension WorkoutSession: IdentifiableModel { var modelID: UUID { id } }
extension PantryItem: IdentifiableModel { var modelID: UUID { id } }
extension HabitCheckin: IdentifiableModel { var modelID: UUID { id } }
