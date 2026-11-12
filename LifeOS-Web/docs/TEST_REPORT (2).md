# Relatório de testes — LifeOS Web

Data: 12/11/2026 · Navegador: Chromium (painel do Claude Code) · Windows 11

## Testes automatizados — 52/52 aprovados

`tests.html` (roda no navegador, não altera dados reais):

- **Assistente (23):** gasto, valor com R$ e milhar, ontem, cartão parcelado em 3x, prova na próxima quinta às 19h, prova com matéria existente, conta recorrente, peso, medidas, treinos, estudar/revisar amanhã, compras de mercado, quantidades ("uma dúzia", "2 kg", "1 litro"), sessão de estudo 1h30, salário, pergunta de valor/data e complemento, frase não entendida, hábito, lembrete, consulta.
- **Datas (9):** amanhã às 8h, "dia 5" já passado → mês seguinte, verbos no passado, dd/mm(/aaaa), dias da semana, "15 de dezembro às 7 da noite", 31/02 rejeitado, sem data, hora já passada → amanhã.
- **Números/categorias (3)**, **criptografia (3, incluindo vetor público PBKDF2)**, **finanças (5)**, **estudos/hábitos/receitas (5)**, **gravar e desfazer (3)**, **backup cifrado (1)**.

## Testes na interface (feitos no navegador)

| Item | Resultado |
|---|---|
| Criar senha e entrar | ✅ |
| Assistente: prova, gasto, conta, peso, treino, compras, pergunta "Qual foi o valor?" → "50" | ✅ registros criados nas áreas certas |
| Prova aparece na Agenda, no Meu dia e na matéria (sem duplicar) | ✅ |
| Formulário de despesa digitado manualmente (R$ 42,90) | ✅ |
| Cartão com compra em 6x → 6 parcelas, fatura em aberto correta | ✅ |
| Documento guardado e conferido no IndexedDB: **conteúdo não aparece em texto** | ✅ |
| Transações no IndexedDB: **não aparecem em texto** | ✅ |
| Backup cifrado com documentos → restauração → documento legível | ✅ |
| Bloquear → senha errada ("4 tentativas") → senha certa | ✅ |
| Recarregar a página → dados persistem (após desbloquear) | ✅ |
| As 22 telas abrem sem erro; 10 formulários abrem sem erro; console sem erros | ✅ |
| Layout celular (375 px) e computador (1280 px, barra lateral), modo claro e escuro | ✅ |
| Service worker ativo, 29 arquivos em cache (offline) | ✅ |
| Servidor local PowerShell: tipos MIME corretos, bloqueia `..` e `.ps1` | ✅ |

## Corrigido durante os testes

- "Ainda pode gastar" aparecia em verde com saldo negativo → agora mostra "Acima do planejado".
- Formulário manual de despesa agora sugere a categoria pela descrição.

## Não testado

- Instalação real no Android/iPhone (precisa do app publicado em HTTPS).
- Notificações reais (a permissão estava bloqueada no navegador de teste).
- Firefox e Safari (testado só em Chromium).
- Uso prolongado com muitos dados (desempenho com milhares de registros).
