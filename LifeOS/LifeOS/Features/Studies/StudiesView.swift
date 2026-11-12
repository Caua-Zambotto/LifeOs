import SwiftUI
import SwiftData
import Charts

/// Módulo ESTUDOS: faculdade (matérias, conteúdos, avaliações, revisões, horas e metas).
struct StudiesView: View {
    enum StudyTab: String, CaseIterable, Identifiable {
        case materias = "Matérias", avaliacoes = "Avaliações", revisoes = "Revisões", historico = "Histórico"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query(sort: \AgendaEvent.start) private var events: [AgendaEvent]
    @Query(sort: \StudySession.date, order: .reverse) private var sessions: [StudySession]
    @Query private var topics: [StudyTopic]
    @Query private var profiles: [UserProfile]
    @State private var section: StudyTab = .materias
    @State private var addingSubject = false
    @State private var editingCourse = false
    @State private var logging = false
    @State private var editingGoal = false
    @State private var addingEvent: EventCategory?
    @State private var editingEvent: AgendaEvent?

    private var profile: UserProfile? { profiles.first }
    private var goalMinutes: Int { max(1, profile?.weeklyStudyGoalMinutes ?? 600) }
    private var weekMinutes: Int {
        let start = Date().startOfWeek
        return sessions.filter { $0.date >= start }.reduce(0) { $0 + $1.minutes }
    }
    private var academicEvents: [AgendaEvent] {
        events.filter { $0.category.isAcademic && $0.contest == nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    weeklyGoal
                    Picker("Seção", selection: $section.animation(.snappy)) {
                        ForEach(StudyTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch section {
                    case .materias: subjectsSection
                    case .avaliacoes: evaluationsSection
                    case .revisoes: reviewsSection
                    case .historico: historySection
                    }
                }
                .padding()
                .padding(.bottom, 16)
            }
            .screenBackground()
            .navigationTitle("Estudos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Registrar estudo", systemImage: "timer") { logging = true }
                        Button("Nova matéria", systemImage: "book.closed") { addingSubject = true }
                        Button("Nova prova", systemImage: "graduationcap") { addingEvent = .prova }
                        Button("Novo trabalho", systemImage: "doc.text") { addingEvent = .trabalho }
                        Button("Nova entrega", systemImage: "tray.and.arrow.up") { addingEvent = .entrega }
                        Divider()
                        Button("Meta semanal de estudo", systemImage: "target") { editingGoal = true }
                        Button("Dados do curso", systemImage: "building.2") { editingCourse = true }
                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .accessibilityLabel("Adicionar")
                }
            }
            .navigationDestination(for: Subject.self) { SubjectDetailView(subject: $0) }
            .sheet(isPresented: $addingSubject) { SubjectEditor(subject: nil) }
            .sheet(isPresented: $editingCourse) { CourseEditor() }
            .sheet(isPresented: $logging) { StudyLogSheet() }
            .sheet(isPresented: $editingGoal) { StudyGoalSheet() }
            .sheet(item: $addingEvent) { cat in EventEditorView(event: nil, defaultCategory: cat) }
            .sheet(item: $editingEvent) { EventEditorView(event: $0) }
        }
    }

    // MARK: Cabeçalho

    private var hero: some View {
        let college = topics.filter { $0.subject != nil }
        let done = college.filter { $0.status == .concluido }.count
        let progress = college.isEmpty ? 0 : Double(done) / Double(college.count)
        let next = academicEvents.filter { !$0.isDone && $0.start >= Date().startOfDay }.first
        return Button { editingCourse = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile?.course.isEmpty == false ? profile!.course : "Toque para informar seu curso")
                            .font(.title3.bold()).lineLimit(2)
                        Text([profile?.institution ?? "", profile?.semester.isEmpty == false ? "\(profile!.semester)º semestre" : ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).opacity(0.9)
                    }
                    Spacer()
                    ZStack {
                        RingProgress(value: progress, tint: .white, lineWidth: 7)
                        Text(Fmt.percent(progress)).font(.caption.bold())
                    }
                    .frame(width: 58, height: 58)
                }
                HStack(spacing: 22) {
                    kpi("\(subjects.count)", "matérias")
                    kpi("\(done)/\(college.count)", "conteúdos")
                    kpi(Fmt.duration(minutes: weekMinutes), "na semana")
                }
                if let next {
                    Label("\(next.category.label): \(next.title) · \(Fmt.relativeDay(next.start))", systemImage: next.category.icon)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                        .lineLimit(1)
                }
            }
            .gradientCard(.study)
        }
        .buttonStyle(.plain)
    }

    private func kpi(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).opacity(0.9)
        }
    }

    private var weeklyGoal: some View {
        let ratio = min(1, Double(weekMinutes) / Double(goalMinutes))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Meta da semana").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Ajustar") { editingGoal = true }.font(.caption.weight(.semibold))
            }
            ProgressBar(value: ratio, tint: Theme.Module.study.tint)
            HStack {
                Text("\(Fmt.duration(minutes: weekMinutes)) de \(Fmt.duration(minutes: goalMinutes))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { logging = true } label: { Label("Registrar estudo", systemImage: "plus") }
                    .font(.caption.weight(.semibold))
            }
        }
        .card()
    }

    // MARK: Matérias

    @ViewBuilder
    private var subjectsSection: some View {
        if subjects.isEmpty {
            EmptyStateView(icon: "books.vertical.fill", title: "Nenhuma matéria",
                           message: "Cadastre suas matérias ou diga ao assistente: \"Tenho prova de cálculo dia 20\".",
                           actionTitle: "Nova matéria") { addingSubject = true }
        }
        ForEach(subjects) { s in
            NavigationLink(value: s) { SubjectCard(subject: s) }
                .buttonStyle(.plain)
        }
    }

    // MARK: Avaliações

    @ViewBuilder
    private var evaluationsSection: some View {
        let today = Date().startOfDay
        let upcoming = academicEvents.filter { !$0.isDone && $0.start >= today }
        let overdue = academicEvents.filter { !$0.isDone && $0.start < today }
        let done = academicEvents.filter { $0.isDone }.reversed()
        HStack(spacing: 8) {
            ForEach([EventCategory.prova, .trabalho, .entrega], id: \.self) { cat in
                Button { addingEvent = cat } label: { Label(cat.label, systemImage: "plus") }
                    .buttonStyle(.bordered).font(.caption.weight(.semibold))
            }
        }
        if academicEvents.isEmpty {
            EmptyStateView(icon: "graduationcap", title: "Sem avaliações", message: "Provas, trabalhos e entregas aparecem aqui e no Calendário.")
        }
        if !overdue.isEmpty { groupHeader("Atrasadas", .red); eventList(overdue) }
        if !upcoming.isEmpty { groupHeader("Próximas", Theme.Module.study.tint); eventList(upcoming) }
        if !done.isEmpty { groupHeader("Concluídas", .secondary); eventList(Array(done.prefix(15))) }
    }

    private func groupHeader(_ title: String, _ color: Color) -> some View {
        Text(title).font(.subheadline.weight(.bold)).foregroundStyle(color).padding(.top, 4)
    }

    private func eventList(_ list: [AgendaEvent]) -> some View {
        ForEach(list) { e in
            EventRow(occurrence: AgendaOccurrence(event: e, date: e.start))
                .contentShape(Rectangle())
                .onTapGesture { editingEvent = e }
                .contextMenu {
                    Button(e.isDone ? "Marcar como pendente" : "Marcar como concluída", systemImage: "checkmark.circle") {
                        e.isDone.toggle()
                        NotificationScheduler.schedule(e)
                        context.saveQuietly()
                    }
                }
        }
    }

    // MARK: Revisões

    @ViewBuilder
    private var reviewsSection: some View {
        let now = Date()
        let college = topics.filter { $0.subject != nil }
        let due = college.filter { StudyReview.isDue($0, now: now) }.sorted { ($0.nextReview ?? now) < ($1.nextReview ?? now) }
        let soon = college.filter { ($0.nextReview ?? .distantPast) > now && ($0.nextReview ?? now) <= now.adding(days: 14) }
            .sorted { ($0.nextReview ?? now) < ($1.nextReview ?? now) }
        Text("Ao concluir um conteúdo, o LifeOS agenda revisões em 1, 7, 15, 30 e 60 dias.")
            .font(.caption).foregroundStyle(.secondary)
        if due.isEmpty && soon.isEmpty {
            EmptyStateView(icon: "arrow.clockwise", title: "Nenhuma revisão agendada",
                           message: "Marque conteúdos como concluídos dentro de cada matéria.")
        }
        if !due.isEmpty {
            groupHeader("Para hoje", .orange)
            ForEach(due) { t in reviewRow(t, due: true) }
        }
        if !soon.isEmpty {
            groupHeader("Próximos 14 dias", .secondary)
            ForEach(soon) { t in reviewRow(t, due: false) }
        }
    }

    private func reviewRow(_ t: StudyTopic, due: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color(hex: t.subject?.colorHex ?? "8B5CF6")).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.subheadline.weight(.semibold))
                Text("\(t.subject?.name ?? "") · revisão \(t.reviewStage + 1)\(t.nextReview.map { " · \(Fmt.relativeDay($0))" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if due {
                Button("Revisado") { StudyReview.markReviewed(t); context.saveQuietly() }
                    .buttonStyle(.borderedProminent).font(.caption.weight(.semibold))
            }
        }
        .card(padding: 12)
    }

    // MARK: Histórico

    @ViewBuilder
    private var historySection: some View {
        let weeks = (0..<8).reversed().map { Date().startOfWeek.adding(days: -7 * $0) }
        let weekly = weeks.map { w in
            DayValue(date: w, value: Double(sessions.filter { $0.date >= w && $0.date < w.adding(days: 7) }.reduce(0) { $0 + $1.minutes }) / 60)
        }
        let monthAgo = Date().adding(days: -30)
        let bySubject = subjects.map { s in
            (name: s.name, color: Color(hex: s.colorHex), hours: Double(s.sessions.filter { $0.date >= monthAgo }.reduce(0) { $0 + $1.minutes }) / 60)
        }.filter { $0.hours > 0 }.sorted { $0.hours > $1.hours }

        VStack(alignment: .leading, spacing: 8) {
            Text("Horas por semana").font(.headline)
            Chart {
                ForEach(weekly) { w in
                    BarMark(x: .value("Semana", w.date, unit: .weekOfYear), y: .value("Horas", w.value))
                        .foregroundStyle(Theme.Module.study.gradient)
                        .cornerRadius(5)
                }
                RuleMark(y: .value("Meta", Double(goalMinutes) / 60))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .leading) { Text("meta").font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(height: 170)
        }
        .card()

        if !bySubject.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Últimos 30 dias por matéria").font(.headline)
                let maxH = bySubject.first?.hours ?? 1
                ForEach(bySubject, id: \.name) { item in
                    HStack(spacing: 10) {
                        Text(item.name).font(.caption).lineLimit(1).frame(width: 110, alignment: .leading)
                        ProgressBar(value: item.hours / maxH, tint: item.color, height: 8)
                        Text("\(Fmt.number(item.hours))h").font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
            }
            .card()
        }

        let college = sessions.filter { $0.contest == nil && $0.contestSubject == nil }
        if college.isEmpty {
            EmptyStateView(icon: "timer", title: "Sem sessões registradas",
                           message: "Registre pelo + ou diga ao assistente: \"Estudei 1h30 de cálculo\".",
                           actionTitle: "Registrar estudo") { logging = true }
        } else {
            groupHeader("Sessões", .secondary)
            ForEach(college.prefix(40)) { s in
                HStack(spacing: 12) {
                    IconBadge(systemName: "timer", tint: Color(hex: s.subject?.colorHex ?? "8B5CF6"), size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.subject?.name ?? (s.note.isEmpty ? "Estudo" : s.note)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(Fmt.fullDate(s.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.duration(minutes: s.minutes)).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .card(padding: 12)
                .contextMenu {
                    Button("Excluir", systemImage: "trash", role: .destructive) { context.delete(s); context.saveQuietly() }
                }
            }
        }
    }
}

/// Registro de estudo com escolha da matéria.
struct StudyLogSheet: View {
    var preselected: Subject? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @State private var subject: Subject?
    @State private var minutes = 60
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Matéria", selection: $subject) {
                    Text("Sem matéria").tag(Subject?.none)
                    ForEach(subjects) { Text($0.name).tag(Optional($0)) }
                }
                Stepper("Duração: \(Fmt.duration(minutes: minutes))", value: $minutes, in: 5...720, step: 5)
                DatePicker("Quando", selection: $date, in: ...Date())
                TextField("O que estudou?", text: $note, axis: .vertical)
            }
            .navigationTitle("Registrar estudo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let s = StudySession(date: date, minutes: minutes, note: String(note.trimmed.prefix(300)))
                        context.insert(s)
                        s.subject = subject
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
            .onAppear { subject = preselected }
        }
    }
}

struct StudyGoalSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var hours = 10

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Usada no módulo Estudos e no indicador de produtividade da Home.")) {
                    Stepper("Meta: \(hours) horas por semana", value: $hours, in: 1...80)
                }
            }
            .navigationTitle("Meta semanal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        context.profile().weeklyStudyGoalMinutes = hours * 60
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
            .onAppear { hours = max(1, context.profile().weeklyStudyGoalMinutes / 60) }
        }
        .presentationDetents([.medium])
    }
}
