import SwiftUI
import SwiftData
import Charts

struct CollegeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query private var profiles: [UserProfile]
    @State private var addingSubject = false
    @State private var editingCourse = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                courseCard
                SectionHeader(title: "Matérias", actionTitle: "Adicionar") { addingSubject = true }
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
            .padding()
            .padding(.bottom, 80)
        }
        .screenBackground()
        .navigationTitle("Faculdade")
        .navigationDestination(for: Subject.self) { SubjectDetailView(subject: $0) }
        .sheet(isPresented: $addingSubject) { SubjectEditor(subject: nil) }
        .sheet(isPresented: $editingCourse) { CourseEditor() }
    }

    private var courseCard: some View {
        let p = profiles.first
        let allTopics = subjects.flatMap(\.topics)
        let progress = StudyReview.progress(allTopics.filter { $0.parent == nil })
        let averages = subjects.compactMap { StudyReview.weightedAverage($0.grades) }
        let avg = averages.isEmpty ? nil : averages.reduce(0, +) / Double(averages.count)
        return Button { editingCourse = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p?.course.isEmpty == false ? p!.course : "Toque para informar seu curso").font(.title3.bold())
                        Text([p?.institution ?? "", p?.semester.isEmpty == false ? "\(p!.semester)º semestre" : ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).opacity(0.9)
                    }
                    Spacer()
                    Image(systemName: "graduationcap.fill").font(.system(size: 36))
                }
                HStack(spacing: 24) {
                    stat("\(subjects.count)", "matérias")
                    stat(Fmt.percent(progress), "conteúdo")
                    stat(avg.map { Fmt.number($0) } ?? "–", "média geral")
                }
            }
            .gradientCard(.study)
        }
        .buttonStyle(.plain)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.title2.bold())
            Text(l).font(.caption).opacity(0.9)
        }
    }
}

struct SubjectCard: View {
    let subject: Subject
    var body: some View {
        let progress = StudyReview.progress(subject.topics.filter { $0.parent == nil })
        let next = subject.events.filter { !$0.isDone && $0.start >= Date().startOfDay }.min { $0.start < $1.start }
        HStack(spacing: 14) {
            ZStack {
                RingProgress(value: progress, tint: Color(hex: subject.colorHex), lineWidth: 6)
                Text(Fmt.percent(progress)).font(.caption2.weight(.bold))
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name).font(.headline)
                if !subject.professor.isEmpty { Text(subject.professor).font(.caption).foregroundStyle(.secondary) }
                if let next {
                    Label("\(next.category.label) \(Fmt.relativeDay(next.start))", systemImage: next.category.icon)
                        .font(.caption.weight(.semibold)).foregroundStyle(next.category.color)
                }
            }
            Spacer()
            if let avg = StudyReview.weightedAverage(subject.grades) {
                Text(Fmt.number(avg)).font(.title3.bold()).foregroundStyle(avg >= 6 ? .green : .orange)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .card()
    }
}

struct SubjectDetailView: View {
    @Bindable var subject: Subject
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var addingEvent: EventCategory?
    @State private var editingEvent: AgendaEvent?
    @State private var addingGrade = false
    @State private var addingSession = false
    @State private var importing = false
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Seção", selection: $tab) {
                    Text("Conteúdo").tag(0)
                    Text("Avaliações").tag(1)
                    Text("Notas").tag(2)
                    Text("Materiais").tag(3)
                }
                .pickerStyle(.segmented)

                switch tab {
                case 0: contentTab
                case 1: evaluationsTab
                case 2: gradesTab
                default: materialsTab
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .screenBackground()
        .navigationTitle(subject.name)
        .toolbar {
            Menu {
                Button("Editar matéria", systemImage: "pencil") { editing = true }
                Button("Registrar estudo", systemImage: "timer") { addingSession = true }
                Button("Excluir matéria", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(item: $addingEvent) { cat in EventEditorView(event: nil, defaultCategory: cat, defaultSubject: subject) }
        .sheet(item: $editingEvent) { EventEditorView(event: $0) }
        .sheet(isPresented: $addingGrade) { GradeEditor(subject: subject) }
        .sheet(isPresented: $addingSession) { StudySessionEditor(subject: subject, contest: nil, contestSubject: nil) }
        .sheet(isPresented: $importing) { VaultImportSheet(subject: subject) }
        .sheet(isPresented: $editing) { SubjectEditor(subject: subject) }
        .confirmationDialog("Excluir \(subject.name)? Assuntos e notas serão apagados; provas na agenda são mantidas.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                context.delete(subject)
                context.saveQuietly()
                dismiss()
            }
        }
    }

    private var contentTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Progresso").font(.headline)
                TopicStatusChart(topics: subject.topics)
                let minutes = subject.sessions.reduce(0) { $0 + $1.minutes }
                if minutes > 0 {
                    Label("\(Fmt.duration(minutes: minutes)) estudadas", systemImage: "timer").font(.subheadline)
                }
            }
            .card()
            TopicTreeView(topics: subject.topics) { title, parent in
                let t = StudyTopic(title: title, order: (parent?.children.count ?? subject.topics.count))
                context.insert(t)
                t.subject = subject
                t.parent = parent
                context.saveQuietly()
            }
        }
    }

    private var evaluationsTab: some View {
        let items = subject.events.sorted { $0.start < $1.start }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { addingEvent = .prova } label: { Label("Prova", systemImage: "plus") }.buttonStyle(.bordered)
                Button { addingEvent = .trabalho } label: { Label("Trabalho", systemImage: "plus") }.buttonStyle(.bordered)
                Button { addingEvent = .entrega } label: { Label("Entrega", systemImage: "plus") }.buttonStyle(.bordered)
            }
            if items.isEmpty {
                Text("Provas, trabalhos e entregas desta matéria aparecem aqui e na Agenda.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(items) { e in
                EventRow(occurrence: AgendaOccurrence(event: e, date: e.start))
                    .onTapGesture { editingEvent = e }
            }
        }
    }

    private var gradesTab: some View {
        let grades = subject.grades.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let avg = StudyReview.weightedAverage(grades) {
                    VStack(alignment: .leading) {
                        Text("Média ponderada").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.number(avg, digits: 2)).font(.largeTitle.bold()).foregroundStyle(avg >= 6 ? .green : .orange)
                    }
                }
                Spacer()
                Button { addingGrade = true } label: { Label("Nota", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }
            if grades.count >= 2 {
                Chart(grades) { g in
                    LineMark(x: .value("Data", g.date), y: .value("Nota", g.normalized))
                    PointMark(x: .value("Data", g.date), y: .value("Nota", g.normalized))
                }
                .chartYScale(domain: 0...10)
                .frame(height: 160)
                .card()
            }
            ForEach(grades) { g in
                HStack {
                    VStack(alignment: .leading) {
                        Text(g.title).font(.subheadline.weight(.semibold))
                        Text("\(Fmt.short(g.date)) · peso \(Fmt.number(g.weight))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Fmt.number(g.value)) / \(Fmt.number(g.maxValue))").font(.headline)
                }
                .card(padding: 12)
                .contextMenu {
                    Button("Excluir", systemImage: "trash", role: .destructive) { context.delete(g); context.saveQuietly() }
                }
            }
        }
    }

    private var materialsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { importing = true } label: { Label("Anexar PDF ou imagem", systemImage: "paperclip") }
                .buttonStyle(.borderedProminent)
            if subject.documents.isEmpty {
                Text("Os arquivos ficam criptografados no cofre de documentos.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(subject.documents.sorted { $0.createdAt > $1.createdAt }) { d in
                DocumentRow(document: d)
            }
        }
    }
}

struct SubjectEditor: View {
    let subject: Subject?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var professor = ""
    @State private var semester = ""
    @State private var notes = ""
    @State private var color = "8B5CF6"
    private let colors = ["8B5CF6", "EC4899", "3B82F6", "10B981", "F59E0B", "EF4444", "14B8A6", "6366F1"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome da matéria", text: $name)
                TextField("Professor(a)", text: $professor)
                TextField("Semestre", text: $semester)
                Section("Cor") {
                    HStack {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.primary, lineWidth: color == c ? 2 : 0))
                                .onTapGesture { color = c }
                        }
                    }
                }
                Section("Observações") { TextField("Anotações", text: $notes, axis: .vertical) }
            }
            .navigationTitle(subject == nil ? "Nova matéria" : "Editar matéria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let s = subject ?? Subject(name: name)
                        s.name = name.trimmed; s.professor = professor; s.semester = semester; s.notes = notes; s.colorHex = color
                        if subject == nil { context.insert(s) }
                        context.saveQuietly()
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear {
                if let s = subject { name = s.name; professor = s.professor; semester = s.semester; notes = s.notes; color = s.colorHex }
            }
        }
    }
}

struct CourseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var course = ""
    @State private var institution = ""
    @State private var semester = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Curso", text: $course)
                TextField("Instituição", text: $institution)
                TextField("Semestre atual", text: $semester).keyboardType(.numberPad)
            }
            .navigationTitle("Meu curso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let p = context.profile()
                        p.course = course.trimmed; p.institution = institution.trimmed; p.semester = semester.trimmed
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let p = context.profile()
                course = p.course; institution = p.institution; semester = p.semester
            }
        }
    }
}

struct GradeEditor: View {
    let subject: Subject
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var value = ""
    @State private var maxValue = "10"
    @State private var weight = "1"
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Avaliação (ex.: P1)", text: $title)
                TextField("Nota obtida", text: $value).keyboardType(.decimalPad)
                TextField("Nota máxima", text: $maxValue).keyboardType(.decimalPad)
                TextField("Peso", text: $weight).keyboardType(.decimalPad)
                DatePicker("Data", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Nova nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        guard let v = Fmt.parseDecimal(value), let m = Fmt.parseDecimal(maxValue), m > 0, v >= 0, v <= m else { return }
                        let g = Grade(title: title.trimmed.isEmpty ? "Avaliação" : title.trimmed, value: v, maxValue: m,
                                      weight: Fmt.parseDecimal(weight) ?? 1, date: date)
                        context.insert(g)
                        g.subject = subject
                        context.saveQuietly()
                        dismiss()
                    }
                    .disabled(Fmt.parseDecimal(value) == nil)
                }
            }
        }
    }
}

struct StudySessionEditor: View {
    let subject: Subject?
    let contest: Contest?
    let contestSubject: ContestSubject?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 60
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Duração: \(Fmt.duration(minutes: minutes))", value: $minutes, in: 5...600, step: 5)
                DatePicker("Data", selection: $date)
                TextField("O que estudou?", text: $note, axis: .vertical)
            }
            .navigationTitle("Registrar estudo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let s = StudySession(date: date, minutes: minutes, note: note)
                        context.insert(s)
                        s.subject = subject
                        s.contest = contest ?? contestSubject?.contest
                        s.contestSubject = contestSubject
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
        }
    }
}
