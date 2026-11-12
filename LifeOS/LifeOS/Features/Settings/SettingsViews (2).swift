import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Configurações

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @State private var customizing = false

    var body: some View {
        Form {
            Section("Aparência") {
                Picker("Tema", selection: $appearance) {
                    Text("Automático").tag("system")
                    Text("Claro").tag("light")
                    Text("Escuro").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section("Tela inicial") {
                Button("Personalizar cartões do \"Meu dia\"") { customizing = true }
            }
            Section("Geral") {
                NavigationLink("Notificações") { NotificationSettingsView() }
                NavigationLink("Segurança e Privacidade") { SecurityPrivacyView() }
                NavigationLink("Backup, exportação e restauração") { BackupView() }
                NavigationLink("Armazenamento") { StorageView() }
            }
            Section("Sobre") {
                NavigationLink("Limitações conhecidas") { LimitationsView() }
                LabeledContent("Versão", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Text("Sem anúncios, sem rastreadores, sem servidores. Todos os dados ficam neste iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Configurações")
        .sheet(isPresented: $customizing) { DashboardCustomizeView() }
    }
}

// MARK: - Notificações

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var enabled: [NotificationCategory: Bool] = [:]
    @State private var leads: [NotificationCategory: Int] = [:]
    @State private var hour = NotificationSettings.defaultHour
    @State private var status = "Verificando…"
    @State private var pending = 0

    var body: some View {
        Form {
            Section(footer: Text("Notificações locais: funcionam sem internet e sem servidores. O iOS permite no máximo 64 avisos agendados; o LifeOS prioriza os mais próximos.")) {
                LabeledContent("Permissão do iOS", value: status)
                LabeledContent("Avisos agendados", value: "\(pending)")
                Button("Solicitar permissão") {
                    Task { _ = await NotificationService.shared.requestAuthorization(); await refresh() }
                }
                Button("Enviar notificação de teste") {
                    NotificationService.shared.notifyNow(id: "test.\(UUID().uuidString)", title: "LifeOS", body: "As notificações estão funcionando.", category: .compromissos)
                }
            }
            Section("Categorias") {
                ForEach(NotificationCategory.allCases) { c in
                    VStack(alignment: .leading) {
                        Toggle(isOn: Binding(get: { enabled[c] ?? true }, set: { enabled[c] = $0; NotificationSettings.setEnabled(c, $0) })) {
                            Label(c.label, systemImage: c.icon)
                        }
                        if enabled[c] ?? true, [.provas, .trabalhos, .compromissos, .contas, .metas].contains(c) {
                            Picker("Antecedência padrão", selection: Binding(get: { leads[c] ?? c.defaultLead }, set: { leads[c] = $0; NotificationSettings.setLead(c, $0) })) {
                                ForEach(NotificationSettings.leadOptions) { Text($0.label).tag($0.minutes) }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            Section(footer: Text("Usado para contas, revisões e eventos de dia inteiro.")) {
                Stepper("Horário padrão: \(hour):00", value: $hour, in: 5...22)
                    .onChange(of: hour) { _, h in NotificationSettings.defaultHour = h }
            }
            Section {
                Button("Reaplicar configurações a todos os avisos") {
                    NotificationScheduler.rescheduleAll(context: context)
                    Task { try? await Task.sleep(nanoseconds: 500_000_000); await refresh() }
                }
            }
        }
        .navigationTitle("Notificações")
        .task {
            for c in NotificationCategory.allCases {
                enabled[c] = NotificationSettings.isEnabled(c)
                leads[c] = NotificationSettings.lead(c)
            }
            await refresh()
        }
    }

    private func refresh() async {
        let s = await NotificationService.shared.authorizationStatus()
        status = switch s {
        case .authorized, .provisional, .ephemeral: "Permitida"
        case .denied: "Negada (ative em Ajustes do iOS)"
        default: "Não solicitada"
        }
        pending = await NotificationService.shared.pendingCount()
    }
}

// MARK: - Segurança e Privacidade

struct SecurityPrivacyView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppLockManager.self) private var lock
    @AppStorage("onboarding.done") private var onboardingDone = true
    @State private var changingPasscode = false
    @State private var authForChange = false
    @State private var authForWipe = false
    @State private var confirmWipe = false
    @State private var wipeText = ""

    var body: some View {
        Form {
            Section("Status de proteção") {
                status("Senha do app", lock.hasPasscode, "PIN de 6 dígitos com PBKDF2 no Keychain")
                status(BiometricService.biometryName, lock.biometricsEnabled, BiometricService.isAvailable ? "Disponível neste aparelho" : "Indisponível")
                status("Bloqueio automático", true, AppLockManager.autoLockOptions.first { $0.seconds == lock.autoLockSeconds }?.label ?? "")
                status("Banco de dados protegido", AppPaths.protectionLevel(of: AppPaths.database) != FileProtectionType.none,
                       "Proteção de dados do iOS (requer código no iPhone)")
                status("Cofre de documentos", true, "AES-256-GCM + proteção \"complete\"")
                status("Último backup", BackupService.lastBackupDate != nil,
                       BackupService.lastBackupDate.map { Fmt.relativeDay($0).capitalizedFirst } ?? "Nunca — recomendado fazer um")
            }
            Section("Acesso") {
                if BiometricService.isAvailable {
                    Toggle("Desbloquear com \(BiometricService.biometryName)", isOn: Binding(
                        get: { lock.biometricsEnabled },
                        set: { newValue in
                            if newValue {
                                Task { if await BiometricService.authenticate(reason: "Ativar \(BiometricService.biometryName)") { lock.setBiometrics(true) } }
                            } else { lock.setBiometrics(false) }
                        }))
                }
                Button("Alterar senha") { authForChange = true }
                Picker("Bloquear após", selection: Binding(get: { lock.autoLockSeconds }, set: { lock.setAutoLock($0) })) {
                    ForEach(AppLockManager.autoLockOptions, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                Button("Bloquear agora") { lock.lock() }
            }
            Section("Dados") {
                NavigationLink("Backup e exportação") { BackupView() }
                NavigationLink("Gerenciar armazenamento e arquivos") { StorageView() }
                NavigationLink("Limitações de segurança") { LimitationsView() }
            }
            Section(footer: Text("Apaga permanentemente todos os registros, documentos, senha e chaves deste aparelho. Backups exportados não são afetados.")) {
                Button("Excluir todos os dados", role: .destructive) { authForWipe = true }
            }
            Section("Privacidade") {
                Label("Nenhum dado é enviado para servidores", systemImage: "icloud.slash")
                Label("Sem rastreadores, anúncios ou analytics", systemImage: "eye.slash")
                Label("Logs não contêm dados pessoais ou financeiros", systemImage: "doc.text.magnifyingglass")
                Label("Tela oculta no seletor de apps", systemImage: "rectangle.on.rectangle.slash")
            }
            .font(.subheadline)
        }
        .navigationTitle("Segurança e Privacidade")
        .sheet(isPresented: $authForChange) { AuthGateView(reason: "Confirme para alterar a senha") { changingPasscode = true } }
        .sheet(isPresented: $changingPasscode) { PasscodeSetupView { } }
        .sheet(isPresented: $authForWipe) { AuthGateView(reason: "Confirme para excluir todos os dados") { confirmWipe = true } }
        .alert("Excluir tudo?", isPresented: $confirmWipe) {
            TextField("Digite EXCLUIR", text: $wipeText)
            Button("Excluir definitivamente", role: .destructive) {
                if wipeText.trimmed.uppercased() == "EXCLUIR" { wipeAll() }
                wipeText = ""
            }
            Button("Cancelar", role: .cancel) { wipeText = "" }
        } message: {
            Text("Esta ação não pode ser desfeita. Faça um backup antes, se quiser guardar seus dados.")
        }
    }

    private func status(_ title: String, _ ok: Bool, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill").foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func wipeAll() {
        try? Persistence.deleteAllRecords(in: context)
        VaultStorage.deleteAllFiles()
        NotificationService.shared.cancelAll()
        KeychainService.deleteAll()
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key != "install.marker" {
            defaults.removeObject(forKey: key)
        }
        DataSeeder.seedIfNeeded(context)
        lock.passcodeChanged()
        onboardingDone = false
    }
}

// MARK: - Backup

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @State private var password = ""
    @State private var confirm = ""
    @State private var includeDocs = true
    @State private var exportDoc: BinaryFileDocument?
    @State private var exportName = ""
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importedData: Data?
    @State private var restorePassword = ""
    @State private var preview: BackupPayload?
    @State private var webPreview: WebImporter.Payload?
    @State private var confirmRestore = false
    @State private var working = false
    @State private var message: String?
    @State private var acceptedRisk = false
    @State private var plainJSON = false

    var body: some View {
        Form {
            Section {
                Label("Seus dados ficam apenas neste iPhone. Sem backup, perder ou trocar o aparelho significa perder tudo.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(.orange)
                LabeledContent("Último backup", value: BackupService.lastBackupDate.map(Fmt.dateTime) ?? "Nunca")
            }

            Section(header: Text("Criar backup criptografado"),
                    footer: Text("Criptografia AES-256-GCM com chave derivada da sua senha (PBKDF2, 310 mil iterações). Salve o arquivo no app Arquivos, iCloud Drive ou envie para o computador.")) {
                SecureField("Senha do backup (mín. 8 caracteres)", text: $password)
                SecureField("Confirmar senha", text: $confirm)
                Toggle("Incluir documentos do cofre", isOn: $includeDocs)
                Toggle("Entendo que, se eu esquecer esta senha, o backup NÃO poderá ser recuperado por ninguém", isOn: $acceptedRisk)
                    .font(.footnote)
                Button("Gerar backup") { Task { await createBackup() } }
                    .disabled(password.count < 8 || password != confirm || !acceptedRisk || working)
            }

            Section(header: Text("Restaurar ou importar"),
                    footer: Text("Aceita backups deste app e também os da antiga versão web/PC do LifeOS (arquivo .lifeosbackup ou exportação JSON). A restauração SUBSTITUI todos os dados atuais; o arquivo é verificado (integridade + senha) antes de qualquer alteração.")) {
                Button("Escolher arquivo de backup") { showImporter = true }
                if importedData != nil && preview == nil && webPreview == nil {
                    SecureField("Senha do backup", text: $restorePassword)
                    Button("Verificar arquivo") { Task { await verify() } }.disabled(restorePassword.isEmpty || working)
                }
                if let p = preview {
                    Text("Backup de \(Fmt.dateTime(p.createdAt)) · versão \(p.appVersion)").font(.subheadline.weight(.semibold))
                    ForEach(p.summary.filter { $0.1 > 0 }, id: \.0) { item in
                        LabeledContent(item.0, value: "\(item.1)")
                    }
                    Button("Restaurar este backup", role: .destructive) { confirmRestore = true }
                }
                if let w = webPreview {
                    Text("Dados da versão web\(w.createdAt.map { " · \(Fmt.dateTime($0))" } ?? "")").font(.subheadline.weight(.semibold))
                    ForEach(w.summary, id: \.0) { item in
                        LabeledContent(item.0, value: "\(item.1)")
                    }
                    Button("Importar para este iPhone", role: .destructive) { confirmRestore = true }
                }
            }

            Section(header: Text("Exportação aberta"), footer: Text("JSON legível, SEM criptografia. Use apenas se precisar dos dados em outro programa e guarde em local seguro.")) {
                Button("Exportar todos os dados em JSON") { Task { await exportJSON() } }
            }

            Section("Como recuperar em outro iPhone") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Gere um backup aqui e salve no iCloud Drive, em um computador ou pendrive.")
                    Text("2. No novo iPhone, instale o LifeOS e conclua a configuração inicial.")
                    Text("3. Em Perfil › Backup, toque em \"Escolher arquivo de backup\", informe a senha e restaure.")
                    Text("O espaço gratuito do iCloud (5 GB) pode não ser suficiente se você guardar muitos documentos. Um computador também serve.")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
            if working { ProgressView() }
        }
        .navigationTitle("Backup")
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .data, defaultFilename: exportName) { result in
            if case .success = result, !plainJSON {
                BackupService.lastBackupDate = Date()
                message = "Backup salvo. Guarde a senha em local seguro."
            }
            exportDoc = nil
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            preview = nil
            webPreview = nil
            restorePassword = ""
            importedData = try? Data(contentsOf: url)
            if importedData == nil { message = "Não foi possível ler o arquivo." }
            // JSON aberto (sem senha): deste app ou da versão web
            if let d = importedData {
                if let p = try? BackupService.plainPayload(from: d) { preview = p }
                else if let w = WebImporter.plainExport(d) { webPreview = w }
            }
        }
        .confirmationDialog("Substituir TODOS os dados atuais pelo backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restaurar", role: .destructive) { restore() }
        }
        .alert("Backup", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
    }

    @MainActor
    private func createBackup() async {
        working = true
        defer { working = false }
        do {
            let payload = try BackupService.snapshot(context: context, includeDocuments: includeDocs)
            let pwd = password
            let data = try await Task.detached(priority: .userInitiated) { try BackupService.encrypt(payload, password: pwd) }.value
            // verificação imediata: o arquivo gerado abre com a senha?
            _ = try await Task.detached(priority: .userInitiated) { try BackupService.decrypt(data, password: pwd) }.value
            plainJSON = false
            exportDoc = BinaryFileDocument(data: data)
            exportName = BackupService.defaultFileName()
            showExporter = true
            password = ""; confirm = ""; acceptedRisk = false
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "Falha ao gerar o backup."
        }
    }

    @MainActor
    private func verify() async {
        guard let data = importedData else { return }
        working = true
        defer { working = false }
        let pwd = restorePassword
        do {
            if WebImporter.isEncryptedWebBackup(data) {
                // A descriptografia da versão web roda fora da thread principal (PBKDF2 é custoso).
                webPreview = try await Task.detached(priority: .userInitiated) { try WebImporter.decrypt(data, password: pwd) }.value
            } else {
                preview = try await Task.detached(priority: .userInitiated) { try BackupService.decrypt(data, password: pwd) }.value
            }
            message = "Arquivo íntegro e senha correta."
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "Não foi possível abrir o backup."
        }
    }

    private func restore() {
        if let w = webPreview {
            do {
                try WebImporter.restore(w, context: context)
                message = "Dados da versão web importados com sucesso."
                webPreview = nil; importedData = nil; restorePassword = ""
            } catch {
                message = "Falha na importação. Tente novamente com o mesmo arquivo."
            }
            return
        }
        guard let p = preview else { return }
        do {
            try BackupService.restore(p, context: context)
            message = "Dados restaurados com sucesso."
            preview = nil; importedData = nil; restorePassword = ""
        } catch {
            message = "Falha na restauração. Seus dados podem estar incompletos; tente novamente com o mesmo arquivo."
        }
    }

    @MainActor
    private func exportJSON() async {
        do {
            let payload = try BackupService.snapshot(context: context, includeDocuments: false)
            plainJSON = true
            exportDoc = BinaryFileDocument(data: try BackupService.plainJSON(payload))
            exportName = "LifeOS-dados.json"
            showExporter = true
        } catch {
            message = "Falha ao exportar."
        }
    }
}

// MARK: - Armazenamento

struct StorageView: View {
    @State private var dbSize: Int64 = 0
    @State private var vaultSize: Int64 = 0
    @State private var tempSize: Int64 = 0

    var body: some View {
        Form {
            Section("Uso de espaço") {
                LabeledContent("Banco de dados", value: Fmt.bytes(dbSize))
                LabeledContent("Cofre de documentos", value: Fmt.bytes(vaultSize))
                LabeledContent("Temporários", value: Fmt.bytes(tempSize))
                LabeledContent("Total", value: Fmt.bytes(dbSize + vaultSize + tempSize))
            }
            Section(footer: Text("Arquivos temporários são cópias descriptografadas criadas ao visualizar ou exportar. Eles já são apagados ao sair do app.")) {
                Button("Limpar temporários") { AppPaths.clearTemp(); refresh() }
            }
            Section("Onde ficam os dados") {
                Text("Banco: Application Support/LifeOS/Database (SQLite via SwiftData, proteção de dados do iOS).")
                Text("Documentos: Application Support/LifeOS/Vault (arquivos .lockbox criptografados).")
                Text("Chaves e senha: Keychain do iOS, somente este aparelho.")
            }
            .font(.footnote)
        }
        .navigationTitle("Armazenamento")
        .onAppear(perform: refresh)
    }

    private func refresh() {
        dbSize = AppPaths.size(of: AppPaths.database)
        vaultSize = AppPaths.size(of: AppPaths.vault)
        tempSize = AppPaths.size(of: AppPaths.temp)
    }
}

// MARK: - Limitações

struct LimitationsView: View {
    var body: some View {
        List {
            Section("Segurança — o que o LifeOS NÃO garante") {
                Text("Nenhum aplicativo é inviolável. A proteção depende de o iPhone ter código de bloqueio ativo e do iOS estar atualizado.")
                Text("O banco de dados usa a proteção de dados padrão do iOS (disponível após o primeiro desbloqueio). Ele não é criptografado com a senha do app; a senha do app controla o acesso pela interface.")
                Text("Um iPhone com jailbreak, malware ou acesso físico desbloqueado pode expor dados.")
                Text("Documentos dependem de uma chave no Keychain deste aparelho. Se o iPhone for trocado sem um backup do LifeOS, os documentos não poderão ser abertos.")
                Text("Se você esquecer a senha de um backup criptografado, ele não pode ser recuperado.")
                Text("Notificações aparecem na tela de bloqueio; por isso não exibem valores.")
            }
            Section("Funcionalidades") {
                Text("O assistente usa regras locais em português: entende frases comuns, mas não tudo. Sempre há confirmação antes de salvar.")
                Text("A identificação de alimentos por foto usa o classificador genérico do iOS e pode errar; você confirma cada item.")
                Text("Informações nutricionais das receitas são estimativas.")
                Text("Concursos: não há busca automática de editais nesta versão; os dados são cadastrados por você.")
                Text("Não há sincronização entre aparelhos; use o backup.")
                Text("O iOS limita a 64 notificações agendadas por app.")
            }
        }
        .font(.subheadline)
        .navigationTitle("Limitações")
    }
}
