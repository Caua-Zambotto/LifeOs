import SwiftUI
import SwiftData
import UIKit

/// Registro do treino DURANTE a execução: uma única tela com todos os exercícios,
/// séries marcáveis, ajuste rápido de carga/repetições e cronômetro de descanso.
struct LiveWorkoutView: View {
    struct SetLog: Identifiable {
        let id = UUID()
        var reps: Int
        var load: Double
        var done = false
    }
    struct ExerciseLog: Identifiable {
        let id = UUID()
        var name: String
        var restSeconds: Int
        var sets: [SetLog]
    }

    let plan: WorkoutPlan?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var exercises: [ExerciseLog]
    @State private var startedAt = Date()
    @State private var restEnd: Date?
    @State private var updatePlan = true
    @State private var addingExercise = false
    @State private var newExerciseName = ""
    @State private var confirmDiscard = false
    @State private var confirmFinish = false
    private let restNotificationID = "live.rest"

    init(plan: WorkoutPlan?) {
        self.plan = plan
        _title = State(initialValue: plan?.name ?? "Treino livre")
        let logs: [ExerciseLog] = (plan?.sortedExercises ?? []).map { ex in
            let sets = (0..<max(1, ex.sets)).map { _ in SetLog(reps: ex.reps, load: ex.load) }
            return ExerciseLog(name: ex.name, restSeconds: ex.restSeconds, sets: sets)
        }
        _exercises = State(initialValue: logs)
    }

    private var doneSets: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    private var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    private var volume: Double {
        exercises.reduce(0) { acc, ex in acc + ex.sets.filter(\.done).reduce(0) { $0 + $1.load * Double($1.reps) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    if let restEnd { restBanner(restEnd) }
                    if exercises.isEmpty {
                        EmptyStateView(icon: "dumbbell", title: "Adicione os exercícios",
                                       message: "Inclua cada exercício e marque as séries conforme for fazendo.",
                                       actionTitle: "Adicionar exercício") { addingExercise = true }
                    }
                    ForEach($exercises) { $ex in
                        exerciseCard($ex)
                    }
                    if !exercises.isEmpty {
                        Button { addingExercise = true } label: {
                            Label("Adicionar exercício", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if plan != nil {
                        Toggle("Atualizar cargas da ficha ao concluir", isOn: $updatePlan)
                            .font(.subheadline)
                            .card(padding: 12)
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { if doneSets > 0 { confirmDiscard = true } else { close() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") { confirmFinish = true }
                        .fontWeight(.bold)
                        .disabled(doneSets == 0)
                }
            }
            .alert("Novo exercício", isPresented: $addingExercise) {
                TextField("Nome do exercício", text: $newExerciseName)
                Button("Adicionar") {
                    let name = newExerciseName.trimmed
                    if !name.isEmpty {
                        withAnimation { exercises.append(ExerciseLog(name: String(name.prefix(80)), restSeconds: 60, sets: [SetLog(reps: 10, load: 0)])) }
                    }
                    newExerciseName = ""
                }
                Button("Cancelar", role: .cancel) { newExerciseName = "" }
            }
            .confirmationDialog("Descartar este treino? As séries marcadas não serão salvas.", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Descartar treino", role: .destructive) { close() }
            }
            .confirmationDialog("Concluir e salvar o treino com \(doneSets) série(s)?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Salvar treino") { finish() }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                NotificationService.shared.cancel([restNotificationID])
            }
        }
    }

    // MARK: Componentes

    private var statusCard: some View {
        HStack(spacing: 0) {
            TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                stat("Tempo", clock(ctx.date.timeIntervalSince(startedAt)))
            }
            stat("Séries", "\(doneSets)/\(totalSets)")
            stat("Volume", "\(Fmt.number(volume, digits: 0)) kg")
        }
        .card(padding: 14)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func restBanner(_ end: Date) -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            let remaining = max(0, end.timeIntervalSince(ctx.date))
            HStack(spacing: 12) {
                Image(systemName: remaining > 0 ? "timer" : "checkmark.circle.fill").font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(remaining > 0 ? "Descanso" : "Descanso concluído").font(.caption.weight(.semibold)).opacity(0.9)
                    Text(remaining > 0 ? clock(remaining) : "Próxima série!").font(.title2.bold()).monospacedDigit()
                }
                Spacer()
                Button(remaining > 0 ? "+15s" : "OK") {
                    if remaining > 0 { startRest(seconds: Int(remaining) + 15) } else { stopRest() }
                }
                .buttonStyle(.bordered).tint(.white)
                if remaining > 0 {
                    Button("Pular") { stopRest() }.buttonStyle(.bordered).tint(.white)
                }
            }
            .gradientCard(remaining > 0 ? .agenda : .fitness)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func exerciseCard(_ ex: Binding<ExerciseLog>) -> some View {
        let item = ex.wrappedValue
        let allDone = !item.sets.isEmpty && item.sets.allSatisfy(\.done)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: allDone ? "checkmark.seal.fill" : "dumbbell.fill")
                    .foregroundStyle(allDone ? .green : Theme.Module.fitness.tint)
                Text(item.name).font(.headline).lineLimit(2)
                Spacer()
                Menu {
                    Button("Adicionar série", systemImage: "plus") { addSet(ex) }
                    if item.sets.count > 1 {
                        Button("Remover última série", systemImage: "minus") { _ = ex.wrappedValue.sets.popLast() }
                    }
                    Picker("Descanso", selection: ex.restSeconds) {
                        ForEach([30, 45, 60, 90, 120, 180], id: \.self) { Text("Descanso \($0)s").tag($0) }
                    }
                    Button("Remover exercício", systemImage: "trash", role: .destructive) {
                        withAnimation { exercises.removeAll { $0.id == item.id } }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Opções de \(item.name)")
            }
            HStack {
                Text("Série").frame(width: 40, alignment: .leading)
                Text("Carga (kg)").frame(maxWidth: .infinity)
                Text("Reps").frame(maxWidth: .infinity)
                Text("").frame(width: 40)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(ex.wrappedValue.sets.indices, id: \.self) { i in
                setRow(ex, index: i)
            }
            Button { addSet(ex) } label: { Label("Série", systemImage: "plus").font(.caption.weight(.semibold)) }
        }
        .card()
    }

    private func setRow(_ ex: Binding<ExerciseLog>, index i: Int) -> some View {
        let set = i < ex.wrappedValue.sets.count ? ex.wrappedValue.sets[i] : SetLog(reps: 0, load: 0)
        return HStack(spacing: 8) {
            Text("\(i + 1)")
                .font(.subheadline.weight(.bold))
                .frame(width: 28, height: 28)
                .background((set.done ? Color.green : Color.secondary).opacity(0.15), in: Circle())
                .frame(width: 40, alignment: .leading)
            stepper(value: Binding(get: { safe(ex, i)?.load ?? 0 }, set: { v in if i < ex.wrappedValue.sets.count { ex.wrappedValue.sets[i].load = max(0, v) } }),
                    step: 2.5, format: { Fmt.number($0) })
            stepper(value: Binding(get: { Double(safe(ex, i)?.reps ?? 0) }, set: { v in if i < ex.wrappedValue.sets.count { ex.wrappedValue.sets[i].reps = max(1, Int(v)) } }),
                    step: 1, format: { "\(Int($0))" })
            Button {
                let wasDone = ex.wrappedValue.sets[i].done
                withAnimation(.snappy) { ex.wrappedValue.sets[i].done.toggle() }
                if !wasDone {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    startRest(seconds: ex.wrappedValue.restSeconds)
                }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(set.done ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 40)
            .accessibilityLabel(set.done ? "Série \(i + 1) feita" : "Marcar série \(i + 1) como feita")
        }
        .opacity(set.done ? 0.75 : 1)
    }

    /// Botões − / + grandes, fáceis de tocar com a mão suada.
    private func stepper(value: Binding<Double>, step: Double, format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 0) {
            Button { value.wrappedValue -= step } label: {
                Image(systemName: "minus").frame(width: 30, height: 34)
            }
            Text(format(value.wrappedValue))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 36)
                .lineLimit(1).minimumScaleFactor(0.7)
            Button { value.wrappedValue += step } label: {
                Image(systemName: "plus").frame(width: 30, height: 34)
            }
        }
        .buttonStyle(.plain)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    // MARK: Ações

    private func safe(_ ex: Binding<ExerciseLog>, _ i: Int) -> SetLog? {
        i < ex.wrappedValue.sets.count ? ex.wrappedValue.sets[i] : nil
    }

    private func addSet(_ ex: Binding<ExerciseLog>) {
        let last = ex.wrappedValue.sets.last
        withAnimation { ex.wrappedValue.sets.append(SetLog(reps: last?.reps ?? 10, load: last?.load ?? 0)) }
    }

    private func startRest(seconds: Int) {
        guard seconds > 0 else { return }
        let end = Date().addingTimeInterval(Double(seconds))
        withAnimation { restEnd = end }
        // Aviso local caso a tela esteja bloqueada ou o app em segundo plano.
        NotificationService.shared.schedule(id: restNotificationID, title: "Descanso concluído",
                                            body: "Hora da próxima série.", fireDate: end, category: .treinos)
    }

    private func stopRest() {
        withAnimation { restEnd = nil }
        NotificationService.shared.cancel([restNotificationID])
    }

    private func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func finish() {
        let session = WorkoutSession(date: startedAt, title: title)
        session.durationMinutes = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        session.planID = plan?.id
        session.muscleGroups = RuleBasedInterpreter.muscleGroups
            .filter { RX.test(#"\b(?:\#($0.pattern))\b"#, title.folded) }.map(\.name)
        context.insert(session)
        var order = 0
        for ex in exercises {
            let done = ex.sets.filter(\.done)
            guard !done.isEmpty else { continue }
            let reps = Int((Double(done.reduce(0) { $0 + $1.reps }) / Double(done.count)).rounded())
            let load = done.map(\.load).max() ?? 0
            session.entries.append(ExerciseEntry(name: ex.name, sets: done.count, reps: reps, load: load, order: order))
            order += 1
            if let plan, updatePlan, let template = plan.exercises.first(where: { $0.name == ex.name }) {
                template.load = load
                template.reps = reps
                template.sets = ex.sets.count
                template.restSeconds = ex.restSeconds
            }
        }
        context.saveQuietly()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        close()
    }

    private func close() {
        NotificationService.shared.cancel([restNotificationID])
        dismiss()
    }
}

struct WorkoutGoalSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var goal = 4

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Usada no módulo Treino e no indicador de produtividade da Home.")) {
                    Stepper("Meta: \(goal) treino(s) por semana", value: $goal, in: 1...14)
                }
            }
            .navigationTitle("Meta semanal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        context.profile().weeklyWorkoutGoal = goal
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
            .onAppear { goal = context.profile().weeklyWorkoutGoal }
        }
        .presentationDetents([.medium])
    }
}
