import SwiftUI
import SwiftData

/// "Perfil e ajustes": aberto pelo botão de engrenagem da Home.
/// Os módulos principais ficam na barra inferior; aqui ficam as áreas de apoio.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var goals: [PersonalGoal]
    @Query private var habits: [Habit]
    @Query private var docs: [VaultDocument]
    @State private var editingName = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    LazyVGrid(columns: columns, spacing: 12) {
                        NavigationLink { GrowthView() } label: {
                            ModuleTile(title: "Metas e hábitos",
                                       subtitle: "\(goals.filter { !$0.isCompleted }.count) metas · \(habits.filter { !$0.isArchived }.count) hábitos",
                                       icon: "target", module: .growth)
                        }
                        NavigationLink { VaultView() } label: {
                            ModuleTile(title: "Documentos", subtitle: "\(docs.count) arquivo(s)", icon: "lock.doc.fill", module: .docs)
                        }
                        NavigationLink { ReportsView() } label: {
                            ModuleTile(title: "Relatórios", subtitle: "Gráficos e exportação", icon: "chart.bar.doc.horizontal.fill", module: .reports)
                        }
                        NavigationLink { FoodView() } label: {
                            ModuleTile(title: "Alimentação", subtitle: "Estoque e receitas", icon: "fork.knife", module: .food)
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 0) {
                        row("Segurança e Privacidade", "lock.shield.fill", .teal) { SecurityPrivacyView() }
                        Divider().padding(.leading, 56)
                        row("Backup e restauração", "externaldrive.fill.badge.timemachine", .blue) { BackupView() }
                        Divider().padding(.leading, 56)
                        row("Notificações", "bell.badge.fill", .red) { NotificationSettingsView() }
                        Divider().padding(.leading, 56)
                        row("Configurações", "gearshape.fill", .gray) { SettingsView() }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Perfil e ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .sheet(isPresented: $editingName) { ProfileEditor() }
        }
    }

    private var header: some View {
        let name = profiles.first?.name ?? ""
        return Button { editingName = true } label: {
            HStack(spacing: 14) {
                Text(String(name.prefix(1)).uppercased().isEmpty ? "?" : String(name.prefix(1)).uppercased())
                    .font(.title.bold()).foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Theme.Module.assistant.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Seu perfil" : name).font(.title2.bold())
                    Text("Dados guardados somente neste iPhone").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func row<D: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
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

struct ProfileEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form { TextField("Nome", text: $name) }
                .navigationTitle("Perfil")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salvar") { context.profile().name = String(name.trimmed.prefix(40)); context.saveQuietly(); dismiss() }
                    }
                }
                .onAppear { name = context.profile().name }
        }
    }
}
