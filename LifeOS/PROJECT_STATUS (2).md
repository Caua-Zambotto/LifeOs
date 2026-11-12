# PROJECT_STATUS — LifeOS (iPhone)

_Atualizado em 12/11/2026_

> **Pausado (12/11/2026).** Por decisão do usuário, a versão em uso é o app web com sincronização em `../LifeOS-Web/` (PC + celular, mesmos dados). Este projeto nativo fica guardado para o futuro.

## Decisão anterior

O LifeOS é **exclusivo para iPhone** (Swift + SwiftUI + SwiftData, iOS 17+). A versão web/PC (`../LifeOS-Web/`) foi **descontinuada**: não recebe mais funcionalidades e serve apenas para exportar os dados já cadastrados nela (backup) e importá-los no iPhone.

## Estrutura (6 módulos na barra inferior)

| Módulo | Arquivo principal | Conteúdo |
|---|---|---|
| **Home** | `Features/Home/HomeView.swift` | Saudação, hoje, indicadores (estudo, faculdade, editais, treino), próximo treino, resumo financeiro do mês, contas, próximas atividades, metas e hábitos, produtividade. Cada card abre o módulo. Personalizável. |
| **Estudos** | `Features/Studies/StudiesView.swift` | Matérias e conteúdos, avaliações (provas/trabalhos/entregas), revisões espaçadas, horas e histórico com gráficos, meta semanal. |
| **Calendário** | `Features/Agenda/AgendaView.swift` | Mês/semana/dia; eventos + contas (Financeiro) + treinos programados (Treino) + datas de concursos (Editais); filtro por módulo; notificações locais. |
| **Treino** | `Features/Health/FitnessViews.swift`, `Features/Training/LiveWorkoutView.swift` | Fichas, **treino ao vivo** (séries marcáveis, carga/reps com botões grandes, cronômetro de descanso, tela sempre acesa), histórico, evolução de carga, corpo, alimentação, meta semanal. |
| **Editais** | `Features/Study/ContestsView.swift` | Vários concursos, % do edital, datas importantes, disciplinas e conteúdos, horas, revisões, questões, simulados, PDF do edital. |
| **Financeiro** | `Features/Finance/FinanceView.swift` | Saldo, quanto posso gastar na semana, contas a vencer com "Pagar", resumo por mês, para onde foi o dinheiro, cartões, faturas, parcelas, dívidas, metas, gráficos, histórico. |

Assistente (linguagem natural), adição rápida e **Perfil e ajustes** (metas e hábitos, documentos, relatórios, alimentação, segurança, backup, notificações) abrem pela Home.

## Status

| Item | Status |
|---|---|
| Código das mudanças | ✅ escrito (43 arquivos Swift) |
| Balanceamento de chaves/parênteses | ✅ verificado automaticamente |
| Formato de importação da versão web | ✅ validado no navegador contra um backup real (chave, AAD, gzip, SHA-256, datas, dias da semana) |
| Compilação no Xcode | ❌ **não executada** — este computador é Windows, sem Xcode |
| Testes unitários (XCTest, inclui 4 novos de importação) | ❌ escritos, não executados |
| Testes no iPhone real | ❌ pendente |

## Dados existentes

- Nenhum modelo foi removido. Os novos campos (`weeklyStudyGoalMinutes`, `weeklyWorkoutGoal`) têm valor padrão → migração automática do SwiftData.
- Backups antigos do iPhone continuam compatíveis (campos novos opcionais no backup).
- Dados da versão web: exportar na web (Perfil › Backup › Gerar backup) e importar no iPhone (Ajustes › Backup › Escolher arquivo de backup).

## Problemas conhecidos / riscos

1. Não compilado: espere alguns erros pequenos de compilação na primeira vez (tipos, inferência em views longas).
2. A barra inferior é própria (o TabView do iOS limita a 5 abas visíveis); ela sobe junto com o teclado.
3. Requer Xcode 16+ (iOS 17+).

## Próximas tarefas

1. Em um Mac: `cd LifeOS && xcodegen generate && open LifeOS.xcodeproj`, compilar (⌘B) e corrigir erros.
2. Rodar os testes (⌘U).
3. Instalar no iPhone, importar o backup da versão web e conferir os dados.
4. Roteiro manual em `docs/TEST_REPORT.md`.
5. Depois de migrar os dados, a pasta `LifeOS-Web` pode ser apagada.
