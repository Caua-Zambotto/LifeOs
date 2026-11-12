import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Query(sort: \FinanceTransaction.date) private var transactions: [FinanceTransaction]
    @Query private var cards: [CreditCard]
    @Query private var recurring: [RecurringEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudySession.date) private var studySessions: [StudySession]
    @Query(sort: \WorkoutSession.date) private var workouts: [WorkoutSession]
    @Query(sort: \BodyMeasurement.date) private var bodyItems: [BodyMeasurement]
    @Query private var habits: [Habit]
    @Query private var goals: [PersonalGoal]
    @Query private var subjects: [Subject]
    @State private var period: ReportPeriod = .mes
    @State private var shareURLs: [URL] = []
    @State private var showShare = false
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Período", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    Button { exportPDF() } label: { Label("Exportar PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    Button { exportCSV() } label: { Label("Exportar CSV", systemImage: "tablecells").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }

                ReportSummary(period: period, transactions: transactions, studySessions: studySessions, workouts: workouts,
                              bodyItems: bodyItems, habits: habits, goals: goals, subjects: subjects)

                Text("Finanças").font(.title3.bold())
                FinanceChartsSection(transactions: transactions, cards: cards, recurring: recurring, profile: profiles.first, period: period)
            }
            .padding()
            .padding(.bottom, 80)
        }
        .screenBackground()
        .navigationTitle("Relatórios")
        .sheet(isPresented: $showShare) { ShareSheet(items: shareURLs) }
        .alert("Erro", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) { Button("OK") {} } message: { Text(exportError ?? "") }
    }

    @MainActor
    private func exportPDF() {
        let view = VStack(alignment: .leading, spacing: 16) {
            Text("LifeOS — Relatório (\(period.label))").font(.title.bold())
            Text("Gerado em \(Fmt.dateTime(Date()))").font(.caption)
            ReportSummary(period: period, transactions: transactions, studySessions: studySessions, workouts: workouts,
                          bodyItems: bodyItems, habits: habits, goals: goals, subjects: subjects)
            FinanceChartsSection(transactions: transactions, cards: cards, recurring: recurring, profile: profiles.first, period: period)
        }
        .padding(24)
        .background(Color.white)
        do {
            let url = try PDFExporter.render(view, fileName: "LifeOS-relatorio-\(period.rawValue).pdf")
            shareURLs = [url]
            showShare = true
        } catch {
            exportError = "Não foi possível gerar o PDF."
        }
    }

    private func exportCSV() {
        let interval = period.interval()
        do {
            shareURLs = [
                try BackupService.writeTemporary(CSVExporter.transactions(transactions.filter { interval.contains($0.date) }), name: "financas.csv"),
                try BackupService.writeTemporary(CSVExporter.study(studySessions.filter { interval.contains($0.date) }), name: "estudos.csv"),
                try BackupService.writeTemporary(CSVExporter.workouts(workouts.filter { interval.contains($0.date) }), name: "treinos.csv"),
                try BackupService.writeTemporary(CSVExporter.body(bodyItems.filter { interval.contains($0.date) }), name: "corpo.csv"),
                try BackupService.writeTemporary(CSVExporter.habits(habits), name: "habitos.csv"),
            ]
            showShare = true
        } catch {
            exportError = "Não foi possível gerar os arquivos CSV."
        }
    }
}

/// Resumo de evolução por área (usado na tela e no PDF).
struct ReportSummary: View {
    let period: ReportPeriod
    let transactions: [FinanceTransaction]
    let studySessions: [StudySession]
    let workouts: [WorkoutSession]
    let bodyItems: [BodyMeasurement]
    let habits: [Habit]
    let goals: [PersonalGoal]
    let subjects: [Subject]

    var body: some View {
        let interval = period.interval()
        let income = FinanceCalculator.income(transactions, in: interval)
        let spent = FinanceCalculator.spending(transactions, in: interval)
        let studyMinutes = studySessions.filter { interval.contains($0.date) }.reduce(0) { $0 + $1.minutes }
        let workoutCount = workouts.filter { interval.contains($0.date) }.count
        let weights = bodyItems.filter { $0.weight != nil && interval.contains($0.date) }
        let days = max(1, Fmt.calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
        let activeHabits = habits.filter { !$0.isArchived }
        let habitRate = activeHabits.isEmpty ? nil : activeHabits.map { HabitActions.consistency($0, days: days) }.reduce(0, +) / Double(activeHabits.count)
        let allTopics = subjects.flatMap(\.topics)
        let academic = StudyReview.progress(allTopics.filter { $0.parent == nil })
        let studyWeeks = weeks(interval).map { w in
            DayValue(date: w, value: Double(studySessions.filter { $0.date >= w && $0.date < w.adding(days: 7) }.reduce(0) { $0 + $1.minutes }) / 60)
        }

        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(title: "Saldo do período", value: Fmt.currency(income - spent), icon: "banknote.fill", tint: .green)
                StatTile(title: "Horas estudadas", value: Fmt.duration(minutes: studyMinutes), icon: "book.fill", tint: .purple)
                StatTile(title: "Treinos", value: "\(workoutCount)", icon: "figure.run", tint: .green)
                StatTile(title: "Variação de peso",
                         value: weights.count >= 2 ? "\(Fmt.number((weights.last!.weight ?? 0) - (weights.first!.weight ?? 0))) kg" : "–",
                         icon: "scalemass.fill", tint: .orange)
                StatTile(title: "Hábitos cumpridos", value: habitRate.map(Fmt.percent) ?? "–", icon: "checkmark.circle.fill", tint: .indigo)
                StatTile(title: "Conteúdo acadêmico", value: Fmt.percent(academic), icon: "graduationcap.fill", tint: .pink)
            }
            if studyMinutes > 0 {
                VStack(alignment: .leading) {
                    Text("Horas de estudo por semana").font(.headline)
                    Chart(studyWeeks) {
                        BarMark(x: .value("Semana", $0.date, unit: .weekOfYear), y: .value("Horas", $0.value))
                            .foregroundStyle(Theme.Module.study.gradient)
                    }
                    .frame(height: 140)
                }
                .card()
            }
            if weights.count >= 2 {
                VStack(alignment: .leading) {
                    Text("Evolução do peso").font(.headline)
                    Chart(weights) { LineMark(x: .value("Data", $0.date), y: .value("Peso", $0.weight ?? 0)).foregroundStyle(.orange) }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 140)
                }
                .card()
            }
            let workoutWeeks = weeks(interval).map { w in DayValue(date: w, value: Double(workouts.filter { $0.date >= w && $0.date < w.adding(days: 7) }.count)) }
            if workoutCount > 0 {
                VStack(alignment: .leading) {
                    Text("Frequência de treinos").font(.headline)
                    Chart(workoutWeeks) { BarMark(x: .value("Semana", $0.date, unit: .weekOfYear), y: .value("Treinos", $0.value)).foregroundStyle(.green) }
                        .frame(height: 120)
                }
                .card()
            }
            let gradeData = subjects.compactMap { s in StudyReview.weightedAverage(s.grades).map { (s.name, $0) } }
            if !gradeData.isEmpty {
                VStack(alignment: .leading) {
                    Text("Média por matéria").font(.headline)
                    Chart(gradeData, id: \.0) { BarMark(x: .value("Média", $0.1), y: .value("Matéria", $0.0)).foregroundStyle(.pink) }
                        .chartXScale(domain: 0...10)
                        .frame(height: max(100, CGFloat(gradeData.count) * 32))
                }
                .card()
            }
            if !goals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Metas").font(.headline)
                    ForEach(goals.filter { !$0.isCompleted }.prefix(8)) { g in
                        HStack {
                            Text(g.title).font(.subheadline)
                            Spacer()
                            Text(Fmt.percent(g.progress)).font(.subheadline.weight(.semibold))
                        }
                        ProgressBar(value: g.progress, tint: .purple, height: 6)
                    }
                    Text("\(goals.filter(\.isCompleted).count) meta(s) concluída(s)").font(.caption).foregroundStyle(.secondary)
                }
                .card()
            }
        }
    }

    private func weeks(_ i: DateInterval) -> [Date] {
        var result: [Date] = []
        var w = i.start.startOfWeek
        while w <= i.end { result.append(w); w = w.adding(days: 7) }
        return result
    }
}
