# PROJECT_STATUS — LifeOS Web (PWA)

_Atualizado em 12/11/2026_

## Decisão

Por pedido do usuário: primeiro Windows, depois celular via PWA. Foi feito **um único app web (PWA)** que serve para os dois: no Windows ele é instalado pelo Edge como aplicativo; no celular, pelo navegador a partir de um endereço HTTPS. A versão nativa iOS (Swift) continua em `../LifeOS/`, pausada.

## Status

| Fase | Status |
|---|---|
| 1 — Estrutura, navegação, visual, banco local, proteção | ✅ pronto e testado |
| 2 — Meu dia e assistente | ✅ pronto e testado |
| 3 — Agenda, faculdade, provas, trabalhos, concursos, editais, revisões | ✅ pronto (telas e formulários abrem; fluxos principais testados) |
| 4 — Finanças | ✅ pronto e testado |
| 5 — Saúde (treinos, corpo, alimentação, receitas) | ✅ pronto (foto só como referência; sem reconhecimento automático na web) |
| 6 — Metas e hábitos | ✅ pronto |
| 7 — Documentos, backup, restauração, criptografia | ✅ pronto e testado |
| 9 — Reorganização em 6 módulos (Home, Estudos, Calendário, Treino, Editais, Financeiro) — v1.2.0 | ✅ pronto; testado no navegador em largura de celular e de desktop |
| 8 — Testes | ✅ 60/60 automatizados + roteiro na interface ([docs/TEST_REPORT.md](docs/TEST_REPORT.md)) |
| Sincronização PC ↔ celular (Supabase) | ⏸ código pronto mas **desativado** — o usuário optou por não usar Supabase |
| Windows | ✅ `Iniciar LifeOS.bat` + instalar como app no Edge |
| Celular | ⏳ falta publicar em HTTPS (Netlify) — ver [PASSO-A-PASSO.md](PASSO-A-PASSO.md) |

## 6 módulos (v1.2.0)

- **Barra inferior fixa** com Home, Estudos, Calendário, Treino, Editais e Financeiro (no computador vira barra lateral, com Adicionar, Assistente, Perfil e ajustes e Bloquear).
- **Home**: saudação, alertas, hoje, indicadores (estudo na semana, faculdade, editais, treinos), próximo treino, mês financeiro, contas a vencer, próximas atividades, metas/hábitos e produtividade. Seções podem ser escondidas/reordenadas (Personalizar Home).
- **Estudos**: matérias, avaliações, revisões, histórico, meta semanal de horas, registro de estudo.
- **Calendário**: mês/semana/dia, filtro por módulo; mostra eventos, contas, treinos da ficha e datas de concursos.
- **Treino**: fichas, meta semanal, **treino ao vivo** (séries marcáveis, carga/reps com botões, cronômetro de descanso, tela acesa), histórico, evolução, corpo e alimentação.
- **Editais**: visão geral (% médio, horas da semana, próxima prova), % do edital por concurso, datas importantes, revisões do edital, matérias, simulados, PDF.
- **Financeiro**: mês navegável com entradas/saídas/resultado e comparação com o mês anterior, contas a vencer com "Pagar", ranking "Para onde foi o dinheiro", planejamento semanal e demais abas.
- Faculdade, Corpo e Alimentação continuam existindo, dentro de Estudos e Treino. Nenhum dado existente é apagado ou migrado.

## Problemas conhecidos

- Notificações só disparam com o app aberto ou em segundo plano recente (limite da web sem servidor de push).
- Sem Face ID / Windows Hello (desbloqueio por senha).
- Sincronização: se o mesmo registro for editado em dois aparelhos sem internet, vale a última edição. Supabase gratuito pausa após 7 dias sem uso (reativar no painel).
- Não testado em Firefox/Safari nem em celular real.

## Próximas tarefas

1. Escolher como levar os dados entre PC e celular sem Supabase (backup cifrado manual, pasta do OneDrive/Drive, ou um aparelho só).
2. Testar no celular real (Android e/ou iPhone) e ajustar.
3. Opcional: reconhecimento de alimentos por foto com modelo local gratuito (ex.: TensorFlow.js/Tesseract.js, offline após baixar).
4. Opcional: Windows Hello / Face ID via WebAuthn.

## Comandos

Iniciar no Windows: dois cliques em `Iniciar LifeOS.bat`.

Rodar os testes: com o app aberto, acessar `http://localhost:8765/tests.html`.
