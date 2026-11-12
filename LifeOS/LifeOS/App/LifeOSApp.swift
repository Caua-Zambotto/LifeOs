import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {
    @State private var appState = AppState()
    @State private var lock = AppLockManager()
    private let container: ModelContainer?

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            SafeLog.error("Falha ao abrir o banco local")
            container = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
                    .environment(appState)
                    .environment(lock)
            } else {
                StoreErrorView()
            }
        }
    }
}

struct StoreErrorView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 44)).foregroundStyle(.orange)
            Text("Não foi possível abrir seus dados").font(.title3.bold())
            Text("O banco local não pôde ser carregado. Nenhum dado foi apagado. Reinicie o iPhone e abra o LifeOS novamente. Se o problema continuar, restaure um backup em Perfil › Backup após reinstalar.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var phase
    @AppStorage("onboarding.done") private var onboardingDone = false
    @AppStorage("appearance") private var appearance = "system"

    private var scheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    var body: some View {
        ZStack {
            if !onboardingDone {
                OnboardingView()
            } else if !lock.hasPasscode {
                // Ex.: dados restaurados em outro aparelho sem a senha no Keychain.
                PasscodeSetupView(mandatory: true) { }
            } else if lock.isLocked {
                LockScreenView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
            if phase != .active && onboardingDone {
                PrivacyShield()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lock.isLocked)
        .preferredColorScheme(scheme)
        .environment(\.locale, Fmt.locale)
        .onChange(of: phase) { _, newPhase in lock.handle(phase: newPhase) }
        .task {
            lock.bootstrap()
            DataSeeder.seedIfNeeded(context)
        }
        .simultaneousGesture(TapGesture().onEnded { lock.registerActivity() })
    }
}

/// Cobre a tela no seletor de apps para não expor dados.
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(Theme.Module.assistant.gradient)
                Text("LifeOS").font(.title2.bold())
            }
        }
    }
}
