import SwiftUI
import SwiftData
import Charts

private let weekdayNames = [1: "Dom", 2: "Seg", 3: "Ter", 4: "Qua", 5: "Qui", 6: "Sex", 7: "Sáb"]

/// Módulo TREINO: raiz da aba.
struct TrainingView: View {
    var body: some View {
        NavigationStack { WorkoutsView() }
    }
}

/// Início de um treino ao vivo (com ou sem ficha).
struct LiveStart: Identifiable {
    let id = UUID()
    let plan: WorkoutPlan?
}

struct WorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutPlan.order) private var plans: [WorkoutPlan]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @Query private var profiles: [UserProfile]
    @State private var tab = 0
    @State private var editingPlan: WorkoutPlan?
    @State private var creatingPlan = false
    @State private var logging: WorkoutPlan?
    @State private var loggingFree = false
    @State private var editingSession: WorkoutSession?
    @State private var selectedExercise = ""
    @State private var live: LiveStart?
    @State private var editingGoal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                shortcuts
                Picker("Seção", selection: $tab.animation(.snappy)) {
                    Text("Fichas").tag(0)
                    Text("Histórico").tag(1)
                    Text("Evolução").tag(2)
                }
                .pickerStyle(.segmented)
                switch tab {
                case 0: plansTab
                case 1: historyTab
                default: evolutionTab
                }
            }
            .padding()
            .padding(.bottom, 16)
        }
        .screenBackground()
        .navigationTitle("Treino")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Iniciar treino livre", systemImage: "play.fill") { live = LiveStart(plan: nil) }
                    Button("Nova ficha de treino", systemImage: "list.bullet.rectangle") { creatingPlan = true }
                    Button("Registrar treino passado", systemImage: "clock.arrow.circlepath") { loggingFree = true }
                    Divider()
                    Button("Meta semanal de treinos", systemImage: "target") { editingGoal = true }
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                .accessibilityLabel("Adicionar")
            }
        }
        .sheet(isPresented: $creatingPlan) { WorkoutPlanEditor(plan: nil) }
        .sheet(item: $editingPlan) { WorkoutPlanEditor(plan: $0) }
        .sheet(item: $logging) { WorkoutSessionEditor(session: nil, plan: $0) }
        .sheet(isPresented: $loggingFree) { WorkoutSessionEditor(session: nil, plan: nil) }
        .sheet(item: $editingSession) { WorkoutSessionEditor(session: $0, plan: nil) }
        .sheet(isPresented: $editingGoal) { WorkoutGoalSheet() }
        .fullScreenCover(item: $live) { LiveWorkoutView(plan: $0.plan) }
    }

    // MARK: Cabeçalho

    private var hero: some View {
        let next = TrainingInsights.nextWorkout(plans: plans, workouts: sessions)
        let weekStart = Date().startOfWeek
        let weekCount = sessions.filter { $0.date >= weekStart }.count
        let goal = max(1, profiles.first?.weeklyWorkoutGoal ?? 4)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.map { $0.day.isSameDay(Date()) ? "Treino de hoje" : "Próximo treino · \(Fmt.relativeDay($0.day))" } ?? "Nenhuma ficha programada")
                        .font(.subheadline.weight(.semibold)).opacity(0.9)
                    Text(next?.plan.name ?? "Treino livre").font(.title2.bold()).lineLimit(2)
                    if let p = next?.plan {
                        Text("\(p.exercises.count) exercícios · \(p.exercises.reduce(0) { $0 + $1.sets }) séries")
                            .font(.subheadline).opacity(0.9)
                    }
                }
                Spacer()
                ZStack {
                    RingProgress(value: min(1, Double(weekCount) / Double(goal)), tint: .white, lineWidth: 7)
                    VStack(spacing: 0) {
                        Text("\(weekCount)/\(goal)").font(.caption.bold())
                        Text("semana").font(.system(size: 8, weight: .semibold))
                    }
                }
                .frame(width: 58, height: 58)
                .onTapGesture { editingGoal = true }
            }
            Button { live = LiveStart(plan: next?.plan) } label: {
                Label("Iniciar treino", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Theme.Module.fitness.tint)
            }
            .buttonStyle(.plain)
        }
        .gradientCard(.fitness)
    }

    private var shortcuts: some View {
        let lastWeight = measurements.first(where: { $0.weight != nil })?.weight
        return HStack(spacing: 12) {
            NavigationLink { BodyView() } label: {
                shortcut("Corpo", lastWeight.map { "\(Fmt.number($0)) kg" } ?? "Peso e medidas", "scalemass.fill", Theme.Module.body.tint)
            }
            NavigationLink { FoodView() } label: {
                shortcut("Alimentação", "Estoque e receitas", "fork.knife", Theme.Module.food.tint)
            }
        }
        .buttonStyle(.plain)
    }

    private func shortcut(_ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            IconBadge(systemName: icon, tint: color, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12)
    }

    private var plansTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if plans.isEmpty {
                EmptyStateView(icon: "figure.strengthtraining.traditional", title: "Monte sua ficha",
                               message: "Ex.: A – Peito e Tríceps (seg/qui), B – Costas e Bíceps (ter/sex), C – Pernas (qua/sáb).",
                               actionTitle: "Criar ficha") { creatingPlan = true }
            }
            ForEach(plans) { p in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.headline)
                            Text(p.weekdays.sorted().compactMap { weekdayNames[$0] }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let t = p.reminderTime { Label(Fmt.time(t), systemImage: "bell.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(p.sortedExercises) { e in
                        HStack {
                            Text(e.name).font(.subheadline)
                            Spacer()
                            Text("\(e.sets)×\(e.reps)" + (e.load > 0 ? " · \(Fmt.number(e.load)) kg" : "")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button { live = LiveStart(plan: p) } label: { Label("Iniciar", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).tint(Theme.Module.fitness.tint)
                        Button("Registrar") { logging = p }.buttonStyle(.bordered)
                        Spacer()
                        Button { editingPlan = p } label: { Image(systemName: "pencil") }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Editar ficha")
                    }
                }
                .card()
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sessions.isEmpty {
                Text("Nenhum treino registrado. Diga ao assistente: \"hoje treinei pernas\".").foregroundStyle(.secondary)
            }
            ForEach(sessions.prefix(60)) { s in
                HStack(spacing: 12) {
                    IconBadge(systemName: "figure.strengthtraining.traditional", tint: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.subheadline.weight(.semibold))
                        Text("\(Fmt.fullDate(s.date))" + (s.durationMinutes > 0 ? " · \(Fmt.duration(minutes: s.durationMinutes))" : "")
                             + (s.entries.isEmpty ? "" : " · \(s.entries.count) exercícios"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .card(padding: 12)
                .onTapGesture { editingSession = s }
                .contextMenu { Button("Excluir", systemImage: "trash", role: .destructive) { context.delete(s); context.saveQuietly() } }
            }
        }
    }

    private var evolutionTab: some View {
        let weeks = (0..<12).reversed().map { Date().startOfWeek.adding(days: -7 * $0) }
        let freq = weeks.map { w in DayValue(date: w, value: Double(sessions.filter { $0.date >= w && $0.date < w.adding(days: 7) }.count)) }
        let exercises = Array(Set(sessions.flatMap { $0.entries.map(\.name) })).sorted()
        let chosen = selectedExercise.isEmpty ? (exercises.first ?? "") : selectedExercise
        let loads = sessions.compactMap { s -> DayValue? in
            let max = s.entries.filter { $0.name == chosen }.map(\.load).max()
            return max.map { DayValue(date: s.date, value: $0) }
        }.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Frequência semanal").font(.headline)
                Chart(freq) { BarMark(x: .value("Semana", $0.date, unit: .weekOfYear), y: .value("Treinos", $0.value)).foregroundStyle(Theme.Module.fitness.gradient) }
                    .frame(height: 150)
                Text("Média: \(Fmt.number(freq.map(\.value).reduce(0, +) / 12)) treinos/semana nas últimas 12 semanas")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .card()
            VStack(alignment: .leading, spacing: 8) {
                Text("Evolução de carga").font(.headline)
                if exercises.isEmpty {
                    Text("Registre treinos com exercícios e cargas para comparar a evolução.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Picker("Exercício", selection: Binding(get: { chosen }, set: { selectedExercise = $0 })) {
                        ForEach(exercises, id: \.self) { Text($0).tag($0) }
                    }
                    if loads.count >= 1 {
                        Chart(loads) {
                            LineMark(x: .value("Data", $0.date), y: .value("Carga", $0.value))
                            PointMark(x: .value("Data", $0.date), y: .value("Carga", $0.value))
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 170)
                        if let first = loads.first?.value, let last = loads.last?.value, first > 0 {
                            Text("Variação: \(last >= first ? "+" : "")\(Fmt.number(last - first)) kg (\(Fmt.percent((last - first) / first)))")
                                .font(.caption.weight(.semibold)).foregroundStyle(last >= first ? .green : .orange)
                        }
                    }
                }
            }
            .card()
        }
    }
}

struct WorkoutPlanEditor: View {
    let plan: WorkoutPlan?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var days: Set<Int> = []
    @State private var hasReminder = false
    @State private var reminder = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var exercises: [ExerciseDraft] = []
    @State private var confirmDelete = false

    struct ExerciseDraft: Identifiable {
        var id = UUID()
        var name = ""
        var group = ""
        var sets = 3
        var reps = 10
        var load = ""
        var rest = 60
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (ex.: Peito e Tríceps)", text: $name)
                    HStack {
                        ForEach(1...7, id: \.self) { d in
                            Text(weekdayNames[d] ?? "")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(days.contains(d) ? Color.green : Color.gray.opacity(0.15), in: Capsule())
                                .foregroundStyle(days.contains(d) ? .white : .primary)
                                .onTapGesture { if days.contains(d) { days.remove(d) } else { days.insert(d) } }
                        }
                    }
                    Toggle("Lembrete", isOn: $hasReminder)
                    if hasReminder { DatePicker("Horário", selection: $reminder, displayedComponents: .hourAndMinute) }
                }
                Section("Exercícios") {
                    ForEach($exercises) { $e in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Exercício", text: $e.name).font(.headline)
                            TextField("Grupo muscular", text: $e.group).font(.caption)
                            Stepper("Séries: \(e.sets)", value: $e.sets, in: 1...10)
                            Stepper("Repetições: \(e.reps)", value: $e.reps, in: 1...50)
                            HStack {
                                TextField("Carga (kg)", text: $e.load).keyboardType(.decimalPad)
                                Stepper("Descanso \(e.rest)s", value: $e.rest, in: 15...300, step: 15)
                            }
                        }
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button { exercises.append(ExerciseDraft()) } label: { Label("Adicionar exercício", systemImage: "plus") }
                }
                if plan != nil {
                    Section { Button("Excluir ficha", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(plan == nil ? "Nova ficha" : "Editar ficha")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(name.trimmed.isEmpty) }
            }
            .confirmationDialog("Excluir esta ficha? O histórico de treinos é mantido.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    if let plan { NotificationScheduler.cancel(plan: plan); context.delete(plan); context.saveQuietly() }
                    dismiss()
                }
            }
            .onAppear {
                guard let p = plan else { return }
                name = p.name; days = p.weekdays
                if let r = p.reminderTime { hasReminder = true; reminder = r }
                exercises = p.sortedExercises.map {
                    ExerciseDraft(name: $0.name, group: $0.muscleGroup, sets: $0.sets, reps: $0.reps,
                                  load: $0.load > 0 ? Fmt.number($0.load) : "", rest: $0.restSeconds)
                }
            }
        }
    }

    private func save() {
        let p = plan ?? WorkoutPlan(name: name)
        p.name = name.trimmed
        p.weekdays = days
        p.reminderTime = hasReminder ? reminder : nil
        if plan == nil {
            p.order = (try? context.fetchCount(FetchDescriptor<WorkoutPlan>())) ?? 0
            context.insert(p)
        }
        p.exercises.forEach { context.delete($0) }
        p.exercises = []
        for (i, e) in exercises.enumerated() where !e.name.trimmed.isEmpty {
            let t = ExerciseTemplate(name: e.name.trimmed, muscleGroup: e.group.trimmed, sets: e.sets, reps: e.reps,
                                     load: Fmt.parseDecimal(e.load) ?? 0, restSeconds: e.rest, order: i)
            p.exercises.append(t)
        }
        context.saveQuietly()
        NotificationScheduler.schedule(p)
        dismiss()
    }
}

struct WorkoutSessionEditor: View {
    let session: WorkoutSession?
    let plan: WorkoutPlan?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date()
    @State private var duration = 60
    @State private var notes = ""
    @State private var entries: [EntryDraft] = []
    @State private var updatePlanLoads = true

    struct EntryDraft: Identifiable {
        var id = UUID()
        var name = ""
        var sets = 3
        var reps = 10
        var load = ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Treino (ex.: Pernas)", text: $title)
                    DatePicker("Data", selection: $date)
                    Stepper("Duração: \(Fmt.duration(minutes: duration))", value: $duration, in: 0...300, step: 5)
                }
                Section("Exercícios e cargas") {
                    ForEach($entries) { $e in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Exercício", text: $e.name).font(.subheadline.weight(.semibold))
                            HStack {
                                Stepper("\(e.sets)×\(e.reps)", value: $e.sets, in: 1...10)
                                Stepper("", value: $e.reps, in: 1...50).labelsHidden()
                            }
                            TextField("Carga (kg)", text: $e.load).keyboardType(.decimalPad)
                        }
                    }
                    .onDelete { entries.remove(atOffsets: $0) }
                    Button { entries.append(EntryDraft()) } label: { Label("Adicionar exercício", systemImage: "plus") }
                }
                if plan != nil {
                    Toggle("Atualizar cargas da ficha", isOn: $updatePlanLoads)
                }
                Section("Observações") { TextField("Como foi o treino?", text: $notes, axis: .vertical) }
            }
            .navigationTitle(session == nil ? "Registrar treino" : "Editar treino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let s = session {
            title = s.title; date = s.date; duration = s.durationMinutes; notes = s.notes
            entries = s.sortedEntries.map { EntryDraft(name: $0.name, sets: $0.sets, reps: $0.reps, load: $0.load > 0 ? Fmt.number($0.load) : "") }
        } else if let p = plan {
            title = p.name
            entries = p.sortedExercises.map { EntryDraft(name: $0.name, sets: $0.sets, reps: $0.reps, load: $0.load > 0 ? Fmt.number($0.load) : "") }
        }
    }

    private func save() {
        let s = session ?? WorkoutSession(date: date, title: title)
        s.title = title.trimmed.isEmpty ? "Treino" : title.trimmed
        s.date = date
        s.durationMinutes = duration
        s.notes = notes
        if session == nil { s.planID = plan?.id; context.insert(s) }
        s.entries.forEach { context.delete($0) }
        s.entries = []
        for (i, e) in entries.enumerated() where !e.name.trimmed.isEmpty {
            s.entries.append(ExerciseEntry(name: e.name.trimmed, sets: e.sets, reps: e.reps, load: Fmt.parseDecimal(e.load) ?? 0, order: i))
        }
        s.muscleGroups = RuleBasedInterpreter.muscleGroups.filter { RX.test(#"\b(?:\#($0.pattern))\b"#, s.title.folded) }.map(\.name)
        if let p = plan, updatePlanLoads {
            for ex in p.exercises {
                if let e = entries.first(where: { $0.name.trimmed == ex.name }), let load = Fmt.parseDecimal(e.load) {
                    ex.load = load; ex.sets = e.sets; ex.reps = e.reps
                }
            }
        }
        context.saveQuietly()
        dismiss()
    }
}

// MARK: - Corpo

struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date) private var items: [BodyMeasurement]
    @Query private var profiles: [UserProfile]
    @State private var adding = false
    @State private var editingGoal = false
    @State private var field = "weight"

    private let fields: [(String, String)] = [("weight", "Peso"), ("waist", "Cintura"), ("arm", "Braço"),
                                               ("chest", "Peito"), ("leg", "Perna"), ("hip", "Quadril"), ("bodyFat", "Gordura %")]

    private func value(_ m: BodyMeasurement, _ key: String) -> Double? {
        switch key {
        case "weight": m.weight
        case "waist": m.waist
        case "arm": m.arm
        case "chest": m.chest
        case "leg": m.leg
        case "hip": m.hip
        default: m.bodyFat
        }
    }

    var body: some View {
        let profile = profiles.first
        let lastWeight = items.last(where: { $0.weight != nil })?.weight
        let bmi: Double? = {
            guard let w = lastWeight, let h = profile?.heightCm, h > 0 else { return nil }
            return w / pow(h / 100, 2)
        }()
        let series = items.compactMap { m in value(m, field).map { DayValue(date: m.date, value: $0) } }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    StatTile(title: "Peso atual", value: lastWeight.map { "\(Fmt.number($0)) kg" } ?? "–", icon: "scalemass.fill", tint: .orange)
                    StatTile(title: "IMC", value: bmi.map { Fmt.number($0) } ?? "–", icon: "heart.text.square.fill", tint: .pink)
                    StatTile(title: "Meta", value: profile?.targetWeight.map { "\(Fmt.number($0)) kg" } ?? "–", icon: "target", tint: .green)
                }
                .onTapGesture { editingGoal = true }

                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(fields, id: \.0) { f in Chip(title: f.1, isSelected: field == f.0, tint: .orange) { field = f.0 } }
                        }
                    }
                    if series.count >= 2 {
                        Chart {
                            ForEach(series) {
                                LineMark(x: .value("Data", $0.date), y: .value("Valor", $0.value)).interpolationMethod(.catmullRom)
                                PointMark(x: .value("Data", $0.date), y: .value("Valor", $0.value))
                            }
                            if field == "weight", let t = profile?.targetWeight {
                                RuleMark(y: .value("Meta", t)).foregroundStyle(.green).lineStyle(StrokeStyle(dash: [5]))
                                    .annotation(position: .top, alignment: .leading) { Text("Meta").font(.caption2).foregroundStyle(.green) }
                            }
                        }
                        .foregroundStyle(Theme.Module.body.gradient)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 200)
                        if let f = series.first?.value, let l = series.last?.value {
                            Text("Desde \(Fmt.short(series.first!.date)): \(l >= f ? "+" : "")\(Fmt.number(l - f))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Registre ao menos duas medições para ver o gráfico.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .card()

                SectionHeader(title: "Histórico", actionTitle: "Registrar") { adding = true }
                ForEach(items.reversed()) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Fmt.fullDate(m.date)).font(.subheadline.weight(.semibold))
                        Text(fields.compactMap { f in value(m, f.0).map { "\(f.1): \(Fmt.number($0))" } }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .card(padding: 12)
                    .contextMenu { Button("Excluir", systemImage: "trash", role: .destructive) { context.delete(m); context.saveQuietly() } }
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .screenBackground()
        .navigationTitle("Corpo")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { BodyMeasurementEditor() }
        .sheet(isPresented: $editingGoal) { BodyGoalEditor() }
    }
}

struct BodyMeasurementEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var weight = ""
    @State private var waist = ""
    @State private var arm = ""
    @State private var chest = ""
    @State private var leg = ""
    @State private var hip = ""
    @State private var fat = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Data", selection: $date, displayedComponents: .date)
                Section("Peso") { TextField("Peso (kg)", text: $weight).keyboardType(.decimalPad) }
                Section("Medidas (cm) — opcionais") {
                    TextField("Cintura", text: $waist).keyboardType(.decimalPad)
                    TextField("Braço", text: $arm).keyboardType(.decimalPad)
                    TextField("Peito", text: $chest).keyboardType(.decimalPad)
                    TextField("Perna/coxa", text: $leg).keyboardType(.decimalPad)
                    TextField("Quadril", text: $hip).keyboardType(.decimalPad)
                    TextField("Gordura corporal (%)", text: $fat).keyboardType(.decimalPad)
                }
                TextField("Observação", text: $note)
            }
            .navigationTitle("Medidas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let m = BodyMeasurement(date: date)
                        m.weight = valid(weight, 20...400)
                        m.waist = valid(waist, 10...250); m.arm = valid(arm, 10...250); m.chest = valid(chest, 10...250)
                        m.leg = valid(leg, 10...250); m.hip = valid(hip, 10...250); m.bodyFat = valid(fat, 2...70)
                        m.note = note
                        guard m.weight != nil || m.waist != nil || m.arm != nil || m.chest != nil || m.leg != nil || m.hip != nil || m.bodyFat != nil else { return }
                        context.insert(m)
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
        }
    }

    private func valid(_ s: String, _ range: ClosedRange<Double>) -> Double? {
        guard let v = Fmt.parseDecimal(s), range.contains(v) else { return nil }
        return v
    }
}

struct BodyGoalEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var height = ""
    @State private var target = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Altura (cm)", text: $height).keyboardType(.decimalPad)
                TextField("Peso meta (kg)", text: $target).keyboardType(.decimalPad)
            }
            .navigationTitle("Altura e meta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let p = context.profile()
                        p.heightCm = Fmt.parseDecimal(height).flatMap { (80...250).contains($0) ? $0 : nil }
                        p.targetWeight = Fmt.parseDecimal(target).flatMap { (20...400).contains($0) ? $0 : nil }
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let p = context.profile()
                height = p.heightCm.map { Fmt.number($0) } ?? ""
                target = p.targetWeight.map { Fmt.number($0) } ?? ""
            }
        }
    }
}
