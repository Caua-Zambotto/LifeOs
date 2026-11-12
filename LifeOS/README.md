# LifeOS

Organizador pessoal para iPhone: agenda, faculdade, concursos, finanças, treinos, corpo, alimentação, metas, hábitos e documentos — com um assistente que entende frases em português.

- **Custo zero**: sem servidores, sem APIs pagas, sem assinaturas, sem bibliotecas de terceiros.
- **100% local**: SwiftData (SQLite) no próprio iPhone; funciona offline.
- **Privacidade**: senha + Face ID, cofre de documentos criptografado, backup criptografado, nenhum rastreador.
- **Exclusivo para iPhone**: seis módulos na barra inferior — **Home, Estudos, Calendário, Treino, Editais e Financeiro**. Assistente, adição rápida e Perfil/Ajustes abrem pela Home.
- **Migração**: dados da antiga versão web/PC podem ser importados em Ajustes › Backup (veja `../LifeOS-Web/README.md`).

> **Situação atual:** o código foi escrito em um PC com Windows, onde **não é possível compilar apps iOS**. Ele ainda **não foi compilado nem executado**. A primeira compilação no Mac provavelmente vai apontar alguns erros pequenos de digitação ou de tipos, que precisam ser corrigidos. Veja [PROJECT_STATUS.md](PROJECT_STATUS.md).

## Requisitos

| Item | Versão |
|---|---|
| Mac | macOS 14 (Sonoma) ou mais recente |
| Xcode | 16 ou mais recente (gratuito na App Store) |
| iPhone | iOS 17 ou mais recente |
| Conta Apple | Apple ID gratuito (não precisa do Apple Developer Program de US$ 99) |
| XcodeGen | gratuito: `brew install xcodegen` |

## Como compilar (no Mac)

```bash
brew install xcodegen
```

```bash
cd LifeOS
```

```bash
xcodegen generate
```

```bash
open LifeOS.xcodeproj
```

No Xcode:

1. Selecione o alvo **LifeOS** › *Signing & Capabilities* › em *Team*, escolha seu Apple ID (*Personal Team*).
2. Se o identificador `com.lifeos.app` estiver em uso, troque por um único, ex.: `com.seunome.lifeos`.
3. Conecte o iPhone por cabo, selecione-o como destino e pressione **⌘R**.
4. No iPhone: *Ajustes › Geral › VPN e Gerenciamento de Dispositivos* › confie no seu certificado de desenvolvedor.
5. Para rodar os testes: **⌘U** (simulador de iPhone).

**Sem XcodeGen:** crie no Xcode um projeto *iOS App* (SwiftUI, Storage: None) chamado LifeOS, apague os arquivos gerados, arraste a pasta `LifeOS/LifeOS` para o projeto e adicione ao Info.plist as chaves `NSFaceIDUsageDescription` e `NSCameraUsageDescription` (textos em `project.yml`).

### Limitação da conta gratuita

Apps instalados com Apple ID gratuito **expiram em 7 dias**. Os dados não são apagados: basta conectar ao Mac e rodar de novo (⌘R) para renovar. Para evitar isso, seria necessário o Apple Developer Program (pago) — não é obrigatório.

### E se eu não tiver Mac?

Não existe forma oficial e gratuita de compilar e instalar apps iOS a partir do Windows. Opções:

- Usar o Mac de um amigo, faculdade ou laboratório (só para compilar e instalar a cada 7 dias).
- Serviços de Mac na nuvem e CI (ex.: GitHub Actions com macOS) **conseguem compilar**, mas instalar no iPhone ainda exige assinatura; muitos desses serviços são pagos. Não foram configurados para respeitar o requisito de custo zero.

O produto final é um app iOS. Não existe APK (Android).

## Estrutura

```
LifeOS/
├── project.yml              # definição do projeto (XcodeGen)
├── LifeOS/
│   ├── App/                 # ponto de entrada, navegação, adição rápida
│   ├── Domain/              # modelos SwiftData e enums
│   ├── Core/
│   │   ├── Persistence/     # contêiner local, diretórios, proteção de arquivos
│   │   ├── Security/        # Keychain, PIN, Face ID, cofre, bloqueio automático
│   │   ├── Notifications/   # notificações locais
│   │   ├── Assistant/       # interpretação de linguagem natural (regras pt-BR)
│   │   ├── Services/        # finanças, estudos, receitas, Vision
│   │   ├── Backup/          # backup criptografado, JSON, CSV, PDF
│   │   └── Design/          # design system e formatadores
│   └── Features/            # telas por área
├── LifeOSTests/             # testes unitários (XCTest)
└── docs/                    # arquitetura, segurança, testes
```

## Documentação

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — arquitetura e decisões técnicas
- [docs/SECURITY.md](docs/SECURITY.md) — relatório de segurança e limitações
- [docs/TEST_REPORT.md](docs/TEST_REPORT.md) — relatório de testes e roteiro de testes manuais
- [PROJECT_STATUS.md](PROJECT_STATUS.md) — status, problemas e próximos passos

## Backup e troca de iPhone

Perfil › Backup e restauração › gere um backup com senha, salve no app Arquivos (iCloud Drive, computador ou pendrive). No novo iPhone, instale o LifeOS, faça a configuração inicial e restaure o arquivo com a mesma senha. **Sem a senha, o backup não pode ser aberto por ninguém.**
