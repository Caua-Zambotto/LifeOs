# Relatório de segurança e privacidade

## O que foi implementado

| Controle | Implementação | Arquivo |
|---|---|---|
| Senha do app | PIN de 6 dígitos; PINs triviais rejeitados; hash PBKDF2-HMAC-SHA256 (210 mil iterações, salt aleatório de 16 bytes) no Keychain | `Core/Security/Security.swift` |
| Tentativas | Após 5 erros, bloqueio progressivo (30 s, 60 s… até 1 h), contador no Keychain | `PasscodeManager` |
| Face ID / Touch ID | `LocalAuthentication`, opcional, com senha como alternativa | `BiometricService` |
| Bloqueio automático | Ao voltar do segundo plano após o tempo escolhido e por inatividade em primeiro plano | `AppLockManager` |
| Tela no seletor de apps | Coberta quando o app não está ativo | `PrivacyShield` |
| Banco de dados | Sandbox + proteção de dados do iOS (`completeUntilFirstUserAuthentication`) | `Persistence.swift` |
| Cofre de documentos | Cada arquivo criptografado com AES-256-GCM; chave aleatória de 256 bits no Keychain (`WhenUnlockedThisDeviceOnly`); arquivos com proteção `complete` | `VaultStorage` |
| Documentos sensíveis | Exigem Face ID/senha para abrir ou exportar | `DocumentRow`, `AuthGateView` |
| Arquivos temporários | Cópias descriptografadas em pasta temporária com proteção `complete`, apagadas ao ir para segundo plano e na abertura | `AppPaths.clearTemp` |
| Backup | AES-256-GCM; chave por PBKDF2 (310 mil iterações) a partir da senha do backup; cabeçalho autenticado (AAD); SHA-256 do conteúdo conferido; o app verifica o arquivo logo após gerá-lo | `BackupService` |
| Restauração | Arquivo verificado (senha + integridade) antes de qualquer alteração; confirmação explícita | `BackupView` |
| Logs | `SafeLog` só aceita mensagens fixas (`StaticString`): impossível registrar valores, textos ou nomes de arquivos | `SafeLog` |
| Rede | Nenhuma chamada de rede. Única exceção: abrir o link oficial de concurso cadastrado pelo usuário (apenas `https://`), no Safari | `ContestDetailView` |
| Permissões | Somente Face ID e câmera (quando usada). Notificações pedidas no onboarding. Galeria via PhotosPicker (não exige permissão) | `project.yml` |
| Entradas | Limites de tamanho de textos, faixas válidas para valores (peso 20–400 kg etc.), arquivos até 50 MB, nomes de arquivos sanitizados (sem path traversal), CSV protegido contra injeção de fórmulas | vários |
| Notificações | Não exibem valores financeiros na tela de bloqueio | `NotificationScheduler` |
| Reinstalação | Itens antigos do Keychain são apagados em uma instalação nova | `AppLockManager.bootstrap` |
| Exclusão total | Requer autenticação + digitar "EXCLUIR"; apaga banco, cofre, chaves, preferências e notificações | `SecurityPrivacyView` |
| Cartões | Só apelido, limite e datas. O app orienta a nunca guardar número/CVV/senha | `CardEditor` |

## Limitações reais (o LifeOS não é inviolável)

1. **O banco de dados não é criptografado com a senha do app.** Ele depende da criptografia do iOS (ativa quando o iPhone tem código de bloqueio). A senha do LifeOS protege o acesso pela interface. Quem tiver o iPhone desbloqueado e ferramentas forenses, ou um aparelho com jailbreak, pode ler o banco.
2. **Classe de proteção do banco**: foi usada `completeUntilFirstUserAuthentication` (padrão recomendado pela Apple para SQLite) para evitar corrupção quando o iPhone bloqueia com o app aberto. Os documentos usam a classe mais forte (`complete`) e criptografia própria.
3. **Chave do cofre presa ao aparelho**: a chave não migra para outro iPhone (nem via backup do iCloud do aparelho). Para trocar de iPhone, use o **backup do LifeOS**, que inclui os documentos.
4. **Senha do backup**: se for esquecida, o backup é irrecuperável. Isso é intencional.
5. **Backup de dispositivo do iOS (iCloud/computador)**: o banco do LifeOS entra nesses backups (protegido pela criptografia da Apple). Ao restaurar o iPhone por esse caminho, o app exigirá criar uma nova senha e os documentos do cofre não poderão ser abertos (a chave não é restaurada).
6. **Força do PIN**: 6 dígitos = 1 milhão de combinações. O bloqueio progressivo dificulta tentativas pela interface, mas não protege contra ataques fora do app.
7. **Exportação JSON** é aberta (sem criptografia) — o app avisa.
8. **Arquivos exportados/compartilhados** saem do controle do LifeOS.
9. **Não há auditoria externa** do código.

## Recomendações ao usuário

- Mantenha código de bloqueio forte no iPhone e o iOS atualizado.
- Faça backup criptografado com frequência e guarde a senha em um gerenciador de senhas.
- Marque como "sensível" documentos pessoais (RG, comprovantes).
