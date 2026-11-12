import SwiftUI
import SwiftData

@Observable
@MainActor
final class AssistantViewModel {
    var pendingDraft: AssistantDraft?
    var missingField: MissingField?
    var errorMessage: String?
    let interpreter: IntentInterpreter = RuleBasedInterpreter()

    func send(_ text: String, context: ModelContext) {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        context.insert(ChatMessage(text: String(t.prefix(500)), role: .user))
        let ctx = AssistantExecutor.interpreterContext(context)

        if RX.test(#"^(cancelar|cancela|esquece|deixa pra la|nao)$"#, t.folded), pendingDraft != nil {
            pendingDraft = nil; missingField = nil
            reply("Tudo bem, cancelei.", context: context)
            return
        }

        let result: Interpretation
        if let draft = pendingDraft, let field = missingField {
            result = interpreter.complete(draft, missing: field, answer: t, context: ctx)
        } else {
            result = interpreter.interpret(t, context: ctx)
        }
        handle(result, context: context)
    }

    private func handle(_ result: Interpretation, context: ModelContext) {
        switch result {
        case .draft(let d):
            pendingDraft = d
            missingField = nil
        case .needsInfo(let d, let field, let question):
            pendingDraft = d
            missingField = field
            reply(question, context: context)
        case .notUnderstood(let help):
            pendingDraft = nil
            missingField = nil
            reply(help, context: context)
        }
        context.saveQuietly()
    }

    func confirm(context: ModelContext) {
        guard let d = pendingDraft else { return }
        do {
            let outcome = try AssistantExecutor.save(d, context: context)
            let msg = ChatMessage(text: outcome.message, role: .assistant, recordRefs: outcome.refs)
            context.insert(msg)
            context.saveQuietly()
            pendingDraft = nil
            missingField = nil
        } catch {
            errorMessage = "Não foi possível salvar. Tente novamente."
        }
    }

    func cancelDraft(context: ModelContext) {
        pendingDraft = nil
        missingField = nil
        reply("Ok, não salvei nada.", context: context)
    }

    func undo(_ message: ChatMessage, context: ModelContext) {
        do {
            try AssistantExecutor.undo(refs: message.recordRefs, context: context)
            message.isUndone = true
            reply("Registro desfeito.", context: context)
            context.saveQuietly()
        } catch {
            errorMessage = "Não foi possível desfazer."
        }
    }

    private func reply(_ text: String, context: ModelContext) {
        context.insert(ChatMessage(text: text, role: .assistant))
    }
}

struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \ChatMessage.date) private var messages: [ChatMessage]
    @State private var vm = AssistantViewModel()
    @State private var input = ""
    @State private var editing = false
    @State private var showClear = false
    @FocusState private var focused: Bool

    private let suggestions = [
        "Gastei 25 reais no almoço", "Tenho prova amanhã às 19h", "Meu peso é 78 kg",
        "Hoje treinei pernas", "Preciso revisar redes amanhã", "Conta de luz vence dia 10 e custa 150 reais",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty { intro }
                        ForEach(messages.suffix(200)) { m in
                            MessageBubble(message: m) { vm.undo(m, context: context) }
                                .id(m.id)
                        }
                        if let draft = vm.pendingDraft, vm.missingField == nil {
                            DraftCard(draft: draft,
                                      onConfirm: { withAnimation { vm.confirm(context: context) } },
                                      onEdit: { editing = true },
                                      onCancel: { withAnimation { vm.cancelDraft(context: context) } })
                                .id("draft")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in scrollDown(proxy) }
                .onChange(of: vm.pendingDraft) { _, _ in scrollDown(proxy) }
                .onAppear { scrollDown(proxy) }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .screenBackground()
            .navigationTitle("Assistente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { appState.showAssistant = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Limpar conversa", systemImage: "trash", role: .destructive) { showClear = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("Limpar o histórico de conversa? Os registros salvos continuam nas suas áreas.", isPresented: $showClear, titleVisibility: .visible) {
                Button("Limpar conversa", role: .destructive) {
                    messages.forEach { context.delete($0) }
                    context.saveQuietly()
                }
            }
            .sheet(isPresented: $editing) {
                if let d = vm.pendingDraft {
                    DraftEditor(draft: d) { edited in vm.pendingDraft = edited }
                }
            }
            .alert("Atenção", isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
                Button("OK") {}
            } message: { Text(vm.errorMessage ?? "") }
            .onAppear(perform: consumePending)
            .onChange(of: appState.pendingAssistantText) { _, _ in consumePending() }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.Module.assistant.gradient, in: Circle())
                VStack(alignment: .leading) {
                    Text("Seu assistente pessoal").font(.headline)
                    Text("Funciona offline. Nada sai do seu iPhone.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Escreva naturalmente. Eu preparo o registro e você confirma antes de salvar.")
                .font(.subheadline)
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Chip(title: s) { input = s; focused = true }
                }
            }
        }
        .card()
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(vm.missingField != nil ? "Responda aqui…" : "Escreva o que aconteceu…", text: $input, axis: .vertical)
                .focused($focused)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(input.trimmed.isEmpty ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(Theme.Module.assistant.gradient), in: Circle())
            }
            .disabled(input.trimmed.isEmpty)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let t = input
        input = ""
        withAnimation { vm.send(t, context: context) }
    }

    private func consumePending() {
        if let t = appState.pendingAssistantText {
            appState.pendingAssistantText = nil
            withAnimation { vm.send(t, context: context) }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var onUndo: () -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 50) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                Text(message.text)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        message.role == .user ? AnyShapeStyle(Theme.Module.assistant.gradient) : AnyShapeStyle(Theme.card),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .strikethrough(message.isUndone)
                HStack(spacing: 10) {
                    Text(Fmt.time(message.date)).font(.caption2).foregroundStyle(.secondary)
                    if !message.recordRefs.isEmpty && !message.isUndone {
                        Button("Desfazer", action: onUndo).font(.caption.weight(.semibold))
                    }
                    if message.isUndone { Text("Desfeito").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            if message.role == .assistant { Spacer(minLength: 50) }
        }
    }
}

struct DraftCard: View {
    let draft: AssistantDraft
    var onConfirm: () -> Void
    var onEdit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemName: draft.kind == .event ? draft.eventCategory.icon : draft.kind.icon,
                          tint: draft.kind == .event ? draft.eventCategory.color : Theme.accent)
                Text(draft.headline).font(.subheadline.weight(.semibold))
            }
            VStack(spacing: 8) {
                ForEach(Array(draft.summary.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.value).fontWeight(.medium).multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            }
            HStack(spacing: 10) {
                Button(action: onConfirm) {
                    Label("Confirmar", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onEdit) { Label("Editar", systemImage: "pencil") }
                    .buttonStyle(.bordered)
                Button(role: .destructive, action: onCancel) { Image(systemName: "xmark") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Cancelar")
            }
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
    }
}

/// Edição manual do rascunho antes de salvar.
struct DraftEditor: View {
    @State var draft: AssistantDraft
    var onSave: (AssistantDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @State private var amountText = ""
    @State private var weightText = ""
    @State private var itemsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título", text: $draft.title)
                }
                switch draft.kind {
                case .expense, .income, .bill:
                    Section("Valores") {
                        TextField("Valor (R$)", text: $amountText).keyboardType(.decimalPad)
                        Picker("Categoria", selection: $draft.financeCategory) {
                            ForEach(FinanceCategory.selectable(for: draft.kind == .income ? .receita : .despesa)) {
                                Label($0.label, systemImage: $0.icon).tag($0)
                            }
                        }
                        DatePicker(draft.kind == .bill ? "Vencimento" : "Data",
                                   selection: Binding(get: { draft.date ?? Date() }, set: { draft.date = $0 }),
                                   displayedComponents: .date)
                        if draft.kind == .bill {
                            Picker("Repetição", selection: $draft.recurrence) {
                                ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
                            }
                        }
                        if draft.kind == .expense && !cards.isEmpty {
                            Picker("Cartão", selection: Binding(get: { draft.cardName ?? "" }, set: { draft.cardName = $0.isEmpty ? nil : $0 })) {
                                Text("Nenhum (débito/dinheiro)").tag("")
                                ForEach(cards) { Text($0.name).tag($0.name) }
                            }
                            if draft.cardName != nil {
                                Stepper("Parcelas: \(draft.installments)x", value: $draft.installments, in: 1...48)
                            }
                        }
                    }
                case .event:
                    Section("Evento") {
                        Picker("Tipo", selection: $draft.eventCategory) {
                            ForEach(EventCategory.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                        }
                        Toggle("Definir horário", isOn: $draft.hasTime)
                        DatePicker("Quando", selection: Binding(get: { draft.date ?? Date() }, set: { draft.date = $0 }),
                                   displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : .date)
                        Picker("Prioridade", selection: $draft.priority) {
                            ForEach(Priority.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Matéria", selection: Binding(get: { draft.subjectName ?? "" }, set: { value in
                            draft.subjectName = value.isEmpty ? nil : value
                            draft.subjectExists = subjects.contains { s in s.name == value }
                        })) {
                            Text("Nenhuma").tag("")
                            if let n = draft.subjectName, !draft.subjectExists { Text("\(n) (nova)").tag(n) }
                            ForEach(subjects) { Text($0.name).tag($0.name) }
                        }
                    }
                case .body:
                    Section("Peso") {
                        TextField("Peso (kg)", text: $weightText).keyboardType(.decimalPad)
                        DatePicker("Data", selection: Binding(get: { draft.date ?? Date() }, set: { draft.date = $0 }), displayedComponents: .date)
                    }
                case .groceries:
                    Section("Itens (separados por vírgula)") {
                        TextField("Itens", text: $itemsText, axis: .vertical)
                        TextField("Valor gasto (opcional)", text: $amountText).keyboardType(.decimalPad)
                    }
                case .studySession, .workout:
                    Section("Duração") {
                        Stepper("\(draft.minutes ?? 0) minutos", value: Binding(get: { draft.minutes ?? 0 }, set: { draft.minutes = $0 }), in: 0...600, step: 5)
                        DatePicker("Data", selection: Binding(get: { draft.date ?? Date() }, set: { draft.date = $0 }), displayedComponents: .date)
                    }
                case .habitCheck:
                    EmptyView()
                }
            }
            .navigationTitle("Editar registro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Aplicar", action: apply) }
            }
            .onAppear {
                amountText = draft.amount.map { Fmt.number($0, digits: 2) } ?? ""
                weightText = draft.weight.map { Fmt.number($0, digits: 2) } ?? ""
                itemsText = draft.items.map(\.name).joined(separator: ", ")
            }
        }
    }

    private func apply() {
        if !amountText.isEmpty { draft.amount = Fmt.parseDecimal(amountText) }
        if draft.kind == .body { draft.weight = Fmt.parseDecimal(weightText) }
        if draft.kind == .groceries {
            let existing = Dictionary(draft.items.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            draft.items = itemsText.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }.map {
                existing[$0] ?? GroceryItem(name: $0.capitalizedFirst, quantity: 1, unit: "un")
            }
        }
        if draft.cardName == nil { draft.installments = 1 }
        if draft.kind == .event, !draft.hasTime, let d = draft.date { draft.date = d.startOfDay }
        onSave(draft)
        dismiss()
    }
}

/// Layout simples que quebra linhas (para chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            widest = max(widest, x)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
