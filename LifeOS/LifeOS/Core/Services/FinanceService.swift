import Foundation
import SwiftData

/// Regras financeiras puras (testáveis) + operações de gravação.
enum FinanceCalculator {

    /// Saldo em conta: saldo inicial + receitas − despesas que afetam o saldo, até `now`.
    /// Compras no cartão só reduzem o saldo quando a fatura é paga.
    static func balance(initial: Double, since start: Date, transactions: [FinanceTransaction], now: Date = Date()) -> Double {
        transactions
            .filter { $0.date >= start && $0.date <= now && $0.affectsBalance }
            .reduce(initial) { $0 + $1.signedAmount }
    }

    /// Despesas de consumo (exclui pagamento de fatura, para não contar duas vezes).
    static func spending(_ txs: [FinanceTransaction], in interval: DateInterval) -> Double {
        txs.filter { $0.kind == .despesa && !$0.isInvoicePayment && interval.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    static func income(_ txs: [FinanceTransaction], in interval: DateInterval) -> Double {
        txs.filter { $0.kind == .receita && interval.contains($0.date) }.reduce(0) { $0 + $1.amount }
    }

    static func byCategory(_ txs: [FinanceTransaction], in interval: DateInterval) -> [(category: FinanceCategory, total: Double)] {
        var dict: [FinanceCategory: Double] = [:]
        for t in txs where t.kind == .despesa && !t.isInvoicePayment && interval.contains(t.date) {
            dict[t.category, default: 0] += t.amount
        }
        return dict.map { (category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }

    // MARK: Cartões

    /// Mês de referência da fatura de uma compra (compras após o fechamento vão para a fatura seguinte).
    static func invoiceMonth(for date: Date, closingDay: Int, calendar: Calendar = Fmt.calendar) -> Date {
        let day = calendar.component(.day, from: date)
        let month = date.startOfMonth
        return day > closingDay ? month.adding(months: 1) : month
    }

    static func invoiceKey(_ month: Date) -> String {
        let c = Fmt.calendar.dateComponents([.year, .month], from: month)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func invoiceTotal(card: CreditCard, month: Date) -> Double {
        card.transactions
            .filter { !$0.isInvoicePayment && $0.kind == .despesa && invoiceMonth(for: $0.date, closingDay: card.closingDay) == month.startOfMonth }
            .reduce(0) { $0 + $1.amount }
    }

    /// Total comprado até hoje menos faturas pagas.
    static func outstanding(card: CreditCard, now: Date = Date()) -> Double {
        let purchases = card.transactions.filter { !$0.isInvoicePayment && $0.kind == .despesa && $0.date <= now }.reduce(0) { $0 + $1.amount }
        let paid = card.transactions.filter(\.isInvoicePayment).reduce(0) { $0 + $1.amount }
        return max(0, purchases - paid)
    }

    static func futureInstallments(card: CreditCard, now: Date = Date()) -> Double {
        card.transactions.filter { !$0.isInvoicePayment && $0.date > now }.reduce(0) { $0 + $1.amount }
    }

    static func limitUsed(card: CreditCard, now: Date = Date()) -> Double {
        outstanding(card: card, now: now) + futureInstallments(card: card, now: now)
    }

    // MARK: Planejamento semanal

    struct WeeklyPlan {
        var balance: Double
        var expectedIncome: Double
        var pendingBills: Double
        var debtPayments: Double
        var cardInvoices: Double
        var savingsTarget: Double
        var weeksRemaining: Int
        var spentThisWeek: Double
        /// Quanto pode gastar na semana inteira.
        var weeklyAllowance: Double
        /// Quanto ainda resta nesta semana.
        var remainingThisWeek: Double
        var isOverBudget: Bool { remainingThisWeek < 0 }
        var available: Double { balance + expectedIncome - pendingBills - debtPayments - cardInvoices - savingsTarget }
    }

    static func weeklyPlan(profile: UserProfile, transactions: [FinanceTransaction], recurring: [RecurringEntry],
                           debts: [Debt], cards: [CreditCard], now: Date = Date()) -> WeeklyPlan {
        let cal = Fmt.calendar
        let monthEnd = now.endOfMonth
        let bal = balance(initial: profile.initialBalance, since: profile.balanceDate, transactions: transactions, now: now)

        let active = recurring.filter(\.isActive)
        let income = active.filter { $0.kind == .receita && $0.dueDate > now && $0.dueDate <= monthEnd }.reduce(0) { $0 + $1.amount }
        let bills = active.filter { $0.kind == .despesa && $0.dueDate <= monthEnd }.reduce(0) { $0 + $1.amount }

        let monthStart = now.startOfMonth
        let debtDue = debts.filter { $0.remainingAmount > 0 }.reduce(0.0) { sum, d in
            let paidThisMonth = d.payments.contains { $0.date >= monthStart }
            return sum + (paidThisMonth ? 0 : min(d.monthlyPayment, d.remainingAmount))
        }
        // Faturas: o que já foi comprado e ainda não foi pago.
        let invoices = cards.reduce(0) { $0 + outstanding(card: $1, now: now) }
        let savingsDone = transactions.filter { $0.category == .reserva && $0.date >= monthStart && $0.date <= now }.reduce(0) { $0 + $1.amount }
        let savings = max(0, profile.monthlySavingsTarget - savingsDone)

        let daysLeft = (cal.dateComponents([.day], from: now.startOfDay, to: monthEnd.startOfDay).day ?? 0) + 1
        let weeks = max(1, Int(ceil(Double(daysLeft) / 7.0)))

        let weekInterval = DateInterval(start: now.startOfWeek, end: max(now.startOfWeek, now))
        // Gastos desta semana (dinheiro ou cartão) já reduziram `available` (saldo ou fatura em aberto).
        // Somamos de volta para calcular a cota desde o início da semana.
        let spentWeek = spending(transactions, in: weekInterval)

        let available = bal + income - bills - debtDue - invoices - savings
        let allowance = max(0, (available + spentWeek) / Double(weeks))
        return WeeklyPlan(balance: bal, expectedIncome: income, pendingBills: bills, debtPayments: debtDue,
                          cardInvoices: invoices, savingsTarget: savings, weeksRemaining: weeks,
                          spentThisWeek: spentWeek, weeklyAllowance: allowance,
                          remainingThisWeek: allowance - spentWeek)
    }
}

@MainActor
enum FinanceService {

    /// Cria uma transação; compras parceladas no cartão viram N transações mensais ligadas pelo mesmo grupo.
    @discardableResult
    static func addTransaction(title: String, amount: Double, kind: FinanceKind, category: FinanceCategory,
                               date: Date, card: CreditCard?, installments: Int, note: String = "",
                               context: ModelContext) -> [FinanceTransaction] {
        let n = max(1, card == nil ? 1 : installments)
        let rounded = (amount * 100).rounded() / 100
        let base = ((rounded / Double(n)) * 100).rounded(.down) / 100
        let group = n > 1 ? UUID() : nil
        var created: [FinanceTransaction] = []
        for i in 0..<n {
            // a última parcela absorve a diferença de centavos
            let value = i == n - 1 ? ((rounded - base * Double(n - 1)) * 100).rounded() / 100 : base
            let tx = FinanceTransaction(title: n > 1 ? "\(title) (\(i + 1)/\(n))" : title, amount: value,
                                        kind: kind, category: category, date: date.adding(months: i))
            tx.note = note
            tx.installmentGroup = group
            tx.installmentNumber = n > 1 ? i + 1 : 0
            tx.installmentCount = n > 1 ? n : 0
            tx.card = card
            context.insert(tx)
            created.append(tx)
        }
        return created
    }

    static func payInvoice(card: CreditCard, amount: Double, context: ModelContext) {
        let tx = FinanceTransaction(title: "Fatura \(card.name)", amount: amount, kind: .despesa, category: .faturaCartao)
        tx.isInvoicePayment = true
        tx.card = card
        context.insert(tx)
        context.saveQuietly()
    }

    /// Marca conta como paga (gera a transação) e avança para o próximo vencimento.
    static func settle(_ entry: RecurringEntry, context: ModelContext, date: Date = Date()) {
        let tx = FinanceTransaction(title: entry.title, amount: entry.amount, kind: entry.kind, category: entry.category, date: date)
        tx.note = "Gerado a partir de conta recorrente"
        context.insert(tx)
        entry.lastSettledAt = date
        if let next = entry.recurrence.next(after: entry.dueDate) {
            entry.dueDate = next
            NotificationScheduler.schedule(entry)
        } else {
            entry.isActive = false
            NotificationScheduler.cancel(entry: entry)
        }
        context.saveQuietly()
    }

    static func payDebt(_ debt: Debt, amount: Double, registerExpense: Bool, context: ModelContext, date: Date = Date()) {
        let remaining = max(0, debt.remainingAmount - amount)
        debt.remainingAmount = remaining
        let p = DebtPayment(date: date, amount: amount, remainingAfter: remaining)
        debt.payments.append(p)
        if registerExpense {
            let tx = FinanceTransaction(title: "Pagamento \(debt.creditor)", amount: amount, kind: .despesa, category: .dividas, date: date)
            context.insert(tx)
        }
        context.saveQuietly()
    }

    /// Aviso local quando o orçamento semanal é ultrapassado.
    static func checkBudgetAlert(context: ModelContext) {
        let profile = context.profile()
        let txs = (try? context.fetch(FetchDescriptor<FinanceTransaction>())) ?? []
        let rec = (try? context.fetch(FetchDescriptor<RecurringEntry>())) ?? []
        let debts = (try? context.fetch(FetchDescriptor<Debt>())) ?? []
        let cards = (try? context.fetch(FetchDescriptor<CreditCard>())) ?? []
        let plan = FinanceCalculator.weeklyPlan(profile: profile, transactions: txs, recurring: rec, debts: debts, cards: cards)
        let key = "budget.alert.\(FinanceCalculator.invoiceKey(Date().startOfWeek))-\(Fmt.calendar.component(.weekOfYear, from: Date()))"
        if plan.isOverBudget && plan.weeklyAllowance > 0 && !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            NotificationService.shared.notifyNow(id: "budget.\(key)", title: "Orçamento da semana ultrapassado",
                                                 body: "Seus gastos passaram do planejado para esta semana.", category: .contas)
        }
    }
}
