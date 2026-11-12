# Arquitetura do LifeOS

## Tecnologias (todas nativas e gratuitas)

| Necessidade | Tecnologia |
|---|---|
| Interface | SwiftUI (iOS 17), Observation (`@Observable`) |
| Banco local | SwiftData (SQLite), `cloudKitDatabase: .none` |
| Gráficos | Swift Charts |
| Senha e chaves | Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Biometria | LocalAuthentication (Face ID / Touch ID) |
| Criptografia | CryptoKit (AES-256-GCM, SHA-256) + CommonCrypto (PBKDF2) |
| Notificações | UserNotifications (somente locais) |
| Fotos | PhotosPicker + UIImagePickerController (câmera) |
| Reconhecimento | Vision (`VNClassifyImageRequest`, `VNRecognizeTextRequest`) |
| Visualização de arquivos | QuickLook |
| Exportação | `ImageRenderer` (PDF), CSV próprio, `fileExporter` |

Nenhuma dependência externa (sem Swift Packages).

## Camadas

```
Features (SwiftUI)  ──usa──▶  Core/Services, Core/Assistant, Core/Backup
        │                              │
        └──── @Query / ModelContext ───┴──▶ Domain (modelos SwiftData) ──▶ SQLite local
```

- **Domain/Models.swift**: 30 modelos. Enums persistidos como `String`/`Int` brutos com propriedades computadas tipadas (mais seguro para migrações e predicados).
- **Core/Services**: regras de negócio puras e testáveis (`FinanceCalculator`, `StudyReview`, `RecipeEngine`) separadas das operações que gravam (`FinanceService`).
- **Features**: uma pasta por área; telas usam `@Query` para leitura reativa e `ModelContext` para gravação.

## Registros conectados (sem duplicidade)

Cada informação é gravada **uma vez** e referenciada:

- Prova/trabalho = `AgendaEvent` com `subject` (matéria) e/ou `contest` (concurso). Aparece na Agenda, no Meu dia e na página da matéria.
- Conta com vencimento = `RecurringEntry`. Aparece em Finanças, Agenda (ponto laranja) e Meu dia; ao pagar, gera a `FinanceTransaction`.
- Compra parcelada = N `FinanceTransaction` com o mesmo `installmentGroup`, ligadas ao `CreditCard`.
- Sessão de estudo = `StudySession` ligada à matéria da faculdade ou à matéria do concurso.
- Treino registrado a partir de uma divisão copia os exercícios e pode atualizar as cargas da divisão.
- Documentos do cofre podem ser vinculados a matéria ou concurso (edital).

## Assistente (linguagem natural)

```
texto ─▶ IntentInterpreter.interpret ─▶ Interpretation
                                         ├─ .draft(AssistantDraft)        → cartão de confirmação
                                         ├─ .needsInfo(draft, campo, pergunta) → pergunta simples
                                         └─ .notUnderstood(ajuda)
confirmação ─▶ AssistantExecutor.save ─▶ registros + ChatMessage(recordRefs) ─▶ "Desfazer"
```

- `RuleBasedInterpreter`: regras e expressões regulares em pt-BR. Normaliza acentos mantendo o alinhamento com o texto original (para preservar "Cálculo" com acento).
- `PTDateParser`: hoje/amanhã/ontem, "dia 15", "20/11", "15 de dezembro", "próxima quinta", "segunda que vem", "às 19h", "7 da noite", "meio-dia". Verbos no passado resolvem datas ambíguas para trás.
- **Nunca inventa**: sem valor/data, pergunta. Toda gravação exige confirmação.
- **Extensão futura**: o protocolo `IntentInterpreter` permite plugar um modelo de linguagem local (Core ML ou framework de modelo on-device da Apple) sem mudar a interface.

## Finanças — planejamento semanal

```
disponível = saldo + receitas previstas no mês − contas pendentes no mês
             − parcelas de dívidas ainda não pagas no mês − faturas em aberto − meta de economia
cota semanal = (disponível + gasto desta semana) / semanas restantes no mês
```

Compras no cartão entram nos gráficos por categoria na data da compra, mas só reduzem o saldo quando a fatura é paga (evita contar duas vezes).

## Sincronização futura

Arquitetura preparada, não implementada:
- Todos os modelos têm `id: UUID` estável e `createdAt`.
- O formato de backup (DTOs Codable com IDs de relacionamento) já é um formato de intercâmbio completo.
- Sincronização via iCloud Drive (arquivo de backup) ou CloudKit privado exigiria apenas mudar `cloudKitDatabase` e revisar os modelos — sem servidor próprio.

## HealthKit

Não habilitado nesta versão (exige capability e revisão de privacidade). O modelo `BodyMeasurement` foi pensado para receber dados importados no futuro, mediante autorização.
