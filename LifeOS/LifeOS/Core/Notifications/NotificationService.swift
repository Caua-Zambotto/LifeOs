import Foundation
import UserNotifications
import SwiftData

/// Notificações 100% locais (UNUserNotificationCenter). Sem push, sem servidor.
/// Os textos evitam valores financeiros, pois aparecem na tela de bloqueio.
enum NotificationSettings {
    static func isEnabled(_ c: NotificationCategory) -> Bool {
        UserDefaults.standard.object(forKey: "notif.enabled.\(c.rawValue)") as? Bool ?? true
    }
    static func setEnabled(_ c: NotificationCategory, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: "notif.enabled.\(c.rawValue)")
    }
    /// Antecedência (minutos) usada como padrão para novos registros e para contas/metas.
    static func lead(_ c: NotificationCategory) -> Int {
        UserDefaults.standard.object(forKey: "notif.lead.\(c.rawValue)") as? Int ?? c.defaultLead
    }
    static func setLead(_ c: NotificationCategory, _ value: Int) {
        UserDefaults.standard.set(value, forKey: "notif.lead.\(c.rawValue)")
    }
    /// Horário padrão para lembretes sem horário definido (contas, revisões...).
    static var defaultHour: Int {
        get { UserDefaults.standard.object(forKey: "notif.defaultHour") as? Int ?? 8 }
        set { UserDefaults.standard.set(newValue, forKey: "notif.defaultHour") }
    }
    static let leadOptions: [LeadOption] = [
        LeadOption(label: "No horário", minutes: 0), LeadOption(label: "15 min antes", minutes: 15),
        LeadOption(label: "30 min antes", minutes: 30), LeadOption(label: "1 hora antes", minutes: 60),
        LeadOption(label: "2 horas antes", minutes: 120), LeadOption(label: "1 dia antes", minutes: 1440),
        LeadOption(label: "2 dias antes", minutes: 2880), LeadOption(label: "1 semana antes", minutes: 10080),
    ]
}

struct LeadOption: Hashable, Identifiable {
    let label: String
    let minutes: Int
    var id: Int { minutes }
}

final class NotificationService {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Agenda uma notificação. Se `recurrence` != nenhuma, repete pelo calendário.
    func schedule(id: String, title: String, body: String, fireDate: Date,
                  recurrence: Recurrence = .nenhuma, category: NotificationCategory) {
        guard NotificationSettings.isEnabled(category) else { cancel([id]); return }
        let cal = Calendar.current
        let components: Set<Calendar.Component>
        switch recurrence {
        case .nenhuma:
            guard fireDate > Date() else { cancel([id]); return }
            components = [.year, .month, .day, .hour, .minute]
        case .diaria: components = [.hour, .minute]
        case .semanal: components = [.weekday, .hour, .minute]
        case .mensal: components = [.day, .hour, .minute]
        case .anual: components = [.month, .day, .hour, .minute]
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = category.rawValue
        let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents(components, from: fireDate),
                                                    repeats: recurrence != .nenhuma)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func notifyNow(id: String, title: String, body: String, category: NotificationCategory) {
        guard NotificationSettings.isEnabled(category) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel(_ ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }
}

/// Converte registros do app em notificações. Chamado ao salvar/excluir registros.
enum NotificationScheduler {
    private static var service: NotificationService { .shared }

    private static func atDefaultHour(_ date: Date) -> Date {
        Calendar.current.date(bySettingHour: NotificationSettings.defaultHour, minute: 0, second: 0, of: date) ?? date
    }

    // MARK: Agenda

    static func schedule(_ event: AgendaEvent) {
        let id = "event.\(event.id.uuidString)"
        guard event.notify, !event.isDone else { service.cancel([id]); return }
        let base = event.isAllDay ? atDefaultHour(event.start) : event.start
        let fire = base.addingTimeInterval(-Double(event.leadMinutes) * 60)
        let when = event.isAllDay ? Fmt.dayMonth(event.start) : Fmt.dateTime(event.start)
        service.schedule(id: id, title: "\(event.category.label): \(event.title)", body: when,
                         fireDate: fire, recurrence: event.recurrence, category: event.category.notificationCategory)
    }

    static func cancel(event: AgendaEvent) { service.cancel(["event.\(event.id.uuidString)"]) }

    // MARK: Contas

    static func schedule(_ entry: RecurringEntry) {
        let id = "bill.\(entry.id.uuidString)"
        guard entry.notify, entry.isActive, entry.kind == .despesa else { service.cancel([id]); return }
        let lead = NotificationSettings.lead(.contas)
        let fire = atDefaultHour(entry.dueDate).addingTimeInterval(-Double(lead) * 60)
        // Para recorrentes, o próximo vencimento é reprogramado ao marcar como pago.
        service.schedule(id: id, title: "Conta a vencer: \(entry.title)",
                         body: "Vencimento \(Fmt.relativeDay(entry.dueDate)). Abra o LifeOS para ver os detalhes.",
                         fireDate: fire, category: .contas)
    }

    static func cancel(entry: RecurringEntry) { service.cancel(["bill.\(entry.id.uuidString)"]) }

    // MARK: Treinos

    static func schedule(_ plan: WorkoutPlan) {
        let ids = (1...7).map { "workout.\(plan.id.uuidString).\($0)" }
        service.cancel(ids)
        guard let time = plan.reminderTime else { return }
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: time)
        for wd in plan.weekdays {
            var comps = DateComponents()
            comps.weekday = wd; comps.hour = hm.hour; comps.minute = hm.minute
            guard let next = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) else { continue }
            service.schedule(id: "workout.\(plan.id.uuidString).\(wd)", title: "Hora do treino",
                             body: plan.name, fireDate: next, recurrence: .semanal, category: .treinos)
        }
    }

    static func cancel(plan: WorkoutPlan) {
        service.cancel((1...7).map { "workout.\(plan.id.uuidString).\($0)" })
    }

    // MARK: Hábitos

    static func schedule(_ habit: Habit) {
        let ids = (0...7).map { "habit.\(habit.id.uuidString).\($0)" }
        service.cancel(ids)
        guard let time = habit.reminderTime, !habit.isArchived else { return }
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: time)
        if habit.weekdays.isEmpty {
            var comps = DateComponents(); comps.hour = hm.hour; comps.minute = hm.minute
            if let next = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) {
                service.schedule(id: "habit.\(habit.id.uuidString).0", title: "Hábito",
                                 body: habit.name, fireDate: next, recurrence: .diaria, category: .habitos)
            }
        } else {
            for wd in habit.weekdays {
                var comps = DateComponents(); comps.weekday = wd; comps.hour = hm.hour; comps.minute = hm.minute
                if let next = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) {
                    service.schedule(id: "habit.\(habit.id.uuidString).\(wd)", title: "Hábito",
                                     body: habit.name, fireDate: next, recurrence: .semanal, category: .habitos)
                }
            }
        }
    }

    static func cancel(habit: Habit) { service.cancel((0...7).map { "habit.\(habit.id.uuidString).\($0)" }) }

    // MARK: Revisões

    static func schedule(_ topic: StudyTopic) {
        let id = "review.\(topic.id.uuidString)"
        guard let next = topic.nextReview else { service.cancel([id]); return }
        service.schedule(id: id, title: "Revisão de estudo", body: topic.title,
                         fireDate: atDefaultHour(next), category: .revisoes)
    }

    // MARK: Metas

    static func schedule(_ goal: PersonalGoal) {
        let id = "goal.\(goal.id.uuidString)"
        guard let deadline = goal.deadline, !goal.isCompleted else { service.cancel([id]); return }
        let fire = atDefaultHour(deadline).addingTimeInterval(-Double(NotificationSettings.lead(.metas)) * 60)
        service.schedule(id: id, title: "Prazo de meta", body: goal.title, fireDate: fire, category: .metas)
    }

    // MARK: Concursos

    static func schedule(_ contest: Contest) {
        let examID = "contest.exam.\(contest.id.uuidString)"
        let regID = "contest.reg.\(contest.id.uuidString)"
        if let exam = contest.examDate {
            let fire = atDefaultHour(exam).addingTimeInterval(-Double(NotificationSettings.lead(.provas)) * 60)
            service.schedule(id: examID, title: "Prova de concurso", body: contest.displayName, fireDate: fire, category: .provas)
        } else { service.cancel([examID]) }
        if let reg = contest.registrationEnd {
            let fire = atDefaultHour(reg).addingTimeInterval(-86400)
            service.schedule(id: regID, title: "Inscrições terminam amanhã", body: contest.displayName, fireDate: fire, category: .provas)
        } else { service.cancel([regID]) }
    }

    static func cancel(contest: Contest) {
        service.cancel(["contest.exam.\(contest.id.uuidString)", "contest.reg.\(contest.id.uuidString)"])
    }

    /// Reprograma tudo (após restauração de backup ou mudança de configuração).
    /// O iOS mantém no máximo 64 notificações pendentes; priorizamos as mais próximas.
    @MainActor
    static func rescheduleAll(context: ModelContext) {
        service.cancelAll()
        let now = Date()
        let events = ((try? context.fetch(FetchDescriptor<AgendaEvent>())) ?? [])
            .filter { $0.notify && !$0.isDone && ($0.recurrence != .nenhuma || $0.start > now) }
            .sorted { $0.start < $1.start }
            .prefix(30)
        events.forEach(schedule)
        ((try? context.fetch(FetchDescriptor<RecurringEntry>())) ?? [])
            .filter { $0.isActive && $0.kind == .despesa }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(10)
            .forEach(schedule)
        ((try? context.fetch(FetchDescriptor<WorkoutPlan>())) ?? []).forEach(schedule)
        ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).filter { !$0.isArchived }.prefix(6).forEach(schedule)
        ((try? context.fetch(FetchDescriptor<StudyTopic>())) ?? [])
            .filter { ($0.nextReview ?? .distantPast) > now }
            .sorted { ($0.nextReview ?? now) < ($1.nextReview ?? now) }
            .prefix(5)
            .forEach(schedule)
        ((try? context.fetch(FetchDescriptor<PersonalGoal>())) ?? []).filter { !$0.isCompleted }.prefix(3).forEach(schedule)
        ((try? context.fetch(FetchDescriptor<Contest>())) ?? []).prefix(3).forEach(schedule)
    }
}
