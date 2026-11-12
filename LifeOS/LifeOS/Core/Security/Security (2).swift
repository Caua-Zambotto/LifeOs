import Foundation
import CryptoKit
import CommonCrypto
import Security
import LocalAuthentication
import os

// MARK: - Log seguro

/// Nunca registra valores, textos do usuário, dados financeiros ou nomes de documentos.
/// Apenas mensagens fixas descrevendo eventos técnicos.
enum SafeLog {
    private static let logger = Logger(subsystem: "com.lifeos.app", category: "app")
    static func info(_ message: StaticString) { logger.info("\(message.description, privacy: .public)") }
    static func error(_ message: StaticString) { logger.error("\(message.description, privacy: .public)") }
}

// MARK: - Keychain

enum KeychainService {
    private static let service = "com.lifeos.secure"

    @discardableResult
    static func save(_ data: Data, for key: String) -> Bool {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // Disponível só com o aparelho desbloqueado e nunca migra para outro aparelho.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveString(_ value: String, for key: String) { save(Data(value.utf8), for: key) }
    static func readString(_ key: String) -> String? { read(key).flatMap { String(data: $0, encoding: .utf8) } }
}

// MARK: - Criptografia

enum CryptoError: Error, LocalizedError {
    case keyDerivationFailed, sealFailed, invalidData, wrongPasswordOrCorrupted, keychainFailure
    var errorDescription: String? {
        switch self {
        case .keyDerivationFailed: "Falha ao derivar a chave."
        case .sealFailed: "Falha ao criptografar."
        case .invalidData: "Arquivo inválido ou corrompido."
        case .wrongPasswordOrCorrupted: "Senha incorreta ou arquivo corrompido."
        case .keychainFailure: "Não foi possível acessar o Keychain."
        }
    }
}

enum CryptoService {
    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "Gerador aleatório indisponível")
        return data
    }

    /// PBKDF2-HMAC-SHA256.
    static func pbkdf2(password: String, salt: Data, rounds: Int, length: Int = 32) throws -> Data {
        var derived = Data(count: length)
        let passwordLength = password.utf8.count
        let status: Int32 = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password, passwordLength,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(rounds),
                    derivedPtr.bindMemory(to: UInt8.self).baseAddress, length
                )
            }
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return derived
    }

    /// AES-256-GCM (confidencialidade + integridade). Retorna nonce|ciphertext|tag.
    static func encrypt(_ data: Data, key: SymmetricKey, aad: Data? = nil) throws -> Data {
        let box: AES.GCM.SealedBox
        if let aad { box = try AES.GCM.seal(data, using: key, authenticating: aad) }
        else { box = try AES.GCM.seal(data, using: key) }
        guard let combined = box.combined else { throw CryptoError.sealFailed }
        return combined
    }

    static func decrypt(_ data: Data, key: SymmetricKey, aad: Data? = nil) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            if let aad { return try AES.GCM.open(box, using: key, authenticating: aad) }
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.wrongPasswordOrCorrupted
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[a.startIndex + i] ^ b[b.startIndex + i] }
        return diff == 0
    }
}

// MARK: - Senha do app (PIN)

final class PasscodeManager {
    static let shared = PasscodeManager()

    private let kSalt = "passcode.salt"
    private let kHash = "passcode.hash"
    private let kFails = "passcode.fails"
    private let kLockUntil = "passcode.lockUntil"
    private let rounds = 210_000
    static let length = 6

    var hasPasscode: Bool { KeychainService.read(kHash) != nil }

    enum VerifyResult: Equatable {
        case success
        case failure(attemptsBeforeLockout: Int)
        case lockedOut(until: Date)
    }

    func set(_ pin: String) throws {
        guard PasscodeManager.isValidFormat(pin) else { throw CryptoError.invalidData }
        let salt = CryptoService.randomBytes(16)
        let hash = try CryptoService.pbkdf2(password: pin, salt: salt, rounds: rounds)
        guard KeychainService.save(salt, for: kSalt), KeychainService.save(hash, for: kHash) else {
            throw CryptoError.keychainFailure
        }
        resetFailures()
    }

    func verify(_ pin: String) -> VerifyResult {
        if let until = lockedUntil, until > Date() { return .lockedOut(until: until) }
        guard let salt = KeychainService.read(kSalt), let stored = KeychainService.read(kHash),
              let candidate = try? CryptoService.pbkdf2(password: pin, salt: salt, rounds: rounds) else {
            return .failure(attemptsBeforeLockout: 0)
        }
        if CryptoService.constantTimeEquals(candidate, stored) {
            resetFailures()
            return .success
        }
        let fails = failures + 1
        KeychainService.saveString(String(fails), for: kFails)
        if fails >= 5 {
            // Bloqueio progressivo: 30s, 60s, 120s... até 1h.
            let delay = min(3600, 30 * pow(2, Double(fails - 5)))
            let until = Date().addingTimeInterval(delay)
            KeychainService.saveString(String(until.timeIntervalSince1970), for: kLockUntil)
            return .lockedOut(until: until)
        }
        return .failure(attemptsBeforeLockout: 5 - fails)
    }

    func remove() {
        KeychainService.delete(kSalt)
        KeychainService.delete(kHash)
        resetFailures()
    }

    var lockedUntil: Date? {
        KeychainService.readString(kLockUntil).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    private var failures: Int { KeychainService.readString(kFails).flatMap(Int.init) ?? 0 }

    private func resetFailures() {
        KeychainService.delete(kFails)
        KeychainService.delete(kLockUntil)
    }

    static func isValidFormat(_ pin: String) -> Bool {
        pin.count == length && pin.allSatisfy(\.isNumber) && !isTrivial(pin)
    }

    /// Rejeita PINs óbvios (000000, 123456, 654321...).
    static func isTrivial(_ pin: String) -> Bool {
        let digits = pin.compactMap(\.wholeNumberValue)
        guard digits.count == length else { return true }
        if Set(digits).count == 1 { return true }
        let asc = zip(digits, digits.dropFirst()).allSatisfy { $1 == $0 + 1 }
        let desc = zip(digits, digits.dropFirst()).allSatisfy { $1 == $0 - 1 }
        return asc || desc
    }
}

// MARK: - Biometria

enum BiometricService {
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Biometria"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Usar senha do LifeOS"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        do { return try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) }
        catch { return false }
    }
}

// MARK: - Chave do cofre

enum VaultKey {
    private static let keyName = "vault.key"

    /// Chave AES-256 aleatória, guardada no Keychain (somente este aparelho).
    static func get() throws -> SymmetricKey {
        if let data = KeychainService.read(keyName) { return SymmetricKey(data: data) }
        let data = CryptoService.randomBytes(32)
        guard KeychainService.save(data, for: keyName) else { throw CryptoError.keychainFailure }
        return SymmetricKey(data: data)
    }
}

// MARK: - Armazenamento do cofre

enum VaultStorage {
    static func store(_ data: Data) throws -> String {
        let name = UUID().uuidString + ".lockbox"
        let sealed = try CryptoService.encrypt(data, key: try VaultKey.get())
        try sealed.write(to: AppPaths.vault.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }

    static func load(_ storedName: String) throws -> Data {
        let sealed = try Data(contentsOf: AppPaths.vault.appendingPathComponent(storedName))
        return try CryptoService.decrypt(sealed, key: try VaultKey.get())
    }

    static func delete(_ storedName: String) {
        guard !storedName.isEmpty else { return }
        try? FileManager.default.removeItem(at: AppPaths.vault.appendingPathComponent(storedName))
    }

    /// Cria uma cópia temporária descriptografada para visualizar/compartilhar.
    static func temporaryCopy(of doc: VaultDocument) throws -> URL {
        let data = try load(doc.storedFileName)
        let safeName = sanitizeFileName(doc.originalFileName.isEmpty ? doc.title : doc.originalFileName)
        let ext = doc.fileExtension.isEmpty ? "" : ".\(doc.fileExtension)"
        let base = safeName.hasSuffix(ext) ? safeName : safeName + ext
        let url = AppPaths.temp.appendingPathComponent(base)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func deleteAllFiles() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: AppPaths.vault, includingPropertiesForKeys: nil) {
            files.forEach { try? fm.removeItem(at: $0) }
        }
        AppPaths.clearTemp()
    }

    /// Evita path traversal e caracteres problemáticos.
    static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            .replacingOccurrences(of: "..", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "arquivo" : String(cleaned.prefix(120))
    }
}
