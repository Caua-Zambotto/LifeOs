import SwiftUI
import SwiftData

/// Ocorrência concreta de um evento (expande repetições).
struct AgendaOccurrence: Identifiable {
    let event: AgendaEvent
    let date: Date
    var id: String { "\(event.id.uuidString)-\(date.timeIntervalSince1970)" }
}

enum AgendaExpander {
    static func occurrences(events: [AgendaEvent], from start: Date, to end: Date) -> [AgendaOccurrence] {
        var result: [AgendaOccurrence] = []
        for e in events {
            if e.recurrence == .nenhuma {
                if e.start >= start && e.start < end { result.append(AgendaOccurrence(event: e, date: e.start)) }
                continue
            }
            var d = e.start
            var guardCount = 0
            while d < end && guardCount < 1000 {
                if d >= start { result.append(AgendaOccurrence(event: e, date: d)) }
                guard let next = e.recurrence.next(after: d) else { break }
                d = next
                guardCount += 1
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}

/// Módulo de origem de um item do calendário (usado no filtro).
enum CalendarModule: String, CaseIterable, Identifiable {
    case todos, estudos, treino, editais, financeiro, pessoal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todos: "Todos"
        case .estudos: "Estudos"
        case .treino: "Treino"
        case .editais: "Editais"
        case .financeiro: "Financeiro"
        case .pessoal: "Pessoal"
        }
    }
    var icon: String {
        switch self {
        case .todos: "square.grid.2x2"
        case .estudos: "book.fill"
        case .treino: "dumbbell.fill"
        case .editais: "building.columns.fill"
        case .financeiro: "chart.pie.fill"
        case .pessoal: "person.fill"
        }
    }
    var color: Color {
        switch self {
        case .todos: Theme.accent
        case .estudos: Theme.Module.study.tint
        case .treino: Theme.Module.fitness.tint
        case .editais: Theme.Module.contest.tint
        case .financeiro: Theme.Module.finance.tint
        case .pessoal: Theme.Module.agenda.tint
        }
    }

    static func of(_ e: AgendaEvent) -> CalendarModule {
        if e.contest != nil { return .editais }
        if e.category.isAcademic { return .estudos }
        if e.category == .treino { return .treino }
        return .pessoal
    }
}

/// Item exibido no calendário: eventos e também itens vindos dos outros módulos.
struct CalendarItem: Identifiable {
    enum Source {
        case event(AgendaEvent)
        case bill(RecurringEntry)
        case workout(WorkoutPlan)
        case contest(Contest)
    }
    let id: String
    let title: String
    let date: Date
    let allDay: Bool
    let module: CalendarModule
    let icon: String
    let color: Color
    let subtitle: String
    let source: Source
}

struct AgendaView: View {
    enum Mode: String, CaseIterable { case mes = "Mês", semana = "Semana", dia = "Dia" }

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \AgendaEvent.start) private var events: [AgendaEvent]
    @Query(sort: \RecurringEntry.dueDate) private var recurring: [RecurringEntry]
    @Query private var contests: [Contest]
    @Query(sort: \WorkoutPlan.order) private var plans: [WorkoutPlan]
    @State private var mode: Mode = .mes
    @State private var filter: CalendarModule = .todos
    @State private var selected = Date().startOfDay
    @State private var month = Date().startOfMonth
    @State private var editing: AgendaEvent?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Visualização", selection: $mode.animation(.snappy)) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    filterBar
                    switch mode {
                    case .mes: monthView
                    case .semana: weekView
                    case .dia: dayHeader
                    }
                    dayList
                }
                .padding()
                .padding(.bottom, 16)
            }
            .screenBackground()
            .navigationTitle("Calendário")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hoje") { withAnimation { selected = Date().startOfDay; month = Date().startOfMonth } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .accessibilityLabel("Novo evento")
                }
            }
            .sheet(item: $editing) { EventEditorView(event: $0) }
            .sheet(isPresented: $creating) { EventEditorView(event: nil, defaultDate: selected) }
        }
    }

    // MARK: Itens

    /// Junta eventos, contas, treinos programados e datas de concursos no intervalo.
    private func items(from start: Date, to end: Date) -> [CalendarItem] {
        var out: [CalendarItem] = []
        for o in AgendaExpander.occurrences(events: events, from: start, to: end) {
            let e = o.event
            out.append(CalendarItem(id: "e-\(o.id)", title: e.title, date: o.date, allDay: e.isAllDay, module: CalendarModule.of(e),
                                    icon: e.category.icon, color: e.category.color,
                                    subtitle: [e.category.label, e.subject?.name, e.contest?.organ].compactMap { $0 }.joined(separator: " · "),
                                    source: .event(e)))
        }
        for r in recurring where r.isActive {
            var due = r.dueDate
            var guardCount = 0
            while due < end && guardCount < 60 {
                if due >= start {
                    out.append(CalendarItem(id: "b-\(r.id)-\(due.timeIntervalSince1970)", title: r.kind == .receita ? "Receber: \(r.title)" : "Vencimento: \(r.title)",
                                            date: due, allDay: true, module: .financeiro, icon: r.kind == .receita ? "arrow.down.left.circle.fill" : "creditcard.fill",
                                            color: r.kind == .receita ? .green : .orange, subtitle: Fmt.currency(r.amount), source: .bill(r)))
                }
                guard let next = r.recurrence.next(after: due) else { break }
                due = next
                guardCount += 1
            }
        }
        let cal = Fmt.calendar
        var day = start.startOfDay
        while day < end {
            for p in plans where p.weekdays.contains(cal.component(.weekday, from: day)) {
                var date = day
                if let t = p.reminderTime {
                    let hm = cal.dateComponents([.hour, .minute], from: t)
                    date = cal.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: day) ?? day
                }
                out.append(CalendarItem(id: "w-\(p.id)-\(day.timeIntervalSince1970)", title: "Treino: \(p.name)", date: date, allDay: p.reminderTime == nil,
                                        module: .treino, icon: "dumbbell.fill", color: Theme.Module.fitness.tint,
                                        subtitle: "\(p.exercises.count) exercícios", source: .workout(p)))
            }
            day = day.adding(days: 1)
        }
        for c in contests {
            let dates: [(Date?, String, String)] = [
                (c.examDate, "Prova", "building.columns.fill"),
                (c.registrationStart, "Início das inscrições", "pencil.line"),
                (c.registrationEnd, "Fim das inscrições", "pencil.and.list.clipboard"),
            ]
            for (d, label, icon) in dates {
                guard let d, d >= start, d < end else { continue }
                out.append(CalendarItem(id: "c-\(c.id)-\(label)", title: "\(label): \(c.organ)", date: d, allDay: label != "Prova",
                                        module: .editais, icon: icon, color: Theme.Module.contest.tint, subtitle: c.role, source: .contest(c)))
            }
        }
        return out.filter { filter == .todos || $0.module == filter }
            .sorted { a, b in a.allDay != b.allDay ? a.allDay : a.date < b.date }
    }

    // MARK: Filtro

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CalendarModule.allCases) { m in
                    Button { withAnimation(.snappy) { filter = m } } label: {
                        Label(m.label, systemImage: m.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(filter == m ? m.color : Theme.card, in: Capsule())
                            .foregroundStyle(filter == m ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Mês

    private var monthView: some View {
        let cal = Fmt.calendar
        let firstWeekday = cal.component(.weekday, from: month)
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: leading) + (0..<daysInMonth).map { month.adding(days: $0) }
        let marks = Dictionary(grouping: items(from: month, to: month.adding(months: 1)), by: { $0.date.startOfDay })
        let symbols = ["D", "S", "T", "Q", "Q", "S", "S"]

        return VStack(spacing: 12) {
            HStack {
                Button { withAnimation { month = month.adding(months: -1) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Mês anterior")
                Spacer()
                Text(Fmt.monthYear(month)).font(.headline)
                Spacer()
                Button { withAnimation { month = month.adding(months: 1) } } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Próximo mês")
            }
            .padding(.horizontal, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { Text(symbols[$0]).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, items: marks[day] ?? [])
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .card()
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            withAnimation { month = month.adding(months: v.translation.width < 0 ? 1 : -1) }
        })
    }

    private func dayCell(_ day: Date, items: [CalendarItem]) -> some View {
        let isSel = day.isSameDay(selected)
        let isToday = day.isSameDay(Date())
        let colors = Array(items.map(\.color).prefix(4))
        return Button { withAnimation(.snappy) { selected = day } } label: {
            VStack(spacing: 3) {
                Text("\(Fmt.calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday || isSel ? .bold : .regular))
                    .foregroundStyle(isSel ? .white : (isToday ? Theme.Module.agenda.tint : .primary))
                    .frame(width: 34, height: 34)
                    .background(isSel ? AnyShapeStyle(Theme.Module.agenda.gradient) : AnyShapeStyle(Color.clear), in: Circle())
                HStack(spacing: 2) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Fmt.fullDate(day)), \(items.count) item(ns)")
    }

    // MARK: Semana

    private var weekView: some View {
        let start = selected.startOfWeek
        let days = (0..<7).map { start.adding(days: $0) }
        let all = items(from: start, to: start.adding(days: 7))
        return VStack(spacing: 12) {
            HStack {
                Button { withAnimation { selected = selected.adding(days: -7) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Semana anterior")
                Spacer()
                Text("\(Fmt.dayMonth(start)) – \(Fmt.dayMonth(start.adding(days: 6)))").font(.headline)
                Spacer()
                Button { withAnimation { selected = selected.adding(days: 7) } } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Próxima semana")
            }
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let dayItems = all.filter { $0.date.isSameDay(d) }
                    let isSel = d.isSameDay(selected)
                    Button { withAnimation(.snappy) { selected = d } } label: {
                        VStack(spacing: 5) {
                            Text(Fmt.weekdayShort(d)).font(.caption2)
                            Text("\(Fmt.calendar.component(.day, from: d))").font(.headline)
                            HStack(spacing: 2) {
                                ForEach(Array(dayItems.prefix(3).enumerated()), id: \.offset) { _, it in
                                    Circle().fill(isSel ? .white : it.color).frame(width: 4, height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(isSel ? AnyShapeStyle(Theme.Module.agenda.gradient) : AnyShapeStyle(Theme.card),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(isSel ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Dia

    private var dayHeader: some View {
        HStack {
            Button { withAnimation { selected = selected.adding(days: -1) } } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Dia anterior")
            Spacer()
            VStack(spacing: 2) {
                Text(Fmt.weekdayShort(selected)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(Fmt.calendar.component(.day, from: selected))").font(.system(size: 40, weight: .bold, design: .rounded))
                Text(Fmt.monthYear(selected)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { withAnimation { selected = selected.adding(days: 1) } } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Próximo dia")
        }
        .card()
    }

    private var dayList: some View {
        let list = items(from: selected, to: selected.adding(days: 1))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(mode == .dia ? "Programação" : Fmt.fullDate(selected)).font(.headline)
                Spacer()
                if !list.isEmpty { Text("\(list.count) item(ns)").font(.caption).foregroundStyle(.secondary) }
            }
            if list.isEmpty {
                EmptyStateView(icon: "calendar", title: "Dia livre",
                               message: filter == .todos ? "Nenhum compromisso neste dia." : "Nada de \(filter.label) neste dia.",
                               actionTitle: "Adicionar evento") { creating = true }
            }
            ForEach(list) { item in
                switch item.source {
                case .event(let e):
                    EventRow(occurrence: AgendaOccurrence(event: e, date: item.date))
                        .contentShape(Rectangle())
                        .onTapGesture { editing = e }
                        .contextMenu {
                            if e.recurrence == .nenhuma {
                                Button(e.isDone ? "Marcar como pendente" : "Marcar como concluído", systemImage: "checkmark.circle") {
                                    e.isDone.toggle()
                                    NotificationScheduler.schedule(e)
                                    context.saveQuietly()
                                }
                            }
                            Button("Excluir", systemImage: "trash", role: .destructive) {
                                NotificationScheduler.cancel(event: e)
                                context.delete(e)
                                context.saveQuietly()
                            }
                        }
                case .bill:
                    moduleRow(item) { appState.selectedTab = .finance }
                case .workout:
                    moduleRow(item) { appState.selectedTab = .training }
                case .contest:
                    moduleRow(item) { appState.selectedTab = .contests }
                }
            }
        }
    }

    /// Itens de outros módulos: tocar leva ao módulo de origem.
    private func moduleRow(_ item: CalendarItem, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemName: item.icon, tint: item.color, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text([item.allDay ? "Dia inteiro" : Fmt.time(item.date), item.subtitle].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(item.module.label).font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(item.module.color.opacity(0.14), in: Capsule())
                    .foregroundStyle(item.module.color)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }
}

struct EventRow: View {
    let occurrence: AgendaOccurrence
    var body: some View {
        let e = occurrence.event
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(e.category.color).frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: e.category.icon).font(.caption).foregroundStyle(e.category.color)
                    Text(e.title).font(.subheadline.weight(.semibold)).strikethrough(e.isDone)
                    if e.priority == .alta { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.red) }
                }
                HStack(spacing: 8) {
                    Text(e.isAllDay ? "Dia inteiro" : Fmt.time(occurrence.date))
                    if let s = e.subject { Text("· \(s.name)") }
                    if e.recurrence != .nenhuma { Image(systemName: "repeat") }
                    if e.notify { Image(systemName: "bell.fill") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card(padding: 12)
        .opacity(e.isDone ? 0.6 : 1)
    }
}

struct EventEditorView: View {
    let event: AgendaEvent?
    var defaultDate: Date = Date()
    var defaultCategory: EventCategory = .compromisso
    var defaultSubject: Subject? = nil
    var defaultContest: Contest? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query(sort: \Contest.organ) private var contests: [Contest]

    @State private var title = ""
    @State private var details = ""
    @State private var category: EventCategory = .compromisso
    @State private var priority: Priority = .media
    @State private var start = Date()
    @State private var hasEnd = false
    @State private var end = Date()
    @State private var allDay = false
    @State private var recurrence: Recurrence = .nenhuma
    @State private var notify = true
    @State private var lead = 60
    @State private var subject: Subject?
    @State private var contest: Contest?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $title)
                    TextField("Descrição", text: $details, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Picker("Categoria", selection: $category) {
                        ForEach(EventCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    Picker("Prioridade", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Quando") {
                    Toggle("Dia inteiro", isOn: $allDay)
                    DatePicker("Início", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    if !allDay {
                        Toggle("Definir término", isOn: $hasEnd)
                        if hasEnd { DatePicker("Término", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute]) }
                    }
                    Picker("Repetir", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Notificação") {
                    Toggle("Avisar", isOn: $notify)
                    if notify {
                        Picker("Antecedência", selection: $lead) {
                            ForEach(NotificationSettings.leadOptions) { Text($0.label).tag($0.minutes) }
                        }
                    }
                }
                if category.isAcademic || subject != nil || contest != nil {
                    Section("Vínculos") {
                        Picker("Matéria", selection: $subject) {
                            Text("Nenhuma").tag(Subject?.none)
                            ForEach(subjects) { Text($0.name).tag(Optional($0)) }
                        }
                        Picker("Concurso", selection: $contest) {
                            Text("Nenhum").tag(Contest?.none)
                            ForEach(contests) { Text($0.displayName).tag(Optional($0)) }
                        }
                    }
                }
                if event != nil {
                    Section {
                        Button("Excluir evento", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(event == nil ? "Novo evento" : "Editar evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(title.trimmed.isEmpty) }
            }
            .confirmationDialog("Excluir este evento?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    if let event {
                        NotificationScheduler.cancel(event: event)
                        context.delete(event)
                        context.saveQuietly()
                    }
                    dismiss()
                }
            }
            .onAppear(perform: load)
            .onChange(of: category) { _, new in if event == nil { lead = NotificationSettings.lead(new.notificationCategory) } }
        }
    }

    private func load() {
        if let e = event {
            title = e.title; details = e.details; category = e.category; priority = e.priority
            start = e.start; allDay = e.isAllDay; recurrence = e.recurrence; notify = e.notify
            lead = e.leadMinutes; subject = e.subject; contest = e.contest
            if let end = e.end { hasEnd = true; self.end = end }
        } else {
            category = defaultCategory
            let base = defaultDate.isSameDay(Date()) ? Date() : defaultDate
            start = Fmt.calendar.date(bySettingHour: max(8, Fmt.calendar.component(.hour, from: base) + 1), minute: 0, second: 0, of: base) ?? base
            end = start.addingTimeInterval(3600)
            subject = defaultSubject
            contest = defaultContest
            lead = NotificationSettings.lead(category.notificationCategory)
            if [.prova, .trabalho, .entrega].contains(category) { priority = .alta }
        }
    }

    private func save() {
        let e = event ?? AgendaEvent(title: title, start: start, category: category)
        e.title = String(title.trimmed.prefix(200))
        e.details = details
        e.category = category
        e.priority = priority
        e.isAllDay = allDay
        e.start = allDay ? start.startOfDay : start
        e.end = (!allDay && hasEnd) ? end : nil
        e.recurrence = recurrence
        e.notify = notify
        e.leadMinutes = lead
        e.subject = subject
        e.contest = contest
        if event == nil { context.insert(e) }
        context.saveQuietly()
        NotificationScheduler.schedule(e)
        dismiss()
    }
}
