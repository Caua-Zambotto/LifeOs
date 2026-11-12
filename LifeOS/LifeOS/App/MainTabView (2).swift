import SwiftUI
import SwiftData

/// Estrutura principal: seis módulos independentes + barra inferior fixa.
/// O TabView padrão do iOS mostra no máximo 5 abas (a 6ª vira "Mais"),
/// por isso a barra é própria. Os módulos ficam vivos ao trocar de aba
/// (mantêm rolagem e navegação), como no TabView nativo.
struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        ZStack {
            ForEach(AppState.Tab.allCases) { tab in
                moduleView(tab)
                    .opacity(appState.selectedTab == tab ? 1 : 0)
                    .allowsHitTesting(appState.selectedTab == tab)
                    .accessibilityHidden(appState.selectedTab != tab)
                    .tint(tab.module.tint)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ModuleTabBar(selection: $state.selectedTab)
        }
        .sheet(isPresented: $state.showQuickAdd) {
            QuickAddSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $state.showAssistant) {
            AssistantView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $state.showSettings) {
            ProfileView()
        }
    }

    @ViewBuilder
    private func moduleView(_ tab: AppState.Tab) -> some View {
        switch tab {
        case .home: HomeView()
        case .studies: StudiesView()
        case .calendar: AgendaView()
        case .training: TrainingView()
        case .contests: EditaisView()
        case .finance: FinanceView()
        }
    }
}

/// Barra de navegação inferior com os seis módulos.
struct ModuleTabBar: View {
    @Binding var selection: AppState.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppState.Tab.allCases) { tab in
                let selected = selection == tab
                Button {
                    if selection != tab {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selected ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 19, weight: selected ? .semibold : .regular))
                            .symbolEffect(.bounce, value: selected)
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selected ? tab.module.tint : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Adição rápida: frase livre (vai para o assistente) ou atalhos para formulários curtos.
struct QuickAddSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var route: QuickRoute?
    @FocusState private var focused: Bool

    enum QuickRoute: String, Identifiable, CaseIterable {
        case expense, income, event, weight, workout, pantry, document, goal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .expense: "Despesa"
            case .income: "Receita"
            case .event: "Evento"
            case .weight: "Peso"
            case .workout: "Treino"
            case .pantry: "Alimento"
            case .document: "Documento"
            case .goal: "Meta"
            }
        }
        var icon: String {
            switch self {
            case .expense: "arrow.up.right"
            case .income: "arrow.down.left"
            case .event: "calendar.badge.plus"
            case .weight: "scalemass.fill"
            case .workout: "figure.strengthtraining.traditional"
            case .pantry: "cart.fill"
            case .document: "doc.badge.plus"
            case .goal: "target"
            }
        }
        var module: Theme.Module {
            switch self {
            case .expense, .income: .finance
            case .event: .agenda
            case .weight: .body
            case .workout: .fitness
            case .pantry: .food
            case .document: .docs
            case .goal: .growth
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        TextField("Ex.: gastei 35 reais no almoço", text: $text, axis: .vertical)
                            .focused($focused)
                            .lineLimit(1...3)
                            .submitLabel(.send)
                            .onSubmit(send)
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill").font(.title)
                        }
                        .disabled(text.trimmed.isEmpty)
                    }
                    .card(padding: 14)

                    Text("Atalhos").font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(QuickRoute.allCases) { r in
                            Button { route = r } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: r.icon)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 50, height: 50)
                                        .background(r.module.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    Text(r.title).font(.caption).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Adicionar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .sheet(item: $route) { r in
                switch r {
                case .expense: TransactionEditor(kind: .despesa)
                case .income: TransactionEditor(kind: .receita)
                case .event: EventEditorView(event: nil)
                case .weight: BodyMeasurementEditor()
                case .workout: WorkoutSessionEditor(session: nil, plan: nil)
                case .pantry: PantryItemEditor(item: nil)
                case .document: VaultImportSheet()
                case .goal: GoalEditor(goal: nil)
                }
            }
        }
    }

    private func send() {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        dismiss()
        // Abre o assistente depois que esta folha fecha.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { appState.openAssistant(with: t) }
    }
}
