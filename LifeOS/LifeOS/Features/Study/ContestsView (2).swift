import SwiftUI
import SwiftData
import Charts

/// Módulo EDITAIS: raiz da aba.
struct EditaisView: View {
    var body: some View {
        NavigationStack { ContestsView() }
    }
}

/// Percentual de conclusão do edital (conteúdos marcados como concluídos).
enum ContestProgress {
    static func topics(_ c: Contest) -> [StudyTopic] { c.subjects.flatMap { StudyReview.flatten($0.topics.filter { $0.parent == nil }) } }
    static func completion(_ c: Contest) -> Double {
        let all = topics(c)
        return all.isEmpty ? 0 : Double(all.filter { $0.status == .concluido }.count) / Double(all.count)
    }
}

struct ContestsView: View {
    @Query(sort: \Contest.createdAt, order: .reverse) private var contests: [Contest]
    @Query private var sessions: [StudySession]
    @State private var tab = 0
    @State private var adding = false

    private var following: [Contest] { contests.filter { $0.status != .interesse } }
    private var interest: [Contest] { contests.filter { $0.status == .interesse } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !following.isEmpty { overview }
                Picker("Lista", selection: $tab.animation(.snappy)) {
                    Text("Acompanhando (\(following.count))").tag(0)
                    Text("De interesse (\(interest.count))").tag(1)
                }
                .pickerStyle(.segmented)

                let list = tab == 0 ? following : interest
                if list.isEmpty {
                    EmptyStateView(icon: "building.columns.fill",
                                   title: tab == 0 ? "Nenhum concurso acompanhado" : "Nenhum edital de interesse",
                                   message: "Cadastre os dados a partir do edital oficial. O LifeOS não busca informações na internet nesta versão.",
                                   actionTitle: "Cadastrar concurso") { adding = true }
                }
                ForEach(list) { c in
                    NavigationLink(value: c) { ContestCard(contest: c) }.buttonStyle(.plain)
                }
            }
            .padding()
            .padding(.bottom, 16)
        }
        .screenBackground()
        .navigationTitle("Editais")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .accessibilityLabel("Cadastrar concurso")
            }
        }
        .navigationDestination(for: Contest.self) { ContestDetailView(contest: $0) }
        .sheet(isPresented: $adding) { ContestEditor(contest: nil, startAsInterest: tab == 1) }
    }

    /// Resumo da preparação: conclusão média, horas na semana e prova mais próxima.
    private var overview: some View {
        let avg = following.map(ContestProgress.completion).reduce(0, +) / Double(max(1, following.count))
        let weekStart = Date().startOfWeek
        let weekMinutes = sessions.filter { ($0.contest != nil || $0.contestSubject != nil) && $0.date >= weekStart }.reduce(0) { $0 + $1.minutes }
        let nextExam = following.compactMap { c in c.examDate.map { (c, $0) } }.filter { $0.1 >= Date().startOfDay }.min { $0.1 < $1.1 }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preparação geral").font(.subheadline.weight(.semibold)).opacity(0.9)
                    Text("\(following.count) concurso(s)").font(.title2.bold())
                    Text("\(Fmt.duration(minutes: weekMinutes)) estudadas nesta semana").font(.subheadline).opacity(0.9)
                }
                Spacer()
                ZStack {
                    RingProgress(value: avg, tint: .white, lineWidth: 7)
                    Text(Fmt.percent(avg)).font(.caption.bold())
                }
                .frame(width: 58, height: 58)
            }
            if let next = nextExam {
                let days = Fmt.daysUntil(next.1)
                Label("Próxima prova: \(next.0.organ) · \(days == 0 ? "hoje" : "em \(days) dias")", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.2), in: Capsule())
                    .lineLimit(1)
            }
        }
        .gradientCard(.contest)
    }
}

struct ContestCard: View {
    let contest: Contest
    var body: some View {
        let topics = contest.subjects.flatMap(\.topics)
        let progress = StudyReview.progress(topics.filter { $0.parent == nil })
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(contest.organ).font(.headline)
                    if !contest.role.isEmpty { Text(contest.role).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(contest.status.label).font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(contest.status.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(contest.status.color)
            }
            HStack(spacing: 16) {
                if let exam = contest.examDate {
                    let d = Fmt.daysUntil(exam)
                    Label(d >= 0 ? "Prova em \(d) dias" : "Prova em \(Fmt.short(exam))", systemImage: "calendar")
                }
                if let s = contest.salary { Label(Fmt.currency(s), systemImage: "banknote") }
                if !contest.board.isEmpty { Label(contest.board, systemImage: "building.2") }
            }
            .font(.caption).foregroundStyle(.secondary)
            if !topics.isEmpty {
                ProgressBar(value: progress, tint: Theme.Module.contest.tint)
                Text("\(Fmt.percent(progress)) do edital concluído").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

struct ContestDetailView: View {
    @Bindable var contest: Contest
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var addingSubject = false
    @State private var newSubject = ""
    @State private var addingMock = false
    @State private var addingSession = false
    @State private var importing = false
    @State private var confirmDelete = false
    @State private var addingDate = false
    @State private var editingEvent: AgendaEvent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                performance
                SectionHeader(title: "Datas importantes", actionTitle: "Adicionar") { addingDate = true }
                importantDates
                reviews
                SectionHeader(title: "Matérias do edital", actionTitle: "Adicionar") { addingSubject = true }
                if contest.subjects.isEmpty {
                    Text("Adicione as matérias do conteúdo programático.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(contest.subjects.sorted { $0.order < $1.order }) { s in
                    NavigationLink { ContestSubjectView(contestSubject: s) } label: { contestSubjectRow(s) }
                        .buttonStyle(.plain)
                }
                SectionHeader(title: "Simulados", actionTitle: "Registrar") { addingMock = true }
                mockSection
                SectionHeader(title: "Edital e documentos", actionTitle: "Importar PDF") { importing = true }
                if contest.documents.isEmpty {
                    Text("Importe o PDF do edital para consultar offline.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(contest.documents) { DocumentRow(document: $0) }
                if !contest.requirements.isEmpty || !contest.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !contest.requirements.isEmpty {
                            Text("Requisitos").font(.headline)
                            Text(contest.requirements).font(.subheadline)
                        }
                        if !contest.notes.isEmpty {
                            Text("Observações").font(.headline)
                            Text(contest.notes).font(.subheadline)
                        }
                    }
                    .card()
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .screenBackground()
        .navigationTitle(contest.organ)
        .toolbar {
            Menu {
                Button("Editar", systemImage: "pencil") { editing = true }
                Button("Registrar horas de estudo", systemImage: "timer") { addingSession = true }
                Button("Excluir concurso", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(isPresented: $editing) { ContestEditor(contest: contest) }
        .sheet(isPresented: $addingMock) { MockExamEditor(contest: contest) }
        .sheet(isPresented: $addingSession) { StudySessionEditor(subject: nil, contest: contest, contestSubject: nil) }
        .sheet(isPresented: $importing) { VaultImportSheet(contest: contest, defaultCategory: .edital) }
        .sheet(isPresented: $addingDate) { EventEditorView(event: nil, defaultCategory: .dataImportante, defaultContest: contest) }
        .sheet(item: $editingEvent) { EventEditorView(event: $0) }
        .alert("Nova matéria", isPresented: $addingSubject) {
            TextField("Nome", text: $newSubject)
            Button("Adicionar") {
                if !newSubject.trimmed.isEmpty {
                    let s = ContestSubject(name: newSubject.trimmed, order: contest.subjects.count)
                    context.insert(s)
                    s.contest = contest
                    context.saveQuietly()
                }
                newSubject = ""
            }
            Button("Cancelar", role: .cancel) { newSubject = "" }
        }
        .confirmationDialog("Excluir este concurso e todo o seu progresso?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                NotificationScheduler.cancel(contest: contest)
                context.delete(contest)
                context.saveQuietly()
                dismiss()
            }
        }
    }

    /// Datas cadastradas no edital + eventos ligados a este concurso (aparecem também no Calendário).
    private var importantDates: some View {
        let today = Date().startOfDay
        let fixed: [(String, Date?, String)] = [
            ("Início das inscrições", contest.registrationStart, "pencil.line"),
            ("Fim das inscrições", contest.registrationEnd, "pencil.and.list.clipboard"),
            ("Prova", contest.examDate, "building.columns.fill"),
        ]
        let events = contest.events.sorted { $0.start < $1.start }
        return VStack(spacing: 0) {
            ForEach(Array(fixed.enumerated()), id: \.offset) { _, item in
                if let date = item.1 {
                    dateRow(item.0, date, item.2, past: date < today)
                }
            }
            ForEach(events) { e in
                Button { editingEvent = e } label: {
                    dateRow(e.title, e.start, e.category.icon, past: e.start < today || e.isDone)
                }
                .buttonStyle(.plain)
            }
            if fixed.allSatisfy({ $0.1 == nil }) && events.isEmpty {
                Text("Cadastre as datas do edital (inscrições, prova, resultado, recursos…).")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .card(padding: 12)
    }

    private func dateRow(_ title: String, _ date: Date, _ icon: String, past: Bool) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, tint: past ? .gray : Theme.Module.contest.tint, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(past ? .secondary : .primary)
                Text(Fmt.fullDate(date)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !past {
                let d = Fmt.daysUntil(date)
                Text(d == 0 ? "Hoje" : "\(d) dias").font(.caption.weight(.bold)).foregroundStyle(Theme.Module.contest.tint)
            }
        }
        .padding(.vertical, 6)
    }

    /// Revisões pendentes dos conteúdos deste edital.
    @ViewBuilder
    private var reviews: some View {
        let due = ContestProgress.topics(contest).filter { StudyReview.isDue($0) }
        if !due.isEmpty {
            SectionHeader(title: "Revisões para hoje")
            VStack(spacing: 8) {
                ForEach(due.prefix(6)) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.subheadline.weight(.semibold))
                            Text(t.contestSubject?.name ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revisado") { StudyReview.markReviewed(t); context.saveQuietly() }
                            .buttonStyle(.borderedProminent).font(.caption.weight(.semibold))
                    }
                }
            }
            .card(padding: 12)
        }
    }

    private var header: some View {
        let completion = ContestProgress.completion(contest)
        let topicCount = ContestProgress.topics(contest).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(contest.role.isEmpty ? contest.organ : contest.role).font(.title2.bold())
                    Text(contest.status.label).font(.subheadline.weight(.semibold)).opacity(0.9)
                }
                Spacer()
                VStack(spacing: 4) {
                    ZStack {
                        RingProgress(value: completion, tint: .white, lineWidth: 7)
                        Text(Fmt.percent(completion)).font(.caption.bold())
                    }
                    .frame(width: 60, height: 60)
                    Text(topicCount == 0 ? "sem conteúdos" : "do edital").font(.caption2.weight(.semibold)).opacity(0.9)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                info("Banca", contest.board)
                info("Área", contest.area)
                info("Salário", contest.salary.map(Fmt.currency) ?? "")
                info("Vagas", contest.vacancies.map(String.init) ?? "")
                info("Inscrições até", contest.registrationEnd.map(Fmt.short) ?? "")
                info("Prova", contest.examDate.map(Fmt.short) ?? "")
            }
            if let url = URL(string: contest.officialLink), contest.officialLink.lowercased().hasPrefix("https://") {
                Link(destination: url) { Label("Abrir link oficial", systemImage: "safari") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .gradientCard(.contest)
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).opacity(0.85)
            Text(value.isEmpty ? "–" : value).font(.subheadline.weight(.semibold))
        }
    }

    private var performance: some View {
        let sessions = contest.sessions
        let minutes = sessions.reduce(0) { $0 + $1.minutes }
        let logs = contest.subjects.flatMap(\.questionLogs)
        let total = logs.reduce(0) { $0 + $1.total }
        let correct = logs.reduce(0) { $0 + $1.correct }
        let weeks = (0..<8).reversed().map { Date().startOfWeek.adding(days: -7 * $0) }
        let weekly = weeks.map { w in
            DayValue(date: w, value: Double(sessions.filter { $0.date >= w && $0.date < w.adding(days: 7) }.reduce(0) { $0 + $1.minutes }) / 60)
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "Horas estudadas", value: Fmt.duration(minutes: minutes), icon: "timer", tint: .indigo)
                StatTile(title: "Acertos", value: total > 0 ? Fmt.percent(Double(correct) / Double(total)) : "–", icon: "target", tint: .green)
                StatTile(title: "Questões", value: "\(total)", icon: "list.number", tint: .orange)
            }
            if minutes > 0 {
                VStack(alignment: .leading) {
                    Text("Horas por semana").font(.subheadline.weight(.semibold))
                    Chart(weekly) { w in
                        BarMark(x: .value("Semana", w.date, unit: .weekOfYear), y: .value("Horas", w.value))
                            .foregroundStyle(Theme.Module.contest.gradient).cornerRadius(5)
                    }
                    .frame(height: 140)
                }
                .card()
            }
        }
    }

    private func contestSubjectRow(_ s: ContestSubject) -> some View {
        let progress = StudyReview.progress(s.topics.filter { $0.parent == nil })
        let total = s.questionLogs.reduce(0) { $0 + $1.total }
        let correct = s.questionLogs.reduce(0) { $0 + $1.correct }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(s.name).font(.subheadline.weight(.semibold))
                ProgressBar(value: progress, tint: Theme.Module.contest.tint, height: 6)
                Text("\(Fmt.percent(progress)) do conteúdo" + (total > 0 ? " · \(Fmt.percent(Double(correct) / Double(total))) de acertos" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .card(padding: 14)
    }

    @ViewBuilder
    private var mockSection: some View {
        let mocks = contest.mockExams.sorted { $0.date < $1.date }
        if mocks.isEmpty {
            Text("Registre simulados para acompanhar sua evolução.").font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if mocks.count >= 2 {
                    Chart(mocks) { m in
                        LineMark(x: .value("Data", m.date), y: .value("Acertos %", m.accuracy * 100))
                        PointMark(x: .value("Data", m.date), y: .value("Acertos %", m.accuracy * 100))
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 150)
                }
                ForEach(mocks.reversed()) { m in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(m.title).font(.subheadline.weight(.semibold))
                            Text(Fmt.short(m.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(m.correct)/\(m.total) · \(Fmt.percent(m.accuracy))").font(.subheadline.weight(.semibold))
                    }
                    .contextMenu {
                        Button("Excluir", systemImage: "trash", role: .destructive) { context.delete(m); context.saveQuietly() }
                    }
                }
            }
            .card()
        }
    }
}

struct ContestSubjectView: View {
    @Bindable var contestSubject: ContestSubject
    @Environment(\.modelContext) private var context
    @State private var total = ""
    @State private var correct = ""
    @State private var addingSession = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Registrar questões").font(.headline)
                    HStack {
                        TextField("Total", text: $total).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        TextField("Acertos", text: $correct).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Button("Salvar", action: saveQuestions).buttonStyle(.borderedProminent)
                    }
                    let logs = contestSubject.questionLogs.sorted { $0.date < $1.date }
                    if logs.count >= 2 {
                        Chart(logs) { l in
                            BarMark(x: .value("Data", l.date, unit: .day), y: .value("Acertos %", l.total > 0 ? Double(l.correct) / Double(l.total) * 100 : 0))
                                .foregroundStyle(Theme.Module.contest.gradient)
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 130)
                    }
                }
                .card()
                Button { addingSession = true } label: { Label("Registrar horas de estudo", systemImage: "timer") }
                    .buttonStyle(.bordered)
                TopicStatusChart(topics: contestSubject.topics).card()
                TopicTreeView(topics: contestSubject.topics) { title, parent in
                    let t = StudyTopic(title: title, order: parent?.children.count ?? contestSubject.topics.count)
                    context.insert(t)
                    t.contestSubject = contestSubject
                    t.parent = parent
                    context.saveQuietly()
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .screenBackground()
        .navigationTitle(contestSubject.name)
        .sheet(isPresented: $addingSession) {
            StudySessionEditor(subject: nil, contest: contestSubject.contest, contestSubject: contestSubject)
        }
    }

    private func saveQuestions() {
        guard let t = Int(total), let c = Int(correct), t > 0, c >= 0, c <= t else { return }
        let log = QuestionLog(total: t, correct: c)
        context.insert(log)
        log.contestSubject = contestSubject
        context.saveQuietly()
        total = ""; correct = ""
    }
}

struct ContestEditor: View {
    let contest: Contest?
    var startAsInterest = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var organ = ""
    @State private var role = ""
    @State private var area = ""
    @State private var salary = ""
    @State private var vacancies = ""
    @State private var requirements = ""
    @State private var board = ""
    @State private var link = ""
    @State private var status: ContestStatus = .previsto
    @State private var notes = ""
    @State private var hasRegStart = false
    @State private var regStart = Date()
    @State private var hasRegEnd = false
    @State private var regEnd = Date()
    @State private var hasExam = false
    @State private var exam = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Identificação") {
                    TextField("Órgão", text: $organ)
                    TextField("Cargo", text: $role)
                    TextField("Área", text: $area)
                    TextField("Banca", text: $board)
                    Picker("Situação", selection: $status) {
                        ForEach(ContestStatus.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Vagas e remuneração") {
                    TextField("Salário (R$)", text: $salary).keyboardType(.decimalPad)
                    TextField("Número de vagas", text: $vacancies).keyboardType(.numberPad)
                    TextField("Requisitos", text: $requirements, axis: .vertical)
                }
                Section(footer: Text("Use apenas datas confirmadas no edital oficial.")) {
                    Toggle("Início das inscrições", isOn: $hasRegStart)
                    if hasRegStart { DatePicker("Data", selection: $regStart, displayedComponents: .date) }
                    Toggle("Fim das inscrições", isOn: $hasRegEnd)
                    if hasRegEnd { DatePicker("Data", selection: $regEnd, displayedComponents: .date) }
                    Toggle("Data da prova", isOn: $hasExam)
                    if hasExam { DatePicker("Data", selection: $exam, displayedComponents: [.date, .hourAndMinute]) }
                }
                Section("Link oficial") {
                    TextField("https://", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Observações") { TextField("Notas", text: $notes, axis: .vertical) }
            }
            .navigationTitle(contest == nil ? "Novo concurso" : "Editar concurso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(organ.trimmed.isEmpty) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let c = contest else { status = startAsInterest ? .interesse : .previsto; return }
        organ = c.organ; role = c.role; area = c.area; board = c.board; status = c.status
        salary = c.salary.map { Fmt.number($0, digits: 2) } ?? ""
        vacancies = c.vacancies.map(String.init) ?? ""
        requirements = c.requirements; link = c.officialLink; notes = c.notes
        if let d = c.registrationStart { hasRegStart = true; regStart = d }
        if let d = c.registrationEnd { hasRegEnd = true; regEnd = d }
        if let d = c.examDate { hasExam = true; exam = d }
    }

    private func save() {
        let c = contest ?? Contest(organ: organ, role: role)
        c.organ = organ.trimmed; c.role = role.trimmed; c.area = area.trimmed; c.board = board.trimmed
        c.status = status
        c.salary = Fmt.parseDecimal(salary)
        c.vacancies = Int(vacancies.trimmed)
        c.requirements = requirements
        let l = link.trimmed
        c.officialLink = l.isEmpty || l.lowercased().hasPrefix("https://") ? l : "https://" + l
        c.notes = notes
        c.registrationStart = hasRegStart ? regStart : nil
        c.registrationEnd = hasRegEnd ? regEnd : nil
        c.examDate = hasExam ? exam : nil
        if contest == nil { context.insert(c) }
        context.saveQuietly()
        NotificationScheduler.schedule(c)
        dismiss()
    }
}

struct MockExamEditor: View {
    let contest: Contest
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var total = ""
    @State private var correct = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome do simulado", text: $title)
                TextField("Total de questões", text: $total).keyboardType(.numberPad)
                TextField("Acertos", text: $correct).keyboardType(.numberPad)
                DatePicker("Data", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Simulado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        guard let t = Int(total), let c = Int(correct), t > 0, c >= 0, c <= t else { return }
                        let m = MockExam(title: title.trimmed.isEmpty ? "Simulado" : title.trimmed, date: date, total: t, correct: c)
                        context.insert(m)
                        m.contest = contest
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
        }
    }
}
