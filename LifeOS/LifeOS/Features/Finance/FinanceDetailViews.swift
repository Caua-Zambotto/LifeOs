import SwiftUI
import SwiftData
import Charts

// MARK: - Planejamento semanal

struct BudgetPlannerView: View {
    @Query private var transactions: [FinanceTransaction]
    @Query private var recurring: [RecurringEntry]
    @Query private var debts: [Debt]
    @Query private var cards: [CreditCard]
    @Query private var profiles: [UserProfile]
    @State private var editingBalance = false

    var body: some View {
        ScrollView {
            if let profile = profiles.first {
                let p = FinanceCalculator.weeklyPlan(profile: profile, transactions: transactions, recurring: recurring, debts: debts, cards: cards)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Você pode gastar por semana").font(.subheadline.weight(.semibold)).opacity(0.9)
                        Text(Fmt.currency(p.weeklyAllowance)).font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Restam \(Fmt.currency(p.remainingThisWeek)) nesta semana · \(p.weeksRemaining) semana(s) até o fim do mês")
                            .font(.subheadline).opacity(0.9)
                    }
                    .gradientCard(p.isOverBudget ? .body : .finance)

                    VStack(spacing: 10) {
                        row("Saldo atual", p.balance, .primary)
                        row("+ Receitas previstas no mês", p.expectedIncome, .green)
                        row("− Contas pendentes no mês", -p.pendingBills, .red)
                        row("− Parcelas de dívidas", -p.debtPayments, .red)
                        row("− Faturas de cartão em aberto", -p.cardInvoices, .red)
                        row("− Meta de economia", -p.savingsTarget, .red)
                        Divider()
                        row("= Disponível até o fim do mês", p.available, p.available >= 0 ? .green : .red, bold: true)
                        row("Gasto nesta semana", p.spentThisWeek, .primary)
                    }
                    .card()

                    Text("Como funciona: o LifeOS parte do saldo informado, soma receitas previstas e desconta tudo o que ainda precisa ser pago no mês. O resultado é dividido pelas semanas restantes. Você recebe um aviso local quando passa do valor da semana.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Ajustar saldo e meta de economia") { editingBalance = true }.buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .screenBackground()
        .navigationTitle("Planejamento")
        .sheet(isPresented: $editingBalance) { BalanceSettingsView() }
    }

    private func row(_ label: String, _ value: Double, _ color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(bold ? .subheadline.weight(.bold) : .subheadline)
            Spacer()
            Text(Fmt.currency(value)).font(.subheadline.weight(bold ? .bold : .semibold)).foregroundStyle(color).monospacedDigit()
        }
    }
}

// MARK: - Contas recorrentes

struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringEntry.dueDate) private var entries: [RecurringEntry]
    @State private var editing: RecurringEntry?
    @State private var creating = false

    var body: some View {
        List {
            let active = entries.filter(\.isActive)
            Section("Contas a pagar") {
                let bills = active.filter { $0.kind == .despesa }
                if bills.isEmpty { Text("Nenhuma conta cadastrada.").foregroundStyle(.secondary) }
                ForEach(bills) { e in entryRow(e) }
            }
            Section("Receitas previstas") {
                let incomes = active.filter { $0.kind == .receita }
                if incomes.isEmpty { Text("Cadastre seu salário para melhorar o planejamento.").foregroundStyle(.secondary) }
                ForEach(incomes) { e in entryRow(e) }
            }
            let monthly = active.filter { $0.kind == .despesa && $0.recurrence == .mensal }.reduce(0) { $0 + $1.amount }
            Section {
                HStack {
                    Text("Despesas fixas mensais")
                    Spacer()
                    Text(Fmt.currency(monthly)).bold()
                }
            }
            let inactive = entries.filter { !$0.isActive }
            if !inactive.isEmpty {
                Section("Quitadas") {
                    ForEach(inactive) { e in
                        Text(e.title).foregroundStyle(.secondary)
                            .swipeActions { Button("Excluir", role: .destructive) { context.delete(e); context.saveQuietly() } }
                    }
                }
            }
        }
        .navigationTitle("Contas")
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { RecurringEditor(entry: $0) }
        .sheet(isPresented: $creating) { RecurringEditor(entry: nil) }
    }

    private func entryRow(_ e: RecurringEntry) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: e.category.icon, tint: e.category.color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.subheadline.weight(.semibold))
                Text("\(e.kind == .receita ? "Previsto" : "Vence") \(Fmt.relativeDay(e.dueDate)) · \(e.recurrence.label)")
                    .font(.caption).foregroundStyle(e.dueDate < Date().startOfDay ? .red : .secondary)
            }
            Spacer()
            Text(Fmt.currency(e.amount)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = e }
        .swipeActions(edge: .leading) {
            Button(e.kind == .receita ? "Recebido" : "Pago") { FinanceService.settle(e, context: context) }.tint(.green)
        }
        .swipeActions {
            Button("Excluir", role: .destructive) {
                NotificationScheduler.cancel(entry: e)
                context.delete(e)
                context.saveQuietly()
            }
        }
    }
}

struct RecurringEditor: View {
    let entry: RecurringEntry?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amount = ""
    @State private var kind: FinanceKind = .despesa
    @State private var category: FinanceCategory = .moradia
    @State private var due = Date()
    @State private var recurrence: Recurrence = .mensal
    @State private var notify = true

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tipo", selection: $kind) {
                    Text("Conta a pagar").tag(FinanceKind.despesa)
                    Text("Receita prevista").tag(FinanceKind.receita)
                }
                .pickerStyle(.segmented)
                TextField("Nome (ex.: Internet)", text: $title)
                TextField("Valor (R$)", text: $amount).keyboardType(.decimalPad)
                Picker("Categoria", selection: $category) {
                    ForEach(FinanceCategory.selectable(for: kind)) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                DatePicker(kind == .despesa ? "Próximo vencimento" : "Data prevista", selection: $due, displayedComponents: .date)
                Picker("Repetição", selection: $recurrence) {
                    ForEach(Recurrence.allCases.filter { $0 != .diaria }) { Text($0.label).tag($0) }
                }
                if kind == .despesa { Toggle("Lembrar antes do vencimento", isOn: $notify) }
                if let entry {
                    Section {
                        Button(kind == .despesa ? "Marcar como paga agora" : "Marcar como recebida agora") {
                            FinanceService.settle(entry, context: context)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Nova conta" : "Editar conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        guard let v = Fmt.parseDecimal(amount), v > 0 else { return }
                        let e = entry ?? RecurringEntry(title: title, amount: v, kind: kind, category: category, dueDate: due, recurrence: recurrence)
                        e.title = title.trimmed.isEmpty ? category.label : title.trimmed
                        e.amount = v; e.kind = kind; e.category = category; e.dueDate = due; e.recurrence = recurrence
                        e.notify = notify; e.isActive = true
                        if entry == nil { context.insert(e) }
                        context.saveQuietly()
                        NotificationScheduler.schedule(e)
                        dismiss()
                    }
                    .disabled(Fmt.parseDecimal(amount) == nil)
                }
            }
            .onAppear {
                if let e = entry {
                    title = e.title; amount = Fmt.number(e.amount, digits: 2); kind = e.kind; category = e.category
                    due = e.dueDate; recurrence = e.recurrence; notify = e.notify
                }
            }
            .onChange(of: kind) { _, k in if category.kind != k { category = FinanceCategory.selectable(for: k).first ?? .outros } }
        }
    }
}

// MARK: - Cartões

struct CardsView: View {
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if cards.isEmpty {
                    EmptyStateView(icon: "creditcard", title: "Nenhum cartão",
                                   message: "Cadastre seus cartões para controlar faturas e parcelamentos. Nenhum dado bancário real é necessário.",
                                   actionTitle: "Adicionar cartão") { creating = true }
                }
                ForEach(cards) { c in
                    NavigationLink { CardDetailView(card: c) } label: { CardVisual(card: c) }.buttonStyle(.plain)
                }
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Cartões")
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $creating) { CardEditor(card: nil) }
    }
}

struct CardVisual: View {
    let card: CreditCard
    var body: some View {
        let used = FinanceCalculator.limitUsed(card: card)
        let current = FinanceCalculator.invoiceTotal(card: card, month: FinanceCalculator.invoiceMonth(for: Date(), closingDay: card.closingDay))
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(card.name).font(.title3.bold())
                Spacer()
                Image(systemName: "creditcard.fill").font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Fatura atual").font(.caption).opacity(0.85)
                Text(Fmt.currency(current)).font(.title.bold()).monospacedDigit()
            }
            if card.limit > 0 {
                ProgressBar(value: used / card.limit, tint: .white)
                Text("Limite usado \(Fmt.currency(used)) de \(Fmt.currency(card.limit))").font(.caption).opacity(0.9)
            }
            Text("Fecha dia \(card.closingDay) · vence dia \(card.dueDay)").font(.caption).opacity(0.85)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: card.colorHex), Color(hex: card.colorHex).opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(.white)
    }
}

struct CardDetailView: View {
    @Bindable var card: CreditCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var month = FinanceCalculator.invoiceMonth(for: Date(), closingDay: 1)
    @State private var editing = false
    @State private var confirmPay = false
    @State private var confirmDelete = false

    var body: some View {
        let items = card.transactions
            .filter { !$0.isInvoicePayment && FinanceCalculator.invoiceMonth(for: $0.date, closingDay: card.closingDay) == month }
            .sorted { $0.date > $1.date }
        let outstanding = FinanceCalculator.outstanding(card: card)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CardVisual(card: card)
                HStack {
                    Button { month = month.adding(months: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text("Fatura de \(Fmt.monthYear(month))").font(.headline)
                    Spacer()
                    Button { month = month.adding(months: 1) } label: { Image(systemName: "chevron.right") }
                }
                HStack {
                    StatTile(title: "Total da fatura", value: Fmt.currency(items.reduce(0) { $0 + $1.amount }), icon: "doc.text", tint: .indigo)
                    StatTile(title: "Em aberto", value: Fmt.currency(outstanding), icon: "hourglass", tint: .orange)
                }
                if outstanding > 0 {
                    Button("Registrar pagamento de \(Fmt.currency(outstanding))") { confirmPay = true }
                        .buttonStyle(PrimaryButtonStyle(module: .finance))
                }
                if items.isEmpty { Text("Nenhuma compra nesta fatura.").foregroundStyle(.secondary) }
                ForEach(items) { TransactionRow(transaction: $0) }
                let byMonth = (0..<6).reversed().map { offset -> DayValue in
                    let m = FinanceCalculator.invoiceMonth(for: Date(), closingDay: card.closingDay).adding(months: -offset)
                    return DayValue(date: m, value: FinanceCalculator.invoiceTotal(card: card, month: m))
                }
                VStack(alignment: .leading) {
                    Text("Últimas faturas").font(.headline)
                    Chart(byMonth) { BarMark(x: .value("Mês", Fmt.monthShort($0.date)), y: .value("Total", $0.value)).foregroundStyle(Color(hex: card.colorHex)) }
                        .frame(height: 140)
                }
                .card()
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle(card.name)
        .toolbar {
            Menu {
                Button("Editar", systemImage: "pencil") { editing = true }
                Button("Excluir cartão", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .onAppear { month = FinanceCalculator.invoiceMonth(for: Date(), closingDay: card.closingDay) }
        .sheet(isPresented: $editing) { CardEditor(card: card) }
        .confirmationDialog("Registrar o pagamento da fatura? O valor sairá do seu saldo.", isPresented: $confirmPay, titleVisibility: .visible) {
            Button("Registrar pagamento") { FinanceService.payInvoice(card: card, amount: outstanding, context: context) }
        }
        .confirmationDialog("Excluir o cartão? As compras são mantidas como despesas sem cartão.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) { context.delete(card); context.saveQuietly(); dismiss() }
        }
    }
}

struct CardEditor: View {
    let card: CreditCard?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var limit = ""
    @State private var closing = 1
    @State private var due = 10
    @State private var color = "1C1C1E"
    private let colors = ["1C1C1E", "820AD1", "EC7000", "CC092F", "0F766E", "1D4ED8", "B45309", "475569"]

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Use apenas um apelido. Nunca informe número, CVV ou senha do cartão.")) {
                    TextField("Apelido (ex.: Nubank)", text: $name)
                    TextField("Limite (R$)", text: $limit).keyboardType(.decimalPad)
                    Stepper("Fechamento: dia \(closing)", value: $closing, in: 1...31)
                    Stepper("Vencimento: dia \(due)", value: $due, in: 1...31)
                }
                Section("Cor") {
                    HStack {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.primary, lineWidth: color == c ? 2 : 0))
                                .onTapGesture { color = c }
                        }
                    }
                }
            }
            .navigationTitle(card == nil ? "Novo cartão" : "Editar cartão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        let c = card ?? CreditCard(name: name, limit: 0, closingDay: closing, dueDay: due)
                        c.name = String(name.trimmed.prefix(30)); c.limit = Fmt.parseDecimal(limit) ?? 0
                        c.closingDay = closing; c.dueDay = due; c.colorHex = color
                        if card == nil { context.insert(c) }
                        context.saveQuietly()
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
            .onAppear {
                if let c = card { name = c.name; limit = Fmt.number(c.limit, digits: 2); closing = c.closingDay; due = c.dueDay; color = c.colorHex }
            }
        }
    }
}

// MARK: - Dívidas

struct DebtsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Debt.createdAt) private var debts: [Debt]
    @State private var creating = false
    @State private var paying: Debt?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let total = debts.reduce(0) { $0 + $1.remainingAmount }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total em dívidas").font(.subheadline.weight(.semibold)).opacity(0.9)
                    Text(Fmt.currency(total)).font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Parcelas mensais: \(Fmt.currency(debts.filter { $0.remainingAmount > 0 }.reduce(0) { $0 + $1.monthlyPayment }))")
                        .font(.subheadline).opacity(0.9)
                }
                .gradientCard(.body)

                let points = debts.flatMap { d in d.payments.map { DayValue(date: $0.date, value: $0.remainingAfter, series: d.creditor) } }
                    .sorted { $0.date < $1.date }
                if points.count >= 2 {
                    VStack(alignment: .leading) {
                        Text("Evolução das dívidas").font(.headline)
                        Chart(points) { p in
                            LineMark(x: .value("Data", p.date), y: .value("Saldo devedor", p.value))
                                .foregroundStyle(by: .value("Credor", p.series))
                            PointMark(x: .value("Data", p.date), y: .value("Saldo devedor", p.value))
                                .foregroundStyle(by: .value("Credor", p.series))
                        }
                        .frame(height: 170)
                    }
                    .card()
                }
                if debts.isEmpty {
                    EmptyStateView(icon: "checkmark.seal", title: "Sem dívidas cadastradas", message: "Cadastre empréstimos, acordos e financiamentos para acompanhar a quitação.",
                                   actionTitle: "Adicionar dívida") { creating = true }
                }
                ForEach(debts) { d in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(d.creditor).font(.headline)
                            Spacer()
                            Text(Fmt.currency(d.remainingAmount)).font(.headline).monospacedDigit()
                        }
                        ProgressBar(value: d.progress, tint: .green)
                        HStack {
                            Text("\(Fmt.percent(d.progress)) quitado · parcela \(Fmt.currency(d.monthlyPayment)) · dia \(d.dueDay)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if d.remainingAmount > 0 {
                                Button("Pagar") { paying = d }.buttonStyle(.bordered).font(.caption)
                            }
                        }
                        if d.monthlyPayment > 0 && d.remainingAmount > 0 {
                            let months = Int(ceil(d.remainingAmount / d.monthlyPayment))
                            Text("Previsão de quitação: \(Fmt.monthYear(Date().adding(months: months))) (sem considerar juros)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .card()
                    .contextMenu {
                        Button("Excluir", systemImage: "trash", role: .destructive) { context.delete(d); context.saveQuietly() }
                    }
                }
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Dívidas")
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $creating) { DebtEditor() }
        .sheet(item: $paying) { DebtPaymentSheet(debt: $0) }
    }
}

struct DebtEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var creditor = ""
    @State private var original = ""
    @State private var remaining = ""
    @State private var monthly = ""
    @State private var interest = ""
    @State private var dueDay = 10

    var body: some View {
        NavigationStack {
            Form {
                TextField("Credor (ex.: Empréstimo banco)", text: $creditor)
                TextField("Valor original (R$)", text: $original).keyboardType(.decimalPad)
                TextField("Saldo devedor atual (R$)", text: $remaining).keyboardType(.decimalPad)
                TextField("Parcela mensal (R$)", text: $monthly).keyboardType(.decimalPad)
                TextField("Juros ao mês (%) — opcional", text: $interest).keyboardType(.decimalPad)
                Stepper("Vencimento: dia \(dueDay)", value: $dueDay, in: 1...31)
            }
            .navigationTitle("Nova dívida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        guard let o = Fmt.parseDecimal(original), o > 0 else { return }
                        let r = Fmt.parseDecimal(remaining) ?? o
                        let d = Debt(creditor: creditor.trimmed, originalAmount: o, remainingAmount: min(r, o),
                                     monthlyPayment: Fmt.parseDecimal(monthly) ?? 0, dueDay: dueDay)
                        d.monthlyInterestRate = Fmt.parseDecimal(interest) ?? 0
                        context.insert(d)
                        context.saveQuietly()
                        dismiss()
                    }
                    .disabled(creditor.trimmed.isEmpty || Fmt.parseDecimal(original) == nil)
                }
            }
        }
    }
}

struct DebtPaymentSheet: View {
    let debt: Debt
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var register = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Valor pago (R$)", text: $amount).keyboardType(.decimalPad)
                Toggle("Lançar como despesa no saldo", isOn: $register)
            }
            .navigationTitle("Pagamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        guard let v = Fmt.parseDecimal(amount), v > 0 else { return }
                        FinanceService.payDebt(debt, amount: v, registerExpense: register, context: context)
                        dismiss()
                    }
                }
            }
            .onAppear { amount = Fmt.number(min(debt.monthlyPayment, debt.remainingAmount), digits: 2) }
        }
    }
}

// MARK: - Metas financeiras

struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @State private var creating = false
    @State private var depositing: SavingsGoal?
    @State private var title = ""
    @State private var target = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if goals.isEmpty {
                    EmptyStateView(icon: "target", title: "Nenhuma meta", message: "Ex.: reserva de emergência, viagem, notebook.",
                                   actionTitle: "Criar meta") { creating = true }
                }
                ForEach(goals) { g in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(g.title).font(.headline)
                            Spacer()
                            Text(Fmt.percent(g.progress)).font(.headline).foregroundStyle(.teal)
                        }
                        ProgressBar(value: g.progress, tint: .teal)
                        HStack {
                            Text("\(Fmt.currency(g.saved)) de \(Fmt.currency(g.target))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Guardar") { depositing = g }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                    .card()
                    .contextMenu { Button("Excluir", systemImage: "trash", role: .destructive) { context.delete(g); context.saveQuietly() } }
                }
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Metas financeiras")
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .alert("Nova meta", isPresented: $creating) {
            TextField("Nome", text: $title)
            TextField("Valor alvo", text: $target).keyboardType(.decimalPad)
            Button("Criar") {
                if let t = Fmt.parseDecimal(target), t > 0, !title.trimmed.isEmpty {
                    context.insert(SavingsGoal(title: title.trimmed, target: t))
                    context.saveQuietly()
                }
                title = ""; target = ""
            }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(item: $depositing) { SavingsDepositSheet(goal: $0) }
    }
}

struct SavingsDepositSheet: View {
    let goal: SavingsGoal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var withdraw = false
    @State private var affectBalance = true

    var body: some View {
        NavigationStack {
            Form {
                Picker("Operação", selection: $withdraw) {
                    Text("Guardar").tag(false)
                    Text("Retirar").tag(true)
                }
                .pickerStyle(.segmented)
                TextField("Valor (R$)", text: $amount).keyboardType(.decimalPad)
                Toggle("Movimentar o saldo disponível", isOn: $affectBalance)
            }
            .navigationTitle(goal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        guard let v = Fmt.parseDecimal(amount), v > 0 else { return }
                        goal.saved = max(0, goal.saved + (withdraw ? -v : v))
                        if affectBalance {
                            let tx = FinanceTransaction(title: "Meta: \(goal.title)", amount: v, kind: withdraw ? .receita : .despesa,
                                                        category: withdraw ? .outrasReceitas : .reserva)
                            context.insert(tx)
                        }
                        context.saveQuietly()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Gráficos

struct FinanceChartsView: View {
    @Query(sort: \FinanceTransaction.date) private var transactions: [FinanceTransaction]
    @Query private var cards: [CreditCard]
    @Query private var recurring: [RecurringEntry]
    @Query private var profiles: [UserProfile]
    @State private var period: ReportPeriod = .trimestre

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Período", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                FinanceChartsSection(transactions: transactions, cards: cards, recurring: recurring,
                                     profile: profiles.first, period: period)
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Gráficos")
    }
}

/// Bloco de gráficos financeiros reutilizado em Relatórios.
struct FinanceChartsSection: View {
    let transactions: [FinanceTransaction]
    let cards: [CreditCard]
    let recurring: [RecurringEntry]
    let profile: UserProfile?
    let period: ReportPeriod

    var body: some View {
        let interval = period.interval()
        let months = monthsIn(interval)
        VStack(alignment: .leading, spacing: 16) {
            chartCard("Entradas × saídas por mês") {
                Chart {
                    ForEach(months, id: \.self) { m in
                        let mi = DateInterval(start: m, end: m.endOfMonth)
                        BarMark(x: .value("Mês", Fmt.monthShort(m)), y: .value("Valor", FinanceCalculator.income(transactions, in: mi)))
                            .foregroundStyle(by: .value("Tipo", "Entradas"))
                            .position(by: .value("Tipo", "Entradas"))
                        BarMark(x: .value("Mês", Fmt.monthShort(m)), y: .value("Valor", FinanceCalculator.spending(transactions, in: mi)))
                            .foregroundStyle(by: .value("Tipo", "Saídas"))
                            .position(by: .value("Tipo", "Saídas"))
                    }
                }
                .chartForegroundStyleScale(["Entradas": Color.green, "Saídas": Color.red])
            }
            chartCard("Gastos por semana") {
                let weeks = weeksIn(interval)
                Chart(weeks.map { DayValue(date: $0, value: FinanceCalculator.spending(transactions, in: DateInterval(start: $0, end: $0.adding(days: 7)))) }) {
                    BarMark(x: .value("Semana", $0.date, unit: .weekOfYear), y: .value("Gasto", $0.value))
                        .foregroundStyle(Theme.Module.finance.gradient)
                }
            }
            chartCard("Gastos por categoria") {
                let data = FinanceCalculator.byCategory(transactions, in: interval)
                Chart(data, id: \.category) {
                    BarMark(x: .value("Total", $0.total), y: .value("Categoria", $0.category.label))
                        .foregroundStyle($0.category.color)
                }
                .frame(height: max(120, CGFloat(data.count) * 30))
            }
            if let profile {
                chartCard("Saldo ao longo dos meses") {
                    Chart(months.map { m in
                        DayValue(date: m, value: FinanceCalculator.balance(initial: profile.initialBalance, since: profile.balanceDate,
                                                                          transactions: transactions, now: min(Date(), m.endOfMonth)))
                    }) {
                        LineMark(x: .value("Mês", $0.date, unit: .month), y: .value("Saldo", $0.value))
                        AreaMark(x: .value("Mês", $0.date, unit: .month), y: .value("Saldo", $0.value))
                            .foregroundStyle(Theme.Module.finance.gradient.opacity(0.2))
                    }
                }
            }
            if !cards.isEmpty {
                chartCard("Gastos por cartão") {
                    Chart(cards) { c in
                        BarMark(x: .value("Cartão", c.name),
                                y: .value("Total", c.transactions.filter { !$0.isInvoicePayment && interval.contains($0.date) }.reduce(0) { $0 + $1.amount }))
                            .foregroundStyle(Color(hex: c.colorHex))
                    }
                }
            }
            let fixed = recurring.filter { $0.isActive && $0.kind == .despesa }
            if !fixed.isEmpty {
                chartCard("Despesas recorrentes") {
                    Chart(fixed) { e in
                        SectorMark(angle: .value("Valor", e.amount), innerRadius: .ratio(0.55), angularInset: 1.5)
                            .foregroundStyle(by: .value("Conta", e.title))
                    }
                    .frame(height: 200)
                }
            }
        }
    }

    private func chartCard<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content().frame(minHeight: 160)
        }
        .card()
    }

    private func monthsIn(_ i: DateInterval) -> [Date] {
        var result: [Date] = []
        var m = i.start.startOfMonth
        while m <= i.end { result.append(m); m = m.adding(months: 1) }
        return result
    }

    private func weeksIn(_ i: DateInterval) -> [Date] {
        var result: [Date] = []
        var w = i.start.startOfWeek
        while w <= i.end { result.append(w); w = w.adding(days: 7) }
        return result
    }
}
