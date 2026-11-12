import SwiftUI
import Observation

/// Controla o bloqueio do app: senha, Face ID e bloqueio automático por inatividade.
@Observable
@MainActor
final class AppLockManager {
    var isLocked: Bool = true
    private(set) var biometricsEnabled: Bool
    private(set) var autoLockSeconds: Int

    private var backgroundedAt: Date?
    private var lastActivity = Date()
    private var timer: Timer?
    private var didBootstrap = false

    static let autoLockOptions: [(label: String, seconds: Int)] = [
        ("Imediatamente", 0), ("30 segundos", 30), ("1 minuto", 60),
        ("2 minutos", 120), ("5 minutos", 300), ("15 minutos", 900),
    ]

    init() {
        let defaults = UserDefaults.standard
        biometricsEnabled = defaults.bool(forKey: "security.biometrics")
        autoLockSeconds = defaults.object(forKey: "security.autolock") as? Int ?? 60
    }

    /// Espelho observável do estado do Keychain (atualizado por `passcodeChanged()`).
    private(set) var hasPasscode: Bool = PasscodeManager.shared.hasPasscode

    /// Chamar após criar, alterar ou remover a senha.
    func passcodeChanged() {
        hasPasscode = PasscodeManager.shared.hasPasscode
        if hasPasscode { isLocked = false }
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        // No iOS, itens do Keychain podem sobreviver à remoção do app.
        // Em uma instalação nova, limpamos credenciais antigas.
        if !UserDefaults.standard.bool(forKey: "install.marker") {
            KeychainService.deleteAll()
            UserDefaults.standard.set(true, forKey: "install.marker")
        }
        hasPasscode = PasscodeManager.shared.hasPasscode
        isLocked = hasPasscode
        AppPaths.clearTemp()
        startIdleTimer()
    }

    func setBiometrics(_ enabled: Bool) {
        biometricsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "security.biometrics")
    }

    func setAutoLock(_ seconds: Int) {
        autoLockSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: "security.autolock")
    }

    func handle(phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundedAt = Date()
            AppPaths.clearTemp()
            if autoLockSeconds == 0 { lock() }
        case .active:
            if let b = backgroundedAt, Date().timeIntervalSince(b) >= Double(autoLockSeconds) { lock() }
            backgroundedAt = nil
            lastActivity = Date()
        default:
            break
        }
    }

    func registerActivity() { lastActivity = Date() }

    func lock() {
        if hasPasscode { isLocked = true }
    }

    func unlockWithBiometrics() async {
        guard biometricsEnabled, isLocked else { return }
        if await BiometricService.authenticate(reason: "Desbloquear o LifeOS") {
            unlocked()
        }
    }

    func unlock(with pin: String) -> PasscodeManager.VerifyResult {
        let result = PasscodeManager.shared.verify(pin)
        if result == .success { unlocked() }
        return result
    }

    private func unlocked() {
        isLocked = false
        lastActivity = Date()
    }

    private func startIdleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
    }

    private func checkIdle() {
        guard !isLocked, hasPasscode else { return }
        // Inatividade em primeiro plano: mínimo de 2 minutos para não atrapalhar a leitura.
        let limit = max(120, Double(autoLockSeconds) * 2)
        if Date().timeIntervalSince(lastActivity) > limit { lock() }
    }
}

/// Estado de navegação compartilhado.
@Observable
@MainActor
final class AppState {
    /// Os seis módulos da barra inferior.
    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case home, studies, calendar, training, contests, finance
        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: "Home"
            case .studies: "Estudos"
            case .calendar: "Calendário"
            case .training: "Treino"
            case .contests: "Editais"
            case .finance: "Financeiro"
            }
        }
        var icon: String {
            switch self {
            case .home: "house"
            case .studies: "book"
            case .calendar: "calendar"
            case .training: "dumbbell"
            case .contests: "building.columns"
            case .finance: "chart.pie"
            }
        }
        var selectedIcon: String {
            switch self {
            case .calendar: "calendar"
            default: icon + ".fill"
            }
        }
        /// Cor de identificação do módulo.
        var module: Theme.Module {
            switch self {
            case .home: .assistant
            case .studies: .study
            case .calendar: .agenda
            case .training: .fitness
            case .contests: .contest
            case .finance: .finance
            }
        }
    }

    var selectedTab: Tab = .home
    /// Assistente, adição rápida e ajustes abrem como folhas sobre qualquer módulo.
    var showAssistant = false
    var showQuickAdd = false
    var showSettings = false
    /// Texto enviado a partir da adição rápida para o assistente.
    var pendingAssistantText: String?

    func openAssistant(with text: String? = nil) {
        pendingAssistantText = text
        showAssistant = true
    }
}
