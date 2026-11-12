import SwiftUI
import SwiftData

/// Teclado numérico de PIN reutilizável.
struct PinPad: View {
    @Binding var pin: String
    var length = PasscodeManager.length
    var biometricAction: (() -> Void)? = nil
    var onComplete: (String) -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "bio", "0", "del"]

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 16) {
                ForEach(0..<length, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count ? Color.primary : Color.primary.opacity(0.15))
                        .frame(width: 14, height: 14)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 18), count: 3), spacing: 16) {
                ForEach(keys, id: \.self) { key in
                    keyView(key)
                }
            }
        }
    }

    @ViewBuilder
    private func keyView(_ key: String) -> some View {
        switch key {
        case "bio":
            if let biometricAction {
                Button(action: biometricAction) {
                    Image(systemName: "faceid").font(.title)
                        .frame(width: 76, height: 76)
                }
                .accessibilityLabel("Desbloquear com \(BiometricService.biometryName)")
            } else { Color.clear.frame(width: 76, height: 76) }
        case "del":
            Button {
                if !pin.isEmpty { pin.removeLast() }
            } label: {
                Image(systemName: "delete.left").font(.title2).frame(width: 76, height: 76)
            }
            .accessibilityLabel("Apagar")
        default:
            Button {
                guard pin.count < length else { return }
                pin.append(key)
                if pin.count == length { onComplete(pin) }
            } label: {
                Text(key).font(.system(size: 30, weight: .medium, design: .rounded))
                    .frame(width: 76, height: 76)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
        }
    }
}

struct LockScreenView: View {
    @Environment(AppLockManager.self) private var lock
    @State private var pin = ""
    @State private var message = "Digite sua senha"
    @State private var shake = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Module.assistant.gradient)
            VStack(spacing: 6) {
                Text("LifeOS bloqueado").font(.title2.bold())
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            PinPad(pin: $pin, biometricAction: lock.biometricsEnabled ? { Task { await lock.unlockWithBiometrics() } } : nil) { value in
                verify(value)
            }
            .offset(x: shake ? -10 : 0)
            .animation(shake ? .default.repeatCount(3, autoreverses: true).speed(4) : .default, value: shake)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .task {
            if let until = PasscodeManager.shared.lockedUntil, until > Date() {
                message = "Muitas tentativas. Tente após \(Fmt.time(until))."
            } else {
                await lock.unlockWithBiometrics()
            }
        }
    }

    private func verify(_ value: String) {
        switch lock.unlock(with: value) {
        case .success:
            pin = ""
        case .failure(let remaining):
            pin = ""
            message = remaining > 0 ? "Senha incorreta. \(remaining) tentativa(s) antes do bloqueio temporário." : "Senha incorreta."
            shake.toggle()
        case .lockedOut(let until):
            pin = ""
            message = "Muitas tentativas. Tente novamente após \(Fmt.time(until))."
            shake.toggle()
        }
    }
}

/// Criação/alteração do PIN (6 dígitos, digitado duas vezes).
struct PasscodeSetupView: View {
    var mandatory = false
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLockManager.self) private var lock
    @State private var pin = ""
    @State private var first: String?
    @State private var message = "Crie uma senha de 6 dígitos"

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "key.fill").font(.system(size: 40)).foregroundStyle(Theme.Module.security.gradient)
            VStack(spacing: 6) {
                Text(first == nil ? "Nova senha" : "Confirme a senha").font(.title2.bold())
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if mandatory {
                    Text("Uma senha é obrigatória para proteger seus dados neste aparelho.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 4)
                }
            }
            PinPad(pin: $pin) { value in handle(value) }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }

    private func handle(_ value: String) {
        if first == nil {
            guard !PasscodeManager.isTrivial(value) else {
                message = "Senha muito simples. Evite sequências e números repetidos."
                pin = ""
                return
            }
            first = value
            pin = ""
            message = "Digite novamente para confirmar"
        } else if value == first {
            do {
                try PasscodeManager.shared.set(value)
                lock.passcodeChanged()
                onDone()
                if !mandatory { dismiss() }
            } catch {
                message = "Não foi possível salvar a senha. Tente novamente."
                first = nil; pin = ""
            }
        } else {
            message = "As senhas não coincidem. Comece de novo."
            first = nil
            pin = ""
        }
    }
}

/// Pede autenticação antes de ações sensíveis (abrir documento sensível, apagar dados...).
struct AuthGateView: View {
    let reason: String
    var onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLockManager.self) private var lock
    @State private var pin = ""
    @State private var message = "Confirme sua senha"

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(reason).font(.headline).multilineTextAlignment(.center)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                PinPad(pin: $pin, biometricAction: lock.biometricsEnabled ? { Task { await biometric() } } : nil) { value in
                    switch PasscodeManager.shared.verify(value) {
                    case .success: succeed()
                    case .failure: message = "Senha incorreta"; pin = ""
                    case .lockedOut(let until): message = "Bloqueado até \(Fmt.time(until))"; pin = ""
                    }
                }
            }
            .padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .task { await biometric() }
        }
    }

    private func biometric() async {
        guard lock.biometricsEnabled else { return }
        if await BiometricService.authenticate(reason: reason) { succeed() }
    }

    private func succeed() {
        dismiss()
        onSuccess()
    }
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppLockManager.self) private var lock
    @AppStorage("onboarding.done") private var onboardingDone = false
    @State private var step = 0
    @State private var name = ""

    var body: some View {
        VStack {
            switch step {
            case 0: welcome
            case 1: nameStep
            case 2: PasscodeSetupView(mandatory: true) { step = 3 }
            default: biometricStep
            }
        }
        .animation(.easeInOut, value: step)
        .screenBackground()
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(Theme.Module.assistant.gradient)
            Text("LifeOS").font(.system(size: 42, weight: .bold, design: .rounded))
            Text("Agenda, estudos, finanças, treinos, alimentação e metas em um só lugar.")
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                feature("iphone", "Tudo fica no seu iPhone", "Sem servidores, sem contas, sem anúncios.")
                feature("lock.fill", "Protegido", "Senha, Face ID e criptografia de documentos e backups.")
                feature("text.bubble.fill", "Registre conversando", "\"Gastei 35 reais no almoço\" e pronto.")
            }
            .card()
            Spacer()
            Button("Começar") { step = 1 }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Como você quer ser chamado?").font(.title.bold())
            TextField("Seu nome", text: $name)
                .textContentType(.givenName)
                .font(.title3)
                .padding()
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            Text("Usado apenas na saudação da tela inicial.").font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button("Continuar") {
                context.profile().name = String(name.trimmed.prefix(40))
                context.saveQuietly()
                step = 2
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
    }

    private var biometricStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "faceid").font(.system(size: 64)).foregroundStyle(Theme.Module.security.gradient)
            Text("Usar \(BiometricService.biometryName)?").font(.title.bold())
            Text("Desbloqueie o LifeOS com rapidez. A senha continua funcionando como alternativa.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            if BiometricService.isAvailable {
                Button("Ativar \(BiometricService.biometryName)") {
                    Task {
                        if await BiometricService.authenticate(reason: "Ativar desbloqueio por biometria") {
                            lock.setBiometrics(true)
                        }
                        await finish()
                    }
                }
                .buttonStyle(PrimaryButtonStyle(module: .security))
            }
            Button("Agora não") { Task { await finish() } }.padding(.bottom)
        }
        .padding(24)
    }

    private func finish() async {
        _ = await NotificationService.shared.requestAuthorization()
        lock.isLocked = false
        onboardingDone = true
    }

    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemName: icon, tint: Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
