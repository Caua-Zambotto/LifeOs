# Relatório de testes

## Situação honesta

| Etapa | Status |
|---|---|
| Compilação | **Não executada** — o ambiente de desenvolvimento é Windows, sem Swift/Xcode |
| Testes unitários (XCTest) | **Escritos, não executados** — 52 casos em `LifeOSTests/` |
| Testes manuais no iPhone | **Não executados** — roteiro abaixo |
| Revisão estática | Feita manualmente: os casos do interpretador e do parser de datas foram rastreados à mão contra as expressões regulares; dois bugs foram encontrados e corrigidos (quantidade "uma dúzia" e unidades coladas ao nome, ex.: "2 laranjas") |

Nenhuma funcionalidade deve ser considerada **testada** até rodar `⌘U` no Xcode e o roteiro manual.

## Testes unitários incluídos

| Arquivo | Cobre |
|---|---|
| `InterpreterTests.swift` | 20 frases (gastos, receita, conta, prova, estudo, peso, treino, mercado, hábito, parcelamento), perguntas de complemento, frase não entendida |
| `InterpreterTests.swift` › `DateParserTests` | amanhã/hora, "dia N" no passado/futuro, dd/mm(/aaaa), dias da semana, mês por extenso, data inválida (31/02), hora já passada |
| `NumberParsingTests` | "1.234,56", "77,5", "1.200", "R$ 35,90", categorias |
| `CoreTests.swift` › `CryptoTests` | PBKDF2 (vetor público), AES-GCM ida e volta, chave/AAD errados, comparação em tempo constante, PINs triviais, nomes de arquivo, CSV |
| `FinanceTests` | mês da fatura, parcelas somando o total exato, saldo x compras no cartão, planejamento semanal, pagamento de conta recorrente |
| `StudyAndRecipeTests` | revisão espaçada, média ponderada, sugestão de receitas, dicionário de alimentos |
| `BackupTests` | backup criptografado → restauração preservando relacionamentos, senha errada, arquivo adulterado, senha fraca, assistente salvar/desfazer sem duplicar |

Data de referência dos testes de linguagem: **quinta-feira, 12/11/2026, 10:00**.

## Como rodar

No Mac: abra o projeto e pressione **⌘U** (com um simulador de iPhone selecionado), ou:

```bash
xcodebuild test -project LifeOS.xcodeproj -scheme LifeOS -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Roteiro de testes manuais (iPhone real)

**Persistência**
- [ ] Criar registros em todas as áreas, fechar o app pelo seletor, reabrir: tudo continua.
- [ ] Reiniciar o iPhone e abrir: tudo continua.

**Segurança**
- [ ] Onboarding exige PIN; PIN "123456" é recusado.
- [ ] Ir para segundo plano por mais que o tempo configurado → app pede senha.
- [ ] Seletor de apps mostra a tela de proteção, não os dados.
- [ ] 5 PINs errados → bloqueio temporário.
- [ ] Face ID desbloqueia; cancelar o Face ID permite usar o PIN.
- [ ] Documento marcado como sensível pede autenticação.

**Assistente**
- [ ] "Gastei 35 reais no almoço" → confirmar → aparece em Finanças e nos gastos da semana.
- [ ] "Tenho prova de cálculo na próxima quinta às 19h" → aparece na Agenda, no Meu dia e em Faculdade › Cálculo.
- [ ] "Gastei no mercado" → assistente pergunta o valor → responder "50".
- [ ] "Desfazer" remove o registro.

**Notificações**
- [ ] Perfil › Notificações › "Enviar notificação de teste" (com o app em segundo plano).
- [ ] Evento daqui a 20 minutos com aviso "15 min antes" dispara no modo avião.

**Backup**
- [ ] Gerar backup com senha → salvar no app Arquivos.
- [ ] Restaurar com senha errada → recusado sem alterar dados.
- [ ] Excluir todos os dados → restaurar o backup → registros e documentos voltam.

**Navegação (6 módulos)**
- [ ] Barra inferior: Home, Estudos, Calendário, Treino, Editais e Financeiro alternam sem perder a posição de rolagem.
- [ ] Home: botões +, engrenagem e "Registrar conversando" abrem adição rápida, ajustes e assistente.
- [ ] Cada card da Home abre o módulo correspondente; "Personalizar Home" reordena e oculta cards.
- [ ] Testar em iPhone pequeno (SE) e grande (Pro Max), modo claro e escuro, texto grande (Acessibilidade).

**Integração e atualização automática**
- [ ] Cadastrar uma prova em Estudos → aparece no Calendário (filtro Estudos) e na Home (Próximas atividades).
- [ ] Concluir um conteúdo em Editais → % do edital e indicador "Editais" da Home sobem.
- [ ] Registrar estudo → "Estudo na semana" da Home e a meta em Estudos atualizam.
- [ ] Ficha com dias da semana → aparece no Calendário (filtro Treino) e em "Próximo treino".
- [ ] Conta recorrente → aparece no Calendário (filtro Financeiro); "Pagar" gera a despesa e avança o vencimento.

**Treino ao vivo**
- [ ] Iniciar treino pela ficha → marcar série inicia o descanso; com a tela bloqueada chega o aviso "Descanso concluído".
- [ ] Ajustar carga/reps com − e +; adicionar exercício e série; Concluir → treino aparece no Histórico e as cargas da ficha atualizam.
- [ ] A tela não apaga durante o treino.

**Importação da versão web**
- [ ] Gerar backup na versão web → importar no iPhone com a senha → conferir eventos, matérias, finanças, treinos, hábitos e documentos.
- [ ] Senha errada é recusada sem alterar dados.

## Atualização de 12/11/2026 (reorganização iOS)

| Verificação | Resultado |
|---|---|
| Compilação Xcode | ❌ não executada (Windows, sem Xcode) |
| Balanceamento de chaves/parênteses nos 43 arquivos Swift | ✅ |
| Formato do backup web × importador Swift (PBKDF2, AES-GCM com AAD, gzip, SHA-256, datas ISO, dias da semana) | ✅ validado no navegador com um backup real |
| Novos testes XCTest de importação (gzip, detecção de formato, mapeamento de relações) | escritos, não executados |
