import SwiftUI
import SwiftData
import Charts

/// Blocos da Home (o usuário pode reordenar e ocultar).
enum HomeSection: String, CaseIterable, Identifiable {
    case today, indicators, workout, finance, bills, upcoming, growth, productivity
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: "Hoje"
        case .indicators: "Estudos, editais e treino"
        case .workout: "Próximo treino"
        case .finance: "Resumo financeiro do mês"
        case .bills: "Contas a vencer"
        case .upcoming: "Próximas atividades"
        case .growth: "Metas e hábitos"
        case .productivity: "Produtividade da semana"
        }
    }
    static var defaultOrder: String { allCases.map(\.rawValue).joined(separator: ",") }
}

/// Números da Home, calculados a partir dos dados reais dos módulos.
struct HomeStats {
    var todayItems: [AgendaOccurrence] = []
    var billsToday: [RecurringEntry] = []
    var studyMinutesWeek = 0
    var studyGoal = 600
    var collegeProgress = 0.0
    var collegeTopics = 0
    var contestProgress = 0.0
    var contestTopics = 0
    var workoutsWeek = 0
    var workoutGoal = 4
    var nextWorkout: (plan: WorkoutPlan, day: Date)?
    var monthIncome = 0.0
    var monthSpending = 0.0
    var balance = 0.0
    var topCategories: [(category: FinanceCategory, total: Double)] = []
    var weekRemaining = 0.0
    var overBudget = false
    var billsSoon: [RecurringEntry] = []
    var upcoming: [(title: String, date: Date, icon: String, color: Color, tab: AppState.Tab)] = []
    var tasksDone = 0
    var tasksTotal = 0
    var habitRate: Double?
    var reviewsDue = 0

    var studyRate: Double { studyGoal > 0 ? min(1, Double(studyMinutesWeek) / Double(studyGoal)) : 0 }
    var workoutRate: Double { workoutGoal > 0 ? min(1, Double(workoutsWeek) / Double(workoutGoal)) : 0 }
    var taskRate: Double? { tasksTotal > 0 ? Double(tasksDone) / Double(tasksTotal) : nil }
    /// Média dos indicadores disponíveis.
    var productivity: Double {
        let parts = [Optional(studyRate), Optional(workoutRate), taskRate, habitRate].compactMap { $0 }
        return parts.isEmpty ? 0 : parts.reduce(0, +) / Double(parts.count)
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @AppStorage("home.sections") private var sectionsRaw = HomeSection.defaultOrder
    @Query(sort: \AgendaEvent.start) private var events: [AgendaEvent]
    @Query(sort: \FinanceTransaction.date) private var transactions: [FinanceTransaction]
    @Query(sort: \RecurringEntry.dueDate) private var recurring: [RecurringEntry]
    @Query private var debts: [Debt]
    @Query private var cards: [CreditCard]
    @Query private var topics: [StudyTopic]
    @Query private var sessions: [StudySession]
    @Query(sort: \WorkoutPlan.order) private var plans: [WorkoutPlan]
    @Query private var workouts: [WorkoutSession]
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \PersonalGoal.createdAt) private var goals: [PersonalGoal]
    @Query private var contests: [Contest]
    @Query private var profiles: [UserProfile]
    @State private var editingEvent: AgendaEvent?
    @State private var customizing = false

    private var sections: [HomeSection] {
        sectionsRaw.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) }
    }

    var body: some View {
        let stats = computeStats()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    assistantPill
                    ForEach(sections) { section in
                        sectionView(section, stats)
                    }
                    Button { customizing = true } label: {
                        Label("Personalizar Home", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .growth: GrowthView()
                case .reports: ReportsView()
                }
            }
            .sheet(item: $editingEvent) { EventEditorView(event: $0) }
            .sheet(isPresented: $customizing) { DashboardCustomizeView() }
            .animation(.snappy, value: sectionsRaw)
        }
    }

    enum HomeRoute: Hashable { case growth, reports }

    // MARK: Cabeçalho

    private var header: some View {
        let name = profiles.first?.name ?? ""
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.fullDate(Date()))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(name.isEmpty ? Fmt.greeting() : "\(Fmt.greeting()), \(name)")
                    .font(.largeTitle.bold())
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                circleButton("plus", "Adicionar") { appState.showQuickAdd = true }
                circleButton("gearshape", "Perfil e ajustes") { appState.showSettings = true }
            }
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private func circleButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Theme.card, in: Circle())
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var assistantPill: some View {
        Button { appState.openAssistant() } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.Module.assistant.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Registrar conversando").font(.subheadline.weight(.semibold))
                    Text("\"Gastei 35 no almoço\", \"Tenho prova sexta às 19h\"…")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Seções

    @ViewBuilder
    private func sectionView(_ section: HomeSection, _ s: HomeStats) -> some View {
        switch section {
        case .today: todayCard(s)
        case .indicators: indicators(s)
        case .workout: workoutCard(s)
        case .finance: financeCard(s)
        case .bills: if !s.billsSoon.isEmpty { billsCard(s) }
        case .upcoming: upcomingCard(s)
        case .growth: growthCard()
        case .productivity: productivityCard(s)
        }
    }

    private func moduleHeader(_ title: String, _ icon: String, _ tab: AppState.Tab?, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(tab?.module.tint ?? Theme.accent)
            Text(title).font(.headline)
            Spacer()
            if let detail { Text(detail).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            if tab != nil { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }
    }

    private func go(_ tab: AppState.Tab) { appState.selectedTab = tab }

    private func todayCard(_ s: HomeStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { go(.calendar) } label: {
                moduleHeader("Hoje", "calendar", .calendar, detail: s.todayItems.isEmpty ? nil : "\(s.todayItems.count) item(ns)")
            }
            .buttonStyle(.plain)
            if s.todayItems.isEmpty && s.billsToday.isEmpty {
                Text("Nenhum compromisso hoje. Aproveite para adiantar os estudos.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(s.todayItems.prefix(4)) { occ in
                HStack(spacing: 12) {
                    Button {
                        guard occ.event.recurrence == .nenhuma else { return }
                        occ.event.isDone.toggle()
                        NotificationScheduler.schedule(occ.event)
                        context.saveQuietly()
                    } label: {
                        Image(systemName: occ.event.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(occ.event.category.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(occ.event.isDone ? "Marcar como pendente" : "Concluir")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(occ.event.title).font(.subheadline.weight(.semibold)).strikethrough(occ.event.isDone).lineLimit(1)
                        Text(occ.event.isAllDay ? occ.event.category.label : "\(Fmt.time(occ.date)) · \(occ.event.category.label)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if occ.event.priority == .alta { Image(systemName: "flag.fill").font(.caption).foregroundStyle(.red) }
                }
                .contentShape(Rectangle())
                .onTapGesture { editingEvent = occ.event }
            }
            if s.todayItems.count > 4 {
                Button("Ver mais \(s.todayItems.count - 4) no calendário") { go(.calendar) }.font(.caption.weight(.semibold))
            }
            ForEach(s.billsToday) { b in
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill").foregroundStyle(.orange).frame(width: 24)
                    Text("Vence hoje: \(b.title)").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Fmt.currency(b.amount)).font(.subheadline).monospacedDigit()
                }
            }
        }
        .card()
    }

    private func indicators(_ s: HomeStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ringTile(title: "Estudo na semana", value: Fmt.duration(minutes: s.studyMinutesWeek),
                     detail: "meta \(Fmt.duration(minutes: s.studyGoal))", progress: s.studyRate, tab: .studies)
            ringTile(title: "Faculdade", value: Fmt.percent(s.collegeProgress),
                     detail: s.collegeTopics == 0 ? "sem conteúdos" : "\(s.collegeTopics) conteúdos", progress: s.collegeProgress, tab: .studies)
            ringTile(title: "Editais", value: Fmt.percent(s.contestProgress),
                     detail: s.contestTopics == 0 ? "sem conteúdos" : "\(s.contestTopics) conteúdos", progress: s.contestProgress, tab: .contests)
            ringTile(title: "Treinos na semana", value: "\(s.workoutsWeek)/\(s.workoutGoal)",
                     detail: s.workoutsWeek >= s.workoutGoal ? "meta batida" : "faltam \(max(0, s.workoutGoal - s.workoutsWeek))",
                     progress: s.workoutRate, tab: .training)
        }
    }

    private func ringTile(title: String, value: String, detail: String, progress: Double, tab: AppState.Tab) -> some View {
        Button { go(tab) } label: {
            HStack(spacing: 12) {
                RingProgress(value: progress, tint: tab.module.tint, lineWidth: 6)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func workoutCard(_ s: HomeStats) -> some View {
        Button { go(.training) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Próximo treino").font(.subheadline.weight(.semibold)).opacity(0.9)
                    if let next = s.nextWorkout {
                        Text(next.plan.name).font(.title2.bold()).lineLimit(1)
                        Text("\(Fmt.relativeDay(next.day).capitalizedFirst) · \(next.plan.exercises.count) exercícios")
                            .font(.subheadline).opacity(0.9)
                    } else {
                        Text("Monte sua ficha").font(.title3.bold())
                        Text("Toque para criar seus treinos").font(.subheadline).opacity(0.9)
                    }
                }
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 40))
            }
            .gradientCard(.fitness)
        }
        .buttonStyle(.plain)
    }

    private func financeCard(_ s: HomeStats) -> some View {
        Button { go(.finance) } label: {
            VStack(alignment: .leading, spacing: 12) {
                moduleHeader("Financeiro · \(Fmt.monthYear(Date()))", "chart.pie.fill", .finance)
                HStack(spacing: 0) {
                    money("Entradas", s.monthIncome, .green)
                    money("Saídas", s.monthSpending, .red)
                    money("Saldo", s.balance, s.balance >= 0 ? .primary : .red)
                }
                if !s.topCategories.isEmpty {
                    let total = max(1, s.topCategories.reduce(0) { $0 + $1.total })
                    VStack(spacing: 6) {
                        ForEach(s.topCategories, id: \.category) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.category.icon).font(.caption).foregroundStyle(item.category.color).frame(width: 18)
                                Text(item.category.label).font(.caption).lineLimit(1).frame(width: 96, alignment: .leading)
                                ProgressBar(value: item.total / total, tint: item.category.color, height: 6)
                                Text(Fmt.currency(item.total)).font(.caption.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                }
                HStack {
                    Image(systemName: s.overBudget ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(s.overBudget ? .orange : .green)
                    Text(s.overBudget ? "Acima do planejado para a semana" : "Pode gastar \(Fmt.currency(s.weekRemaining)) nesta semana")
                        .font(.caption.weight(.semibold))
                }
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private func money(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Fmt.currency(value)).font(.subheadline.weight(.bold)).foregroundStyle(color)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func billsCard(_ s: HomeStats) -> some View {
        Button { go(.finance) } label: {
            VStack(alignment: .leading, spacing: 10) {
                moduleHeader("Contas a vencer", "calendar.badge.exclamationmark", .finance)
                ForEach(s.billsSoon.prefix(4)) { b in
                    HStack(spacing: 12) {
                        IconBadge(systemName: b.category.icon, tint: b.category.color, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.title).font(.subheadline.weight(.semibold))
                            Text(b.dueDate < Date().startOfDay ? "Atrasada · \(Fmt.relativeDay(b.dueDate))" : "Vence \(Fmt.relativeDay(b.dueDate))")
                                .font(.caption).foregroundStyle(b.dueDate < Date().startOfDay ? .red : .secondary)
                        }
                        Spacer()
                        Text(Fmt.currency(b.amount)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private func upcomingCard(_ s: HomeStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { go(.calendar) } label: {
                moduleHeader("Próximas atividades", "list.bullet.rectangle", .calendar, detail: "7 dias")
            }
            .buttonStyle(.plain)
            if s.upcoming.isEmpty {
                Text("Nada programado para os próximos dias.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(s.upcoming.prefix(5).enumerated()), id: \.offset) { _, item in
                Button { go(item.tab) } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemName: item.icon, tint: item.color, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(Fmt.dateTime(item.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let d = Fmt.daysUntil(item.date)
                        Text(d == 0 ? "Hoje" : d == 1 ? "Amanhã" : "\(d) dias")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(item.color.opacity(0.14), in: Capsule())
                            .foregroundStyle(item.color)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func growthCard() -> some View {
        let now = Date()
        let habitsToday = habits.filter { !$0.isArchived && $0.isScheduled(on: now) }
        let active = goals.filter { !$0.isCompleted }
        return VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: HomeRoute.growth) {
                HStack(spacing: 8) {
                    Image(systemName: "target").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Module.growth.tint)
                    Text("Metas e hábitos").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            if habitsToday.isEmpty && active.isEmpty {
                Text("Crie hábitos e metas para acompanhar sua evolução.").font(.subheadline).foregroundStyle(.secondary)
            }
            if !habitsToday.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(habitsToday) { h in
                            let done = h.isDone(on: now)
                            Button { HabitActions.toggle(h, on: now, context: context) } label: {
                                Label(h.name, systemImage: done ? "checkmark.circle.fill" : h.icon)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(done ? Color(hex: h.colorHex) : Color(hex: h.colorHex).opacity(0.12), in: Capsule())
                                    .foregroundStyle(done ? .white : Color(hex: h.colorHex))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            ForEach(active.prefix(3)) { g in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(g.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(Fmt.percent(g.progress)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                    ProgressBar(value: g.progress, tint: Theme.Module.growth.tint, height: 6)
                }
            }
        }
        .card()
    }

    private func productivityCard(_ s: HomeStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: HomeRoute.reports) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.yellow)
                    Text("Produtividade da semana").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 16) {
                ZStack {
                    RingProgress(value: s.productivity, tint: Theme.accent, lineWidth: 9)
                    Text(Fmt.percent(s.productivity)).font(.headline).monospacedDigit()
                }
                .frame(width: 76, height: 76)
                VStack(spacing: 7) {
                    metric("Estudo", s.studyRate, Theme.Module.study.tint)
                    metric("Treino", s.workoutRate, Theme.Module.fitness.tint)
                    if let t = s.taskRate { metric("Tarefas \(s.tasksDone)/\(s.tasksTotal)", t, Theme.Module.agenda.tint) }
                    if let h = s.habitRate { metric("Hábitos", h, Theme.Module.growth.tint) }
                }
            }
            if s.reviewsDue > 0 {
                Button { go(.studies) } label: {
                    Label("\(s.reviewsDue) revisão(ões) pendente(s)", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .card()
    }

    private func metric(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).frame(width: 92, alignment: .leading).lineLimit(1)
            ProgressBar(value: value, tint: color, height: 6)
            Text(Fmt.percent(value)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: Cálculo

    private func computeStats() -> HomeStats {
        let now = Date()
        let today = now.startOfDay
        let weekStart = now.startOfWeek
        let profile = profiles.first
        var s = HomeStats()

        s.todayItems = AgendaExpander.occurrences(events: events, from: today, to: today.adding(days: 1))
            .sorted { a, b in
                if a.event.isAllDay != b.event.isAllDay { return !a.event.isAllDay }
                if a.date != b.date { return a.date < b.date }
                return a.event.priorityRaw > b.event.priorityRaw
            }
        s.billsToday = recurring.filter { $0.isActive && $0.kind == .despesa && $0.dueDate.isSameDay(now) }

        s.studyGoal = max(1, profile?.weeklyStudyGoalMinutes ?? 600)
        s.studyMinutesWeek = sessions.filter { $0.date >= weekStart && $0.date <= now }.reduce(0) { $0 + $1.minutes }
        let college = topics.filter { $0.subject != nil }
        s.collegeTopics = college.count
        s.collegeProgress = college.isEmpty ? 0 : Double(college.filter { $0.status == .concluido }.count) / Double(college.count)
        let contestTopics = topics.filter { $0.contestSubject != nil }
        s.contestTopics = contestTopics.count
        s.contestProgress = contestTopics.isEmpty ? 0 : Double(contestTopics.filter { $0.status == .concluido }.count) / Double(contestTopics.count)
        s.reviewsDue = topics.filter { StudyReview.isDue($0, now: now) }.count

        s.workoutGoal = max(1, profile?.weeklyWorkoutGoal ?? 4)
        s.workoutsWeek = workouts.filter { $0.date >= weekStart && $0.date <= now }.count
        s.nextWorkout = TrainingInsights.nextWorkout(plans: plans, workouts: workouts, now: now)

        let month = DateInterval(start: now.startOfMonth, end: now)
        s.monthIncome = FinanceCalculator.income(transactions, in: month)
        s.monthSpending = FinanceCalculator.spending(transactions, in: month)
        s.topCategories = Array(FinanceCalculator.byCategory(transactions, in: month).prefix(3))
        if let profile {
            let plan = FinanceCalculator.weeklyPlan(profile: profile, transactions: transactions, recurring: recurring, debts: debts, cards: cards, now: now)
            s.balance = plan.balance
            s.weekRemaining = max(0, plan.remainingThisWeek)
            s.overBudget = plan.isOverBudget
        }
        s.billsSoon = recurring.filter { $0.isActive && $0.kind == .despesa && $0.dueDate <= now.adding(days: 7) }

        // Próximas atividades de todos os módulos (7 dias, a partir de amanhã).
        let from = today.adding(days: 1), to = today.adding(days: 8)
        var up: [(title: String, date: Date, icon: String, color: Color, tab: AppState.Tab)] = []
        for occ in AgendaExpander.occurrences(events: events, from: from, to: to) where !occ.event.isDone {
            let tab: AppState.Tab = occ.event.contest != nil ? .contests : (occ.event.category.isAcademic ? .studies : .calendar)
            up.append((occ.event.title, occ.date, occ.event.category.icon, occ.event.category.color, tab))
        }
        for c in contests {
            if let d = c.examDate, d >= from, d < to { up.append(("Prova: \(c.displayName)", d, "building.columns.fill", .indigo, .contests)) }
            if let d = c.registrationEnd, d >= from, d < to { up.append(("Fim das inscrições: \(c.organ)", d, "pencil.and.list.clipboard", .indigo, .contests)) }
        }
        s.upcoming = up.sorted { $0.date < $1.date }

        // Produtividade: tarefas com prazo nesta semana, hábitos dos últimos 7 dias.
        let weekTasks = events.filter { ($0.category.isTask || $0.category == .prova) && $0.recurrence == .nenhuma && $0.start >= weekStart && $0.start <= now }
        s.tasksTotal = weekTasks.count
        s.tasksDone = weekTasks.filter(\.isDone).count
        let activeHabits = habits.filter { !$0.isArchived }
        if !activeHabits.isEmpty {
            s.habitRate = activeHabits.map { HabitActions.consistency($0, days: 7, now: now) }.reduce(0, +) / Double(activeHabits.count)
        }
        return s
    }
}

/// Ajuda compartilhada entre Home e Treino.
enum TrainingInsights {
    /// Próxima ficha programada (hoje conta só se o treino de hoje ainda não foi registrado).
    static func nextWorkout(plans: [WorkoutPlan], workouts: [WorkoutSession], now: Date = Date()) -> (plan: WorkoutPlan, day: Date)? {
        let cal = Fmt.calendar
        let trainedToday = workouts.contains { $0.date.isSameDay(now) }
        var best: (plan: WorkoutPlan, day: Date)?
        for p in plans {
            for offset in 0..<8 {
                if offset == 0 && trainedToday { continue }
                let day = now.startOfDay.adding(days: offset)
                if p.weekdays.contains(cal.component(.weekday, from: day)) {
                    if best == nil || day < best!.day { best = (p, day) }
                    break
                }
            }
        }
        return best
    }
}

struct DashboardCustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("home.sections") private var sectionsRaw = HomeSection.defaultOrder
    @State private var order: [HomeSection] = []
    @State private var enabled: Set<HomeSection> = []

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("Arraste para reordenar. Desative o que não quer ver na Home.")) {
                    ForEach(order) { section in
                        Toggle(section.label, isOn: Binding(
                            get: { enabled.contains(section) },
                            set: { if $0 { enabled.insert(section) } else { enabled.remove(section) } }))
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                }
                Section {
                    Button("Restaurar padrão") {
                        order = HomeSection.allCases
                        enabled = Set(HomeSection.allCases)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Personalizar Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        sectionsRaw = order.filter { enabled.contains($0) }.map(\.rawValue).joined(separator: ",")
                        dismiss()
                    }
                }
            }
            .onAppear {
                let current = sectionsRaw.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) }
                enabled = Set(current)
                order = current + HomeSection.allCases.filter { !current.contains($0) }
            }
        }
    }
}

/// Ponto genérico para gráficos (data + valor).
struct DayValue: Identifiable {
    let date: Date
    let value: Double
    var series: String = ""
    var id: String { "\(series)-\(date.timeIntervalSince1970)" }
}

enum HabitActions {
    @MainActor
    static func toggle(_ habit: Habit, on date: Date, context: ModelContext) {
        if let existing = habit.checkins.first(where: { $0.date.isSameDay(date) }) {
            context.delete(existing)
        } else {
            habit.checkins.append(HabitCheckin(date: date))
        }
        context.saveQuietly()
    }

    static func streak(_ habit: Habit, now: Date = Date()) -> Int {
        var count = 0
        var day = now.startOfDay
        // Se hoje ainda não foi feito, a sequência conta a partir de ontem.
        if habit.isScheduled(on: day) && !habit.isDone(on: day) { day = day.adding(days: -1) }
        for _ in 0..<366 {
            if habit.isScheduled(on: day) {
                if habit.isDone(on: day) { count += 1 } else { break }
            }
            day = day.adding(days: -1)
        }
        return count
    }

    static func consistency(_ habit: Habit, days: Int, now: Date = Date()) -> Double {
        let range = (0..<days).map { now.startOfDay.adding(days: -$0) }.filter { habit.isScheduled(on: $0) }
        guard !range.isEmpty else { return 0 }
        return Double(range.filter { habit.isDone(on: $0) }.count) / Double(range.count)
    }
}
