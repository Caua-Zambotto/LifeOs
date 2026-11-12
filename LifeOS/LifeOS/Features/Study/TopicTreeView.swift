import SwiftUI
import SwiftData
import Charts

/// Lista hierárquica de assuntos/subtópicos com status e revisão espaçada.
/// Usada tanto em matérias da faculdade quanto em matérias de concurso.
struct TopicTreeView: View {
    let topics: [StudyTopic]
    var onAdd: (_ title: String, _ parent: StudyTopic?) -> Void
    @Environment(\.modelContext) private var context
    @State private var newTitle = ""
    @State private var addingChildTo: StudyTopic?
    @State private var childTitle = ""

    private var roots: [StudyTopic] { topics.filter { $0.parent == nil }.sorted { $0.order < $1.order } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Novo assunto", text: $newTitle)
                    .onSubmit(addRoot)
                Button(action: addRoot) { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(newTitle.trimmed.isEmpty)
            }
            .card(padding: 12)

            if roots.isEmpty {
                Text("Cadastre os assuntos para acompanhar o progresso.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(roots) { t in
                TopicRow(topic: t, level: 0, onAddChild: { addingChildTo = $0 })
            }
        }
        .alert("Novo subtópico", isPresented: Binding(get: { addingChildTo != nil }, set: { if !$0 { addingChildTo = nil } })) {
            TextField("Título", text: $childTitle)
            Button("Adicionar") {
                if !childTitle.trimmed.isEmpty { onAdd(childTitle.trimmed, addingChildTo) }
                childTitle = ""; addingChildTo = nil
            }
            Button("Cancelar", role: .cancel) { childTitle = ""; addingChildTo = nil }
        }
    }

    private func addRoot() {
        let t = newTitle.trimmed
        guard !t.isEmpty else { return }
        onAdd(t, nil)
        newTitle = ""
    }
}

struct TopicRow: View {
    @Bindable var topic: StudyTopic
    let level: Int
    var onAddChild: (StudyTopic) -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(TopicStatus.allCases) { s in
                        Button { StudyReview.setStatus(s, for: topic); context.saveQuietly() } label: {
                            Label(s.label, systemImage: s.icon)
                        }
                    }
                } label: {
                    Image(systemName: topic.status.icon).font(.title3).foregroundStyle(topic.status.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title).font(level == 0 ? .subheadline.weight(.semibold) : .subheadline)
                    HStack(spacing: 6) {
                        Text(topic.status.label)
                        if let next = topic.nextReview {
                            Text("· revisão \(Fmt.relativeDay(next))").foregroundStyle(next <= Date() ? .orange : .secondary)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if StudyReview.isDue(topic) {
                    Button("Revisado") { StudyReview.markReviewed(topic); context.saveQuietly() }
                        .font(.caption).buttonStyle(.bordered)
                }
                Menu {
                    if level < 2 { Button("Adicionar subtópico", systemImage: "plus") { onAddChild(topic) } }
                    Button("Excluir", systemImage: "trash", role: .destructive) {
                        context.delete(topic)
                        context.saveQuietly()
                    }
                } label: { Image(systemName: "ellipsis").padding(6) }
            }
            .padding(.leading, CGFloat(level) * 18)
            ForEach(topic.children.sorted { $0.order < $1.order }) { child in
                TopicRow(topic: child, level: level + 1, onAddChild: onAddChild)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Gráfico de pizza de status dos assuntos.
struct TopicStatusChart: View {
    let topics: [StudyTopic]

    struct StatusCount: Identifiable {
        let status: TopicStatus
        let count: Int
        var id: String { status.rawValue }
    }

    var body: some View {
        let all = StudyReview.flatten(topics.filter { $0.parent == nil })
        let counts = TopicStatus.allCases
            .map { s in StatusCount(status: s, count: all.filter { $0.status == s }.count) }
            .filter { $0.count > 0 }
        if all.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 20) {
                Chart(counts) { item in
                    SectorMark(angle: .value("Qtd", item.count), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(item.status.color)
                        .cornerRadius(4)
                }
                .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(counts) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.status.color).frame(width: 8, height: 8)
                            Text("\(item.status.label): \(item.count)").font(.caption)
                        }
                    }
                }
            }
        }
    }
}
