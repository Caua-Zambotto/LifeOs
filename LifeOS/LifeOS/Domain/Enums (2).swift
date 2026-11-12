import SwiftUI

// MARK: - Agenda

enum EventCategory: String, CaseIterable, Codable, Identifiable {
    case compromisso, reuniao, pessoal, prova, trabalho, entrega, consulta, treino, lembrete, dataImportante, estudo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compromisso: "Compromisso"
        case .reuniao: "Reunião"
        case .pessoal: "Pessoal"
        case .prova: "Prova"
        case .trabalho: "Trabalho"
        case .entrega: "Entrega"
        case .consulta: "Consulta"
        case .treino: "Treino"
        case .lembrete: "Lembrete"
        case .dataImportante: "Data importante"
        case .estudo: "Estudo"
        }
    }

    var icon: String {
        switch self {
        case .compromisso: "calendar"
        case .reuniao: "person.2.fill"
        case .pessoal: "person.fill"
        case .prova: "graduationcap.fill"
        case .trabalho: "doc.text.fill"
        case .entrega: "tray.and.arrow.up.fill"
        case .consulta: "cross.case.fill"
        case .treino: "figure.strengthtraining.traditional"
        case .lembrete: "bell.fill"
        case .dataImportante: "star.fill"
        case .estudo: "book.fill"
        }
    }

    var color: Color {
        switch self {
        case .compromisso: .blue
        case .reuniao: .indigo
        case .pessoal: .teal
        case .prova: .pink
        case .trabalho: .purple
        case .entrega: .orange
        case .consulta: .red
        case .treino: .green
        case .lembrete: .yellow
        case .dataImportante: .mint
        case .estudo: .cyan
        }
    }

    var isAcademic: Bool { [.prova, .trabalho, .entrega, .estudo].contains(self) }
    var isTask: Bool { [.trabalho, .entrega, .estudo, .lembrete].contains(self) }

    var notificationCategory: NotificationCategory {
        switch self {
        case .prova: .provas
        case .trabalho, .entrega: .trabalhos
        case .treino: .treinos
        case .estudo: .revisoes
        default: .compromissos
        }
    }
}

enum Priority: Int, CaseIterable, Codable, Identifiable {
    case baixa = 0, media = 1, alta = 2
    var id: Int { rawValue }
    var label: String {
        switch self { case .baixa: "Baixa"; case .media: "Média"; case .alta: "Alta" }
    }
    var color: Color {
        switch self { case .baixa: .gray; case .media: .orange; case .alta: .red }
    }
}

enum Recurrence: String, CaseIterable, Codable, Identifiable {
    case nenhuma, diaria, semanal, mensal, anual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .nenhuma: "Não repete"
        case .diaria: "Diariamente"
        case .semanal: "Semanalmente"
        case .mensal: "Mensalmente"
        case .anual: "Anualmente"
        }
    }

    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .nenhuma: nil
        case .diaria: calendar.date(byAdding: .day, value: 1, to: date)
        case .semanal: calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .mensal: calendar.date(byAdding: .month, value: 1, to: date)
        case .anual: calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

// MARK: - Estudos

enum TopicStatus: String, CaseIterable, Codable, Identifiable {
    case naoIniciado, estudando, concluido, revisar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .naoIniciado: "Não iniciado"
        case .estudando: "Estudando"
        case .concluido: "Concluído"
        case .revisar: "Precisa revisar"
        }
    }
    var icon: String {
        switch self {
        case .naoIniciado: "circle"
        case .estudando: "circle.lefthalf.filled"
        case .concluido: "checkmark.circle.fill"
        case .revisar: "arrow.clockwise.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .naoIniciado: .gray
        case .estudando: .blue
        case .concluido: .green
        case .revisar: .orange
        }
    }
}

enum ContestStatus: String, CaseIterable, Codable, Identifiable {
    case interesse, previsto, inscricoesAbertas, inscrito, realizado, encerrado
    var id: String { rawValue }
    var label: String {
        switch self {
        case .interesse: "Edital de interesse"
        case .previsto: "Previsto"
        case .inscricoesAbertas: "Inscrições abertas"
        case .inscrito: "Inscrito"
        case .realizado: "Prova realizada"
        case .encerrado: "Encerrado"
        }
    }
    var color: Color {
        switch self {
        case .interesse: .gray
        case .previsto: .blue
        case .inscricoesAbertas: .green
        case .inscrito: .purple
        case .realizado: .orange
        case .encerrado: .secondary
        }
    }
}

// MARK: - Finanças

enum FinanceKind: String, CaseIterable, Codable, Identifiable {
    case receita, despesa
    var id: String { rawValue }
    var label: String { self == .receita ? "Receita" : "Despesa" }
}

enum FinanceCategory: String, CaseIterable, Codable, Identifiable {
    // Receitas
    case salario, rendaExtra, servicos, outrasReceitas
    // Despesas
    case alimentacao, transporte, moradia, faculdade, saude, lazer, compras, assinaturas, internet, dividas, reserva, outros
    // Interno: pagamento de fatura (não entra em gráficos por categoria)
    case faturaCartao

    var id: String { rawValue }

    var kind: FinanceKind {
        switch self {
        case .salario, .rendaExtra, .servicos, .outrasReceitas: .receita
        default: .despesa
        }
    }

    static func selectable(for kind: FinanceKind) -> [FinanceCategory] {
        allCases.filter { $0.kind == kind && $0 != .faturaCartao }
    }

    var label: String {
        switch self {
        case .salario: "Salário"
        case .rendaExtra: "Renda extra"
        case .servicos: "Serviços"
        case .outrasReceitas: "Outras entradas"
        case .alimentacao: "Alimentação"
        case .transporte: "Transporte"
        case .moradia: "Moradia"
        case .faculdade: "Faculdade"
        case .saude: "Saúde"
        case .lazer: "Lazer"
        case .compras: "Compras"
        case .assinaturas: "Assinaturas"
        case .internet: "Internet e telefone"
        case .dividas: "Dívidas"
        case .reserva: "Reserva e metas"
        case .outros: "Outros"
        case .faturaCartao: "Pagamento de fatura"
        }
    }

    var icon: String {
        switch self {
        case .salario: "banknote.fill"
        case .rendaExtra: "sparkles"
        case .servicos: "wrench.and.screwdriver.fill"
        case .outrasReceitas: "arrow.down.circle.fill"
        case .alimentacao: "fork.knife"
        case .transporte: "car.fill"
        case .moradia: "house.fill"
        case .faculdade: "graduationcap.fill"
        case .saude: "heart.fill"
        case .lazer: "gamecontroller.fill"
        case .compras: "bag.fill"
        case .assinaturas: "repeat.circle.fill"
        case .internet: "wifi"
        case .dividas: "creditcard.trianglebadge.exclamationmark"
        case .reserva: "banknote"
        case .outros: "ellipsis.circle.fill"
        case .faturaCartao: "creditcard.fill"
        }
    }

    var color: Color {
        switch self {
        case .salario: .green
        case .rendaExtra: .mint
        case .servicos: .teal
        case .outrasReceitas: .cyan
        case .alimentacao: .orange
        case .transporte: .blue
        case .moradia: .brown
        case .faculdade: .purple
        case .saude: .red
        case .lazer: .pink
        case .compras: .indigo
        case .assinaturas: .yellow
        case .internet: .cyan
        case .dividas: Color(red: 0.75, green: 0.2, blue: 0.2)
        case .reserva: .green
        case .outros: .gray
        case .faturaCartao: .gray
        }
    }
}

// MARK: - Desenvolvimento pessoal

enum GoalHorizon: String, CaseIterable, Codable, Identifiable {
    case curto, medio, longo
    var id: String { rawValue }
    var label: String {
        switch self { case .curto: "Curto prazo"; case .medio: "Médio prazo"; case .longo: "Longo prazo" }
    }
}

enum GoalArea: String, CaseIterable, Codable, Identifiable {
    case pessoal, profissional, leitura, aprendizado, idiomas, saude, financeira
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pessoal: "Pessoal"
        case .profissional: "Profissional"
        case .leitura: "Leitura"
        case .aprendizado: "Aprendizado"
        case .idiomas: "Idiomas"
        case .saude: "Saúde"
        case .financeira: "Financeira"
        }
    }
    var icon: String {
        switch self {
        case .pessoal: "person.fill"
        case .profissional: "briefcase.fill"
        case .leitura: "book.closed.fill"
        case .aprendizado: "lightbulb.fill"
        case .idiomas: "character.bubble.fill"
        case .saude: "heart.fill"
        case .financeira: "dollarsign.circle.fill"
        }
    }
}

// MARK: - Documentos

enum DocumentCategory: String, CaseIterable, Codable, Identifiable {
    case edital, comprovante, academico, recibo, anotacao, pessoal, outro
    var id: String { rawValue }
    var label: String {
        switch self {
        case .edital: "Edital"
        case .comprovante: "Comprovante"
        case .academico: "Acadêmico"
        case .recibo: "Recibo"
        case .anotacao: "Anotação"
        case .pessoal: "Pessoal"
        case .outro: "Outro"
        }
    }
    var icon: String {
        switch self {
        case .edital: "doc.richtext.fill"
        case .comprovante: "checkmark.seal.fill"
        case .academico: "graduationcap.fill"
        case .recibo: "doc.plaintext.fill"
        case .anotacao: "note.text"
        case .pessoal: "person.text.rectangle.fill"
        case .outro: "doc.fill"
        }
    }
}

// MARK: - Notificações

enum NotificationCategory: String, CaseIterable, Codable, Identifiable {
    case provas, trabalhos, compromissos, contas, treinos, revisoes, habitos, metas
    var id: String { rawValue }
    var label: String {
        switch self {
        case .provas: "Provas"
        case .trabalhos: "Trabalhos e entregas"
        case .compromissos: "Compromissos"
        case .contas: "Contas e vencimentos"
        case .treinos: "Treinos"
        case .revisoes: "Revisões e estudos"
        case .habitos: "Hábitos"
        case .metas: "Metas"
        }
    }
    var icon: String {
        switch self {
        case .provas: "graduationcap.fill"
        case .trabalhos: "doc.text.fill"
        case .compromissos: "calendar"
        case .contas: "creditcard.fill"
        case .treinos: "figure.run"
        case .revisoes: "arrow.clockwise"
        case .habitos: "checkmark.circle.fill"
        case .metas: "target"
        }
    }
    /// Antecedência padrão em minutos.
    var defaultLead: Int {
        switch self {
        case .provas: 24 * 60
        case .trabalhos: 24 * 60
        case .compromissos: 60
        case .contas: 24 * 60
        case .treinos: 0
        case .revisoes: 0
        case .habitos: 0
        case .metas: 24 * 60
        }
    }
}

enum ChatRole: String, Codable { case user, assistant }
