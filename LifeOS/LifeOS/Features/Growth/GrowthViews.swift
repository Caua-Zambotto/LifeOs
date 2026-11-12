import SwiftUI
import SwiftData
import Charts

struct GrowthView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \PersonalGoal.createdAt) private var goals: [PersonalGoal]
    @State private var tab = 0
    @State private var addingHabit = false
    @State private var editingHabit: Habit?
    @State private var addingGoal = false

    private var activeHabits: [Habit] { habits.filter { !$0.isArchived } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Seção", selection: $tab) {
                    Text("Hábitos").tag(0)
                    Text("Metas").tag(1)
                }
                .pickerStyle(.segmented)
                if tab == 0 { habitsTab } else { goalsTab }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .screenBackground()
        .navigationTitle("Desenvolvimento")
        .toolbar { Button { if tab == 0 { addingHabit = true } else { addingGoal = true } } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $addingHabit) { HabitEditor(habit: nil) }
        .sheet(item: $editingHabit) { HabitEditor(habit: $0) }
        .sheet(isPresented: $addingGoal) { GoalEditor(goal: nil) }
    }

    // MARK: Hábitos

    private var habitsTab: some View {
        let today = Date()
        let days = (0..<7).reversed().map { today.startOfDay.adding(days: -$0) }
        let consistency = (0..<30).reversed().map { offset -> DayValue in
            let d = today.startOfDay.adding(days: -offset)
            let scheduled = activeHabits.filter { $0.isScheduled(on: d) }
            let done = scheduled.filter { $0.isDone(on: d) }.count
            return DayValue(date: d, value: scheduled.isEmpty ? 0 : Double(done) / Double(scheduled.count) * 100)
        }
        return VStack(alignment: .leading, spacing: 14) {
            if activeHabits.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "Nenhum hábito", message: "Ex.: ler 20 páginas, beber 2L de água, estudar inglês 30 min.",
                               actionTitle: "Criar hábito") { addingHabit = true }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Consistência — últimos 30 dias").font(.headline)
                    Chart(consistency) {
                        BarMark(x: .value("Dia", $0.date, unit: .day), y: .value("%", $0.value))
                            .foregroundStyle(Theme.Module.growth.gradient)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 120)
                }
                .card()
            }
            ForEach(activeHabits) { h in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: h.icon).foregroundStyle(Color(hex: h.colorHex)).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name).font(.headline)
                            Text("Sequência: \(HabitActions.streak(h)) · 30 dias: \(Fmt.percent(HabitActions.consistency(h, days: 30)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { HabitActions.toggle(h, on: today, context: context) } label: {
                            Image(systemName: h.isDone(on: today) ? "checkmark.circle.fill" : "circle")
                                .font(.title).foregroundStyle(Color(hex: h.colorHex))
                        }
                        .buttonStyle(.plain)
                        .disabled(!h.isScheduled(on: today))
                    }
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { d in
                            VStack(spacing: 4) {
                                Text(Fmt.weekdayShort(d).prefix(1)).font(.caption2).foregroundStyle(.secondary)
                                Circle()
                                    .fill(h.isDone(on: d) ? Color(hex: h.colorHex) : (h.isScheduled(on: d) ? Color.gray.opacity(0.2) : Color.clear))
                                    .overlay(Circle().stroke(Color.gray.opacity(0.2)))
                                    .frame(width: 22, height: 22)
                                    .onTapGesture { if h.isScheduled(on: d) { HabitActions.toggle(h, on: d, context: context) } }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .card()
                .contextMenu {
                    Button("Editar", systemImage: "pencil") { editingHabit = h }
                    Button("Arquivar", systemImage: "archivebox") {
                        h.isArchived = true; NotificationScheduler.cancel(habit: h); context.saveQuietly()
                    }
                    Button("Excluir", systemImage: "trash", role: .destructive) {
                        NotificationScheduler.cancel(habit: h); context.delete(h); context.saveQuietly()
                    }
                }
            }
        }
    }

    // MARK: Metas

    private var goalsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if goals.isEmpty {
                EmptyStateView(icon: "target", title: "Nenhuma meta", message: "Defina metas de curto, médio e longo prazo — pessoais, profissionais, leitura, idiomas…",
                               actionTitle: "Criar meta") { addingGoal = true }
            }
            ForEach(GoalHorizon.allCases) { horizon in
                let list = goals.filter { $0.horizon == horizon }
                if !list.isEmpty {
                    Text(horizon.label).font(.headline).padding(.top, 4)
                    ForEach(list) { g in
                        NavigationLink { GoalDetailView(goal: g) } label: { goalRow(g) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func goalRow(_ g: PersonalGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconBadge(systemName: g.area.icon, tint: Theme.Module.growth.tint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.title).font(.subheadline.weight(.semibold)).strikethrough(g.isCompleted)
                    Text("\(g.area.label)" + (g.deadline.map { " · até \(Fmt.short($0))" } ?? "")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.percent(g.progress)).font(.headline).foregroundStyle(g.isCompleted ? .green : .primary)
            }
            ProgressBar(value: g.progress, tint: g.isCompleted ? .green : Theme.Module.growth.tint)
            Text("\(Fmt.number(g.currentValue)) de \(Fmt.number(g.targetValue)) \(g.unit)").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }
}

struct GoalDetailView: View {
    @Bindable var goal: PersonalGoal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var delta = ""
    @State private var note = ""
    @State private var editing = false

    var body: some View {
        let logs = goal.logs.sorted { $0.date < $1.date }
        let points = cumulative(logs)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.title).font(.title2.bold())
                    Text("\(goal.horizon.label) · \(goal.area.label)").opacity(0.9)
                    ProgressBar(value: goal.progress, tint: .white)
                    Text("\(Fmt.number(goal.currentValue)) de \(Fmt.number(goal.targetValue)) \(goal.unit) · \(Fmt.percent(goal.progress))")
                        .font(.subheadline.weight(.semibold))
                }
                .gradientCard(.growth)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Registrar progresso").font(.headline)
                    HStack {
                        TextField("Quanto avançou (\(goal.unit))", text: $delta).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                        Button("Salvar", action: log).buttonStyle(.borderedProminent)
                    }
                    TextField("Observação (opcional)", text: $note).textFieldStyle(.roundedBorder)
                }
                .card()

                if points.count >= 2 {
                    Chart(points) {
                        LineMark(x: .value("Data", $0.date), y: .value("Progresso", $0.value))
                        AreaMark(x: .value("Data", $0.date), y: .value("Progresso", $0.value)).foregroundStyle(Theme.Module.growth.gradient.opacity(0.2))
                    }
                    .frame(height: 160)
                    .card()
                }

                if !goal.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Observações").font(.headline)
                        Text(goal.notes).font(.subheadline)
                    }
                    .card()
                }

                SectionHeader(title: "Histórico")
                ForEach(logs.reversed()) { l in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(l.delta >= 0 ? "+" : "")\(Fmt.number(l.delta)) \(goal.unit)").font(.subheadline.weight(.semibold))
                            if !l.note.isEmpty { Text(l.note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(Fmt.short(l.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    .card(padding: 12)
                }
                Toggle("Meta concluída", isOn: $goal.isCompleted)
                    .onChange(of: goal.isCompleted) { _, _ in NotificationScheduler.schedule(goal); context.saveQuietly() }
                    .card()
            }
            .padding()
        }
        .screenBackground()
        .toolbar {
            Menu {
                Button("Editar", systemImage: "pencil") { editing = true }
                Button("Excluir", systemImage: "trash", role: .destructive) { context.delete(goal); context.saveQuietly(); dismiss() }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(isPresented: $editing) { GoalEditor(goal: goal) }
    }

    private func cumulative(_ logs: [GoalLog]) -> [DayValue] {
        var running = 0.0
        var result: [DayValue] = []
        for l in logs {
            running += l.delta
            result.append(DayValue(date: l.date, value: running))
        }
        return result
    }

    private func log() {
        guard let v = Fmt.parseDecimal(delta), v != 0 else { return }
        let l = GoalLog(delta: v, note: note.trimmed)
        goal.logs.append(l)
        goal.currentValue = max(0, goal.currentValue + v)
        if goal.currentValue >= goal.targetValue { goal.isCompleted = true }
        context.saveQuietly()
        delta = ""; note = ""
    }
}

struct GoalEditor: View {
    let goal: PersonalGoal?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var horizon: GoalHorizon = .curto
    @State private var area: GoalArea = .pessoal
    @State private var target = "100"
    @State private var current = "0"
    @State private var unit = "%"
    @State private var hasDeadline = false
    @State private var deadline = Date().adding(months: 3)
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Meta (ex.: Ler 12 livros)", text: $title)
                Picker("Prazo", selection: $horizon) { ForEach(GoalHorizon.allCases) { Text($0.label).tag($0) } }
                Picker("Área", selection: $area) { ForEach(GoalArea.allCases) { Label($0.label, systemImage: $0.icon).tag($0) } }
                Section("Medição") {
                    TextField("Valor alvo", text: $target).keyboardType(.decimalPad)
                    TextField("Valor atual", text: $current).keyboardType(.decimalPad)
                    TextField("Unidade (livros, horas, %, kg...)", text: $unit)
                }
                Toggle("Data limite", isOn: $hasDeadline)
                if hasDeadline { DatePicker("Até", selection: $deadline, displayedComponents: .date) }
                Section("Observações") { TextField("Por que esta meta importa?", text: $notes, axis: .vertical) }
            }
            .navigationTitle(goal == nil ? "Nova meta" : "Editar meta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let g = goal ?? PersonalGoal(title: title)
                        g.title = title.trimmed; g.horizon = horizon; g.area = area
                        g.targetValue = max(0.01, Fmt.parseDecimal(target) ?? 100)
                        g.currentValue = max(0, Fmt.parseDecimal(current) ?? 0)
                        g.unit = unit.trimmed.isEmpty ? "%" : unit.trimmed
                        g.deadline = hasDeadline ? deadline : nil
                        g.notes = notes
                        if goal == nil { context.insert(g) }
                        context.saveQuietly()
                        NotificationScheduler.schedule(g)
                        dismiss()
                    }
                    .disabled(title.trimmed.isEmpty)
                }
            }
            .onAppear {
                guard let g = goal else { return }
                title = g.title; horizon = g.horizon; area = g.area
                target = Fmt.number(g.targetValue); current = Fmt.number(g.currentValue); unit = g.unit
                if let d = g.deadline { hasDeadline = true; deadline = d }
                notes = g.notes
            }
        }
    }
}

struct HabitEditor: View {
    let habit: Habit?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "checkmark.circle.fill"
    @State private var color = "34C759"
    @State private var days: Set<Int> = []
    @State private var hasReminder = false
    @State private var reminder = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    private let icons = ["checkmark.circle.fill", "book.fill", "drop.fill", "figure.walk", "brain.head.profile", "moon.fill",
                         "character.bubble.fill", "leaf.fill", "dumbbell.fill", "pencil", "music.note", "heart.fill"]
    private let colors = ["34C759", "0A84FF", "FF9F0A", "FF375F", "BF5AF2", "5E5CE6", "64D2FF", "FFD60A"]
    private let names = [1: "D", 2: "S", 3: "T", 4: "Q", 5: "Q", 6: "S", 7: "S"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Hábito (ex.: Ler 20 páginas)", text: $name)
                Section("Ícone") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                        ForEach(icons, id: \.self) { i in
                            Image(systemName: i).font(.title3).frame(width: 40, height: 40)
                                .background(icon == i ? Color(hex: color).opacity(0.25) : Color.clear, in: Circle())
                                .onTapGesture { icon = i }
                        }
                    }
                    HStack {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.primary, lineWidth: color == c ? 2 : 0))
                                .onTapGesture { color = c }
                        }
                    }
                }
                Section(footer: Text("Nenhum dia selecionado = todos os dias.")) {
                    HStack {
                        ForEach(1...7, id: \.self) { d in
                            Text(names[d] ?? "").font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(days.contains(d) ? Color(hex: color) : Color.gray.opacity(0.15), in: Capsule())
                                .foregroundStyle(days.contains(d) ? .white : .primary)
                                .onTapGesture { if days.contains(d) { days.remove(d) } else { days.insert(d) } }
                        }
                    }
                    Toggle("Lembrete", isOn: $hasReminder)
                    if hasReminder { DatePicker("Horário", selection: $reminder, displayedComponents: .hourAndMinute) }
                }
            }
            .navigationTitle(habit == nil ? "Novo hábito" : "Editar hábito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let h = habit ?? Habit(name: name)
                        h.name = name.trimmed; h.icon = icon; h.colorHex = color; h.weekdays = days
                        h.reminderTime = hasReminder ? reminder : nil
                        if habit == nil { context.insert(h) }
                        context.saveQuietly()
                        NotificationScheduler.schedule(h)
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear {
                guard let h = habit else { return }
                name = h.name; icon = h.icon; color = h.colorHex; days = h.weekdays
                if let r = h.reminderTime { hasReminder = true; reminder = r }
            }
        }
    }
}
