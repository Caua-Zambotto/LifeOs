import SwiftUI
import UniformTypeIdentifiers

/// Documento binário genérico para `.fileExporter` (salvar no app Arquivos / iCloud Drive / computador).
struct BinaryFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum CSVExporter {
    static func escape(_ s: String) -> String {
        // Evita injeção de fórmulas ao abrir em planilhas.
        var v = s
        if let first = v.first, "=+-@".contains(first) { v = "'" + v }
        if v.contains(";") || v.contains("\"") || v.contains("\n") {
            v = "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    static func make(header: [String], rows: [[String]]) -> Data {
        // Separador ";" e BOM UTF-8: abre corretamente no Excel em português.
        let lines = [header] + rows
        let text = lines.map { $0.map(escape).joined(separator: ";") }.joined(separator: "\n")
        return Data("\u{FEFF}".utf8) + Data(text.utf8)
    }

    static func number(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }

    static func transactions(_ txs: [FinanceTransaction]) -> Data {
        make(header: ["Data", "Tipo", "Categoria", "Descrição", "Valor", "Cartão", "Parcela"],
             rows: txs.sorted { $0.date < $1.date }.map {
                 [Fmt.short($0.date), $0.kind.label, $0.category.label, $0.title, number($0.amount),
                  $0.card?.name ?? "", $0.installmentCount > 0 ? "\($0.installmentNumber)/\($0.installmentCount)" : ""]
             })
    }

    static func body(_ items: [BodyMeasurement]) -> Data {
        func f(_ v: Double?) -> String { v.map { number($0) } ?? "" }
        return make(header: ["Data", "Peso", "Cintura", "Braço", "Peito", "Perna", "Quadril", "Gordura %"],
                    rows: items.sorted { $0.date < $1.date }.map {
                        [Fmt.short($0.date), f($0.weight), f($0.waist), f($0.arm), f($0.chest), f($0.leg), f($0.hip), f($0.bodyFat)]
                    })
    }

    static func workouts(_ items: [WorkoutSession]) -> Data {
        var rows: [[String]] = []
        for s in items.sorted(by: { $0.date < $1.date }) {
            if s.entries.isEmpty {
                rows.append([Fmt.short(s.date), s.title, "", "", "", ""])
            }
            for e in s.sortedEntries {
                rows.append([Fmt.short(s.date), s.title, e.name, "\(e.sets)", "\(e.reps)", number(e.load)])
            }
        }
        return make(header: ["Data", "Treino", "Exercício", "Séries", "Repetições", "Carga (kg)"], rows: rows)
    }

    static func study(_ items: [StudySession]) -> Data {
        make(header: ["Data", "Minutos", "Matéria", "Concurso", "Observação"],
             rows: items.sorted { $0.date < $1.date }.map {
                 [Fmt.short($0.date), "\($0.minutes)", $0.subject?.name ?? $0.contestSubject?.name ?? "",
                  $0.contest?.displayName ?? "", $0.note]
             })
    }

    static func habits(_ habits: [Habit]) -> Data {
        var rows: [[String]] = []
        for h in habits {
            for c in h.checkins.sorted(by: { $0.date < $1.date }) { rows.append([Fmt.short(c.date), h.name]) }
        }
        return make(header: ["Data", "Hábito"], rows: rows)
    }
}

enum PDFExporter {
    /// Renderiza uma view SwiftUI em um PDF (página do tamanho do conteúdo, largura A4).
    @MainActor
    static func render<V: View>(_ view: V, fileName: String) throws -> URL {
        let url = AppPaths.temp.appendingPathComponent(fileName)
        let renderer = ImageRenderer(content: view.frame(width: 595).environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)
        var thrown: Error?
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: 595, height: max(size.height, 842)))
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { thrown = CocoaError(.fileWriteUnknown); return }
            ctx.beginPDFPage(nil)
            // conteúdo no topo da página
            ctx.translateBy(x: 0, y: box.height - size.height)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        if let thrown { throw thrown }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return url
    }
}
