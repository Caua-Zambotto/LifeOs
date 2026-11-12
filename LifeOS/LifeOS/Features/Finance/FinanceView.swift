import SwiftUI
import SwiftData
import Charts

struct FinanceView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var transactions: [FinanceTransaction]
    @Query(sort: \RecurringEntry.dueDate) private var recurring: [RecurringEntry]
    @Query private var debts: [Debt]
    @Query private var cards: [CreditCard]
    @Query private var profiles: [UserProfile]
    @State private var month = Date().startOfMonth
    @State private var newKind: FinanceKind?
    @State private var settling: RecurringEntry?
    @State private var editingBalance = false
    @State private var editing: FinanceTransaction?

    private var plan: FinanceCalculator.WeeklyPlan? {
        profiles.first.map {
            FinanceCalculator.weeklyPlan(profile: $0, transactions: transactions, recurring: recurring, debts: debts, cards: cards)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    balanceCard
                    weeklyCard
                    quickActions
                    upcomingBills
                    summaryCard
                    categoryCard
                    navigationRows
                    SectionHeader(title: "Últimas movimentações")
                    if transactions.isEmpty {
                        EmptyStateView(icon: "list.bullet.rectangle", title: "Sem movimentações",
                                       message: "Registre um gasto pelo + ou diga \"gastei 35 reais no almoço\".")
                    }
                    ForEach(transactions.prefix(8)) { t in
                        TransactionRow(transaction: t).onTapGesture { editing = t }
                    }
                    if transactions.count > 8 {
                        NavigationLink("Ver todas as movimentações") { TransactionsListView() }
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding()
                .padding(.bottom, 16)
            }
            .screenBackground()
            .navigationTitle("Financeiro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nova despesa", systemImage: "arrow.up.right") { newKind = .despesa }
                        Button("Nova receita", systemImage: "arrow.down.left") { newKind = .receita }
                    } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .accessibilityLabel("Adicionar movimentação")
                }
            }
            .confirmationDialog(settling.map { "Registrar \($0.title) (\(Fmt.currency($0.amount))) como \($0.kind == .receita ? "recebido" : "pago") hoje?" } ?? "",
                                isPresented: Binding(get: { settling != nil }, set: { if !$0 { settling = nil } }), titleVisibility: .visible) {
                Button("Registrar pagamento") {
                    if let s = settling { FinanceService.settle(s, context: context) }
                    settling = nil
                }
            }
            .sheet(item: $newKind) { TransactionEditor(kind: $0) }
            .sheet(item: $editing) { TransactionEditor(transaction: $0) }
            .sheet(isPresented: $editingBalance) { BalanceSettingsView() }
        }
    }

    private var balanceCard: some View {
        Button { editingBalance = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Saldo disponível").font(.subheadline.weight(.semibold)).opacity(0.9)
                    Spacer()
                    Image(systemName: "pencil.circle.fill").opacity(0.8)
                }
                Text(Fmt.currency(plan?.balance ?? 0)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                let month = DateInterval(start: Date().startOfMonth, end: Date())
                HStack(spacing: 18) {
                    Label(Fmt.currency(FinanceCalculator.income(transactions, in: month)), systemImage: "arrow.down.left")
                    Label(Fmt.currency(FinanceCalculator.spending(transactions, in: month)), systemImage: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold)).opacity(0.95)
            }
            .gradientCard(.finance)
        }
        .buttonStyle(.plain)
    }

    private var weeklyCard: some View {
        NavigationLink { BudgetPlannerView() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Posso gastar nesta semana").font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                if let p = plan {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.currency(max(0, p.remainingThisWeek))).font(.title.bold()).monospacedDigit()
                            .foregroundStyle(p.isOverBudget ? .red : .primary)
                        Text("de \(Fmt.currency(p.weeklyAllowance))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ProgressBar(value: p.weeklyAllowance > 0 ? p.spentThisWeek / p.weeklyAllowance : 0,
                                tint: p.isOverBudget ? .red : Theme.Module.finance.tint)
                    if p.isOverBudget {
                        Label("Você passou \(Fmt.currency(-p.remainingThisWeek)) do planejado", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    }
                }
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            actionButton("Despesa", "arrow.up.right", .red) { newKind = .despesa }
            actionButton("Receita", "arrow.down.left", .green) { newKind = .receita }
            NavigationLink { RecurringListView() } label: { actionLabel("Contas", "calendar.badge.clock", .orange) }
            NavigationLink { CardsView() } label: { actionLabel("Cartões", "creditcard.fill", .indigo) }
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, icon, color) }
    }

    private func actionLabel(_ title: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            IconBadge(systemName: icon, tint: color, size: 44)
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Intervalo do mês selecionado (até agora, se for o mês atual).
    private func monthInterval(_ m: Date) -> DateInterval {
        DateInterval(start: m, end: max(m, min(m.endOfMonth, Date())))
    }

    /// Contas que vencem nos próximos 10 dias, com registro de pagamento em um toque.
    @ViewBuilder
    private var upcomingBills: some View {
        let bills = recurring.filter { $0.isActive && $0.kind == .despesa && $0.dueDate <= Date().adding(days: 10) }
        if !bills.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Contas a vencer").font(.headline)
                    Spacer()
                    Text(Fmt.currency(bills.reduce(0) { $0 + $1.amount })).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                ForEach(bills.prefix(4)) { b in
                    HStack(spacing: 12) {
                        IconBadge(systemName: b.category.icon, tint: b.category.color, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.title).font(.subheadline.weight(.semibold))
                            Text(b.dueDate < Date().startOfDay ? "Atrasada (\(Fmt.relativeDay(b.dueDate)))" : "Vence \(Fmt.relativeDay(b.dueDate))")
                                .font(.caption).foregroundStyle(b.dueDate < Date().startOfDay ? .red : .secondary)
                        }
                        Spacer()
                        Text(Fmt.currency(b.amount)).font(.subheadline).monospacedDigit()
                        Button("Pagar") { settling = b }
                            .buttonStyle(.bordered).font(.caption.weight(.semibold))
                    }
                }
            }
            .card()
        }
    }

    private var summaryCard: some View {
        let interval = monthInterval(month)
        let previous = monthInterval(month.adding(months: -1))
        let income = FinanceCalculator.income(transactions, in: interval)
        let spent = FinanceCalculator.spending(transactions, in: interval)
        let prevSpent = FinanceCalculator.spending(transactions, in: previous)
        let isCurrent = month == Date().startOfMonth
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { withAnimation(.snappy) { month = month.adding(months: -1) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Mês anterior")
                Spacer()
                Text(Fmt.monthYear(month)).font(.headline)
                Spacer()
                Button { withAnimation(.snappy) { month = month.adding(months: 1) } } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrent)
                    .accessibilityLabel("Próximo mês")
            }
            HStack(spacing: 0) {
                monthValue("Entradas", income, .green)
                monthValue("Saídas", spent, .red)
                monthValue("Resultado", income - spent, income - spent >= 0 ? .green : .red)
            }
            Chart {
                BarMark(x: .value("Valor", income), y: .value("Tipo", "Entradas")).foregroundStyle(.green.gradient).cornerRadius(5)
                BarMark(x: .value("Valor", spent), y: .value("Tipo", "Saídas")).foregroundStyle(.red.gradient).cornerRadius(5)
            }
            .chartXAxis(.hidden)
            .frame(height: 70)
            if prevSpent > 0 {
                let diff = (spent - prevSpent) / prevSpent
                Label("\(diff >= 0 ? "+" : "−")\(Fmt.percent(abs(diff))) de gastos em relação ao mês anterior",
                      systemImage: diff > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(diff > 0 ? .orange : .green)
            }
        }
        .card()
    }

    private func monthValue(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(Fmt.currency(value)).font(.subheadline.weight(.bold)).foregroundStyle(color)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryCard: some View {
        let data = FinanceCalculator.byCategory(transactions, in: monthInterval(month))
        let total = data.reduce(0) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Para onde foi o dinheiro").font(.headline)
            if data.isEmpty {
                Text("Sem despesas neste mês.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(data, id: \.category) { item in
                        SectorMark(angle: .value("Total", item.total), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(item.category.color)
                            .cornerRadius(4)
                    }
                    .frame(width: 130, height: 130)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("Total").font(.caption2).foregroundStyle(.secondary)
                            Text(Fmt.currency(total)).font(.caption.weight(.bold)).minimumScaleFactor(0.6)
                        }
                        .frame(width: 70)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(data.prefix(6), id: \.category) { item in
                            HStack(spacing: 6) {
                                Circle().fill(item.category.color).frame(width: 8, height: 8)
                                Text(item.category.label).font(.caption).lineLimit(1)
                                Spacer()
                                Text(Fmt.percent(total > 0 ? item.total / total : 0)).font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                // Ranking completo: valor e participação de cada categoria.
                VStack(spacing: 9) {
                    ForEach(data, id: \.category) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(item.category.label, systemImage: item.category.icon)
                                    .font(.caption.weight(.semibold)).foregroundStyle(item.category.color)
                                Spacer()
                                Text(Fmt.currency(item.total)).font(.caption.weight(.semibold)).monospacedDigit()
                            }
                            ProgressBar(value: total > 0 ? item.total / total : 0, tint: item.category.color, height: 6)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .card()
    }

    private var navigationRows: some View {
        VStack(spacing: 0) {
            navRow("Planejamento semanal", "chart.line.uptrend.xyaxis", .green) { BudgetPlannerView() }
            Divider().padding(.leading, 56)
            navRow("Contas e receitas previstas", "calendar.badge.clock", .orange) { RecurringListView() }
            Divider().padding(.leading, 56)
            navRow("Cartões e faturas", "creditcard.fill", .indigo) { CardsView() }
            Divider().padding(.leading, 56)
            navRow("Dívidas", "creditcard.trianglebadge.exclamationmark", .red) { DebtsView() }
            Divider().padding(.leading, 56)
            navRow("Metas financeiras", "target", .teal) { SavingsGoalsView() }
            Divider().padding(.leading, 56)
            navRow("Gráficos financeiros", "chart.bar.xaxis", .blue) { FinanceChartsView() }
            Divider().padding(.leading, 56)
            navRow("Todas as movimentações", "list.bullet", .gray) { TransactionsListView() }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func navRow<D: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                IconBadge(systemName: icon, tint: color, size: 32)
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

struct TransactionRow: View {
    let transaction: FinanceTransaction
    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: transaction.category.icon, tint: transaction.category.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(Fmt.relativeDay(transaction.date).capitalizedFirst)
                    if let c = transaction.card { Text("· \(c.name)") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.signedCurrency(transaction.signedAmount))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(transaction.kind == .receita ? .green : .primary)
        }
        .card(padding: 12)
    }
}

struct TransactionsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var transactions: [FinanceTransaction]
    @State private var search = ""
    @State private var kind: FinanceKind?
    @State private var editing: FinanceTransaction?
    @State private var exportURL: URL?

    private var filtered: [FinanceTransaction] {
        transactions.filter { t in
            (kind == nil || t.kind == kind) &&
            (search.isEmpty || t.title.folded.contains(search.folded) || t.category.label.folded.contains(search.folded))
        }
    }

    var body: some View {
        List {
            Picker("Tipo", selection: $kind) {
                Text("Todas").tag(FinanceKind?.none)
                Text("Receitas").tag(Optional(FinanceKind.receita))
                Text("Despesas").tag(Optional(FinanceKind.despesa))
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            let groups = Dictionary(grouping: filtered) { $0.date.startOfDay }.sorted { $0.key > $1.key }
            ForEach(groups, id: \.key) { day, items in
                Section(Fmt.fullDate(day)) {
                    ForEach(items) { t in
                        HStack {
                            IconBadge(systemName: t.category.icon, tint: t.category.color, size: 30)
                            VStack(alignment: .leading) {
                                Text(t.title).font(.subheadline)
                                Text(t.category.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.signedCurrency(t.signedAmount)).monospacedDigit()
                                .foregroundStyle(t.kind == .receita ? .green : .primary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = t }
                        .swipeActions {
                            Button("Excluir", role: .destructive) { context.delete(t); context.saveQuietly() }
                            if let group = t.installmentGroup {
                                Button("Todas as parcelas") {
                                    transactions.filter { $0.installmentGroup == group }.forEach { context.delete($0) }
                                    context.saveQuietly()
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar")
        .navigationTitle("Movimentações")
        .toolbar {
            Button {
                exportURL = try? BackupService.writeTemporary(CSVExporter.transactions(filtered), name: "LifeOS-financas.csv")
            } label: { Image(systemName: "square.and.arrow.up") }
        }
        .sheet(item: $editing) { TransactionEditor(transaction: $0) }
        .sheet(item: Binding(get: { exportURL.map(ShareItem.init) }, set: { if $0 == nil { exportURL = nil } })) { item in
            ShareSheet(items: [item.url])
        }
    }
}

struct TransactionEditor: View {
    var transaction: FinanceTransaction?
    var kind: FinanceKind = .despesa

    init(transaction: FinanceTransaction) { self.transaction = transaction; self.kind = transaction.kind }
    init(kind: FinanceKind) { self.transaction = nil; self.kind = kind }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @State private var currentKind: FinanceKind = .despesa
    @State private var title = ""
    @State private var amount = ""
    @State private var category: FinanceCategory = .alimentacao
    @State private var date = Date()
    @State private var card: CreditCard?
    @State private var installments = 1
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if transaction == nil {
                    Picker("Tipo", selection: $currentKind) {
                        ForEach(FinanceKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    TextField("Valor (R$)", text: $amount).keyboardType(.decimalPad).font(.title2.bold())
                    TextField("Descrição", text: $title)
                    Picker("Categoria", selection: $category) {
                        ForEach(FinanceCategory.selectable(for: currentKind)) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                }
                if currentKind == .despesa && !cards.isEmpty && (transaction == nil || transaction?.installmentGroup == nil) {
                    Section("Pagamento") {
                        Picker("Cartão de crédito", selection: $card) {
                            Text("Débito / dinheiro / Pix").tag(CreditCard?.none)
                            ForEach(cards) { Text($0.name).tag(Optional($0)) }
                        }
                        if card != nil && transaction == nil {
                            Stepper("Parcelas: \(installments)x", value: $installments, in: 1...48)
                            if installments > 1, let v = Fmt.parseDecimal(amount) {
                                Text("\(installments)x de \(Fmt.currency(v / Double(installments)))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Observação") { TextField("Opcional", text: $note, axis: .vertical) }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle(transaction == nil ? "Nova movimentação" : "Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save) }
            }
            .onAppear(perform: load)
            .onChange(of: currentKind) { _, k in
                if category.kind != k { category = FinanceCategory.selectable(for: k).first ?? .outros }
            }
        }
    }

    private func load() {
        if let t = transaction {
            currentKind = t.kind; title = t.title; amount = Fmt.number(t.amount, digits: 2)
            category = t.category; date = t.date; card = t.card; note = t.note
        } else {
            currentKind = kind
            category = kind == .receita ? .salario : .alimentacao
        }
    }

    private func save() {
        guard let value = Fmt.parseDecimal(amount), value > 0, value < 10_000_000 else {
            error = "Informe um valor válido."
            return
        }
        let desc = title.trimmed.isEmpty ? category.label : String(title.trimmed.prefix(120))
        if let t = transaction {
            t.title = desc; t.amount = value; t.kind = currentKind; t.category = category
            t.date = date; t.note = note
            if t.installmentGroup == nil { t.card = currentKind == .despesa ? card : nil }
        } else {
            FinanceService.addTransaction(title: desc, amount: value, kind: currentKind, category: category, date: date,
                                          card: currentKind == .despesa ? card : nil, installments: installments,
                                          note: note, context: context)
        }
        context.saveQuietly()
        if currentKind == .despesa { FinanceService.checkBudgetAlert(context: context) }
        dismiss()
    }
}

struct BalanceSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var balance = ""
    @State private var date = Date()
    @State private var savings = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Informe o saldo real da sua conta em uma data. A partir dela, o LifeOS soma receitas e subtrai despesas. Nenhuma conexão com banco é feita.")) {
                    TextField("Saldo (R$)", text: $balance).keyboardType(.numbersAndPunctuation)
                    DatePicker("Na data", selection: $date)
                }
                Section(footer: Text("Valor reservado todo mês; é descontado do quanto você pode gastar por semana.")) {
                    TextField("Meta de economia mensal (R$)", text: $savings).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Saldo e economia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let p = context.profile()
                        if let b = Fmt.parseDecimal(balance) { p.initialBalance = b; p.balanceDate = date }
                        p.monthlySavingsTarget = max(0, Fmt.parseDecimal(savings) ?? 0)
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let p = context.profile()
                balance = Fmt.number(p.initialBalance, digits: 2)
                date = p.balanceDate
                savings = p.monthlySavingsTarget > 0 ? Fmt.number(p.monthlySavingsTarget, digits: 2) : ""
            }
        }
    }
}

/// Folha de compartilhamento nativa (salvar em Arquivos, AirDrop para o computador...).
struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
