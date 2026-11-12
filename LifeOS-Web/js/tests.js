// Testes automatizados executados no navegador (abrir tests.html).
import * as N from './nlp.js';
import * as D from './domain.js';
import * as C from './crypto.js';
import * as B from './backup.js';
import * as db from './store.js';
import { parseDecimal, fold } from './util.js';

const out = document.getElementById('out');
const results = [];
const tests = [];
const t = (name, fn) => tests.push([name, fn]);

function eq(a, b, msg = '') {
  const A = JSON.stringify(a), Bs = JSON.stringify(b);
  if (A !== Bs) throw new Error(`${msg} esperado ${Bs}, obtido ${A}`);
}
function ok(v, msg = 'esperado verdadeiro') { if (!v) throw new Error(msg); }
async function throws(fn, msg = 'esperava erro') { try { await fn(); } catch { return; } throw new Error(msg); }

// Quinta-feira, 12/11/2026, 10:00
const REF = new Date(2026, 10, 12, 10, 0);
const ymdhm = (d) => (d ? [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes()] : null);
const ymd = (d) => (d ? ymdhm(d).slice(0, 3) : null);
let ctx = { now: REF };
function draft(text) {
  const r = N.interpret(text, ctx);
  if (r.type !== 'draft') throw new Error(`esperava rascunho, obtido ${r.type} (${r.question || ''})`);
  return r.draft;
}
const reset = () => { ctx = { now: REF }; };

// ---------- Interpretador ----------
t('Gasto no almoço', () => { reset(); const d = draft('Gastei 35 reais no almoço'); eq(d.kind, 'expense'); eq(d.amount, 35); eq(d.financeCategory, 'alimentacao'); eq(d.title, 'Almoço'); });
t('Valor com R$ e milhar', () => { reset(); const d = draft('Paguei R$ 1.234,56 de aluguel'); eq(d.amount, 1234.56); eq(d.financeCategory, 'moradia'); });
t('Uber ontem', () => { reset(); const d = draft('gastei 25 reais de uber ontem'); eq(d.financeCategory, 'transporte'); eq(ymd(d.date), [2026, 11, 11]); });
t('Cartão parcelado', () => { ctx = { now: REF, cardNames: ['Nubank'] }; const d = draft('Comprei um tênis por 300 reais no cartão em 3x'); eq(d.kind, 'expense'); eq(d.amount, 300); eq(d.installments, 3); eq(d.cardName, 'Nubank'); eq(d.financeCategory, 'compras'); eq(d.title, 'Tênis'); });
t('Prova na próxima quinta', () => { reset(); const d = draft('Tenho prova de cálculo na próxima quinta às 19h'); eq(d.kind, 'event'); eq(d.eventCategory, 'prova'); eq(d.subjectName, 'Cálculo'); eq(d.subjectExists, false); eq(d.hasTime, true); eq(ymdhm(d.date), [2026, 11, 19, 19, 0]); eq(d.title, 'Prova de Cálculo'); });
t('Prova com matéria existente', () => { ctx = { now: REF, subjectNames: ['Eletrônica Digital'] }; const d = draft('Tenho prova de eletrônica digital dia 20 às 19h'); eq(d.subjectName, 'Eletrônica Digital'); eq(d.subjectExists, true); eq(ymdhm(d.date), [2026, 11, 20, 19, 0]); });
t('Conta de internet', () => { reset(); const d = draft('Minha conta de internet vence dia 15 e custa 120 reais'); eq(d.kind, 'bill'); eq(d.amount, 120); eq(d.title, 'Internet'); eq(d.financeCategory, 'internet'); eq(d.recurrence, 'mensal'); eq(ymd(d.date), [2026, 11, 15]); });
t('Peso', () => { reset(); const d = draft('Meu peso atual é 77,5 kg'); eq(d.kind, 'body'); eq(d.weight, 77.5); });
t('Medidas', () => { reset(); const d = draft('Minha cintura está com 82 cm'); eq(d.kind, 'body'); eq(d.measurements.waist, 82); });
t('Treino peito e tríceps', () => { reset(); const d = draft('Hoje fiz treino de peito e tríceps'); eq(d.kind, 'workout'); eq(d.muscleGroups, ['Peito', 'Tríceps']); eq(d.title, 'Peito e Tríceps'); });
t('Treinei pernas', () => { reset(); const d = draft('Hoje treinei pernas'); eq(d.kind, 'workout'); eq(d.muscleGroups, ['Pernas']); });
t('Estudar amanhã', () => { reset(); const d = draft('Preciso estudar segurança da informação amanhã'); eq(d.eventCategory, 'estudo'); eq(d.title, 'Estudar Segurança da informação'); eq(ymd(d.date), [2026, 11, 13]); eq(d.hasTime, false); });
t('Revisar redes', () => { reset(); const d = draft('Preciso revisar redes amanhã'); eq(d.eventCategory, 'estudo'); eq(d.title, 'Revisar Redes'); });
t('Compras de mercado', () => { reset(); const d = draft('Comprei ovos, arroz, frango e batata no mercado'); eq(d.kind, 'groceries'); eq(d.items.map((i) => i.name), ['Ovos', 'Arroz', 'Frango', 'Batata']); eq(d.amount, null); });
t('Itens com quantidades', () => { const it = N.splitItems('2 kg de frango, uma dúzia de ovos e 1 litro de leite, 2 laranjas'); eq(it.length, 4); eq(it[0], { name: 'Frango', quantity: 2, unit: 'kg' }); eq(it[1], { name: 'Ovos', quantity: 12, unit: 'un' }); eq(it[2].unit, 'L'); eq(it[3], { name: 'Laranjas', quantity: 2, unit: 'un' }); });
t('Sessão de estudo', () => { reset(); const d = draft('Estudei 1h30 de português'); eq(d.kind, 'studySession'); eq(d.minutes, 90); eq(d.subjectName, 'Português'); });
t('Receita (salário)', () => { reset(); const d = draft('Recebi 2500 reais de salário'); eq(d.kind, 'income'); eq(d.amount, 2500); eq(d.financeCategory, 'salario'); });
t('Pergunta o valor e completa', () => { reset(); const r = N.interpret('Gastei no mercado', ctx); eq(r.type, 'needsInfo'); eq(r.field, 'amount'); const c = N.complete(r.draft, r.field, '50', ctx); eq(c.type, 'draft'); eq(c.draft.amount, 50); });
t('Pergunta a data e completa', () => { reset(); const r = N.interpret('Tenho prova de física', ctx); eq(r.field, 'date'); const c = N.complete(r.draft, 'date', 'dia 20', ctx); eq(ymd(c.draft.date), [2026, 11, 20]); });
t('Frase não entendida', () => { reset(); eq(N.interpret('olá tudo bem', ctx).type, 'notUnderstood'); });
t('Marcar hábito', () => { ctx = { now: REF, habitNames: ['Meditar'] }; const d = draft('Hoje fiz meditar'); eq(d.kind, 'habitCheck'); eq(d.habitName, 'Meditar'); });
t('Lembrete', () => { reset(); const d = draft('Me lembre de pagar o aluguel amanhã às 9h'); eq(d.eventCategory, 'lembrete'); eq(ymdhm(d.date), [2026, 11, 13, 9, 0]); ok(d.title.startsWith('Pagar o aluguel'), d.title); });
t('Consulta no dentista', () => { reset(); const d = draft('Tenho dentista sexta às 14:30'); eq(d.eventCategory, 'consulta'); eq(ymdhm(d.date), [2026, 11, 13, 14, 30]); });

// ---------- Datas ----------
const pd = (s, past = false) => N.parseDate(new N.NText(s), past, REF);
t('Amanhã às 8h', () => eq(ymdhm(pd('amanhã às 8h').date), [2026, 11, 13, 8, 0]));
t('Dia já passado vai para o mês seguinte', () => eq(ymd(pd('dia 5').date), [2026, 12, 5]));
t('Dia no passado (verbos no passado)', () => eq(ymd(pd('dia 20', true).date), [2026, 10, 20]));
t('Data com barra', () => { eq(ymd(pd('20/11').date), [2026, 11, 20]); eq(ymdhm(pd('10/01/2027 14:30').date), [2027, 1, 10, 14, 30]); });
t('Dias da semana', () => { eq(ymd(pd('sexta').date), [2026, 11, 13]); eq(ymd(pd('segunda que vem').date), [2026, 11, 16]); eq(ymd(pd('na quinta').date), [2026, 11, 12]); eq(ymd(pd('próxima quinta').date), [2026, 11, 19]); });
t('Mês por extenso e período', () => eq(ymdhm(pd('15 de dezembro às 7 da noite').date), [2026, 12, 15, 19, 0]));
t('Data inválida rejeitada', () => eq(pd('31/02').date, null));
t('Sem data', () => eq(pd('comprar pão').date, null));
t('Hora já passada vai para amanhã', () => eq(ymdhm(pd('às 8h').date), [2026, 11, 13, 8, 0]));

// ---------- Números e categorias ----------
t('Números', () => { eq(N.parseNumber('1.234,56', true), 1234.56); eq(N.parseNumber('77,5', false), 77.5); eq(N.parseNumber('1.200', true), 1200); eq(N.parseNumber('77.5', false), 77.5); eq(parseDecimal('R$ 35,90'), 35.9); });
t('Categorias', () => { eq(N.guessExpense('uber pro trabalho'), 'transporte'); eq(N.guessExpense('netflix'), 'assinaturas'); eq(N.guessExpense('farmacia'), 'saude'); eq(N.guessExpense('coisa aleatoria'), 'outros'); eq(N.guessIncome('freela de design'), 'rendaExtra'); });
t('Fold mantém comprimento', () => { const s = 'Cálculo São João ação'; eq(fold(s).length, s.length); eq(fold(s), 'calculo sao joao acao'); });

// ---------- Criptografia ----------
t('PBKDF2 (vetor público)', async () => {
  const k = await C.pbkdf2Bits('password', C.enc.encode('salt'), 1);
  eq([...k].map((b) => b.toString(16).padStart(2, '0')).join(''), '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
});
t('AES-GCM ida e volta / chave errada', async () => {
  const k1 = await C.aesKeyFromRaw(C.randomBytes(32)); const k2 = await C.aesKeyFromRaw(C.randomBytes(32));
  const ct = await C.encryptBytes(k1, C.enc.encode('segredo'), C.enc.encode('aad'));
  eq(C.dec.decode(await C.decryptBytes(k1, ct, C.enc.encode('aad'))), 'segredo');
  await throws(() => C.decryptBytes(k2, ct, C.enc.encode('aad')));
  await throws(() => C.decryptBytes(k1, ct, C.enc.encode('outro')));
});
t('CSV contra injeção de fórmula', () => { eq(B.csvEscape('=SOMA(A1)'), "'=SOMA(A1)"); eq(B.csvEscape('a;b'), '"a;b"'); });

// ---------- Finanças (em memória) ----------
t('Mês da fatura', () => {
  eq(D.invoiceKey(D.invoiceMonth(new Date(2026, 10, 3), 5)), '2026-11');
  eq(D.invoiceKey(D.invoiceMonth(new Date(2026, 10, 10), 5)), '2026-12');
  eq(D.invoiceKey(D.invoiceMonth(new Date(2026, 11, 20), 5)), '2027-01');
});
t('Parcelas somam o total', () => {
  db.initMemory();
  const card = db.insert('cards', { name: 'C', limit: 1000, closingDay: 5, dueDay: 12 });
  const txs = D.addTransaction({ title: 'Notebook', amount: 1000, kind: 'despesa', category: 'compras', date: new Date(2026, 10, 1), cardId: card.id, installments: 3 });
  eq(txs.length, 3); eq(Math.round(txs.reduce((a, x) => a + x.amount, 0) * 100) / 100, 1000);
  eq(txs.map((x) => x.installmentNumber), [1, 2, 3]); eq(new Date(txs[2].date).getMonth(), 0);
});
t('Saldo ignora cartão até pagar a fatura', () => {
  db.initMemory();
  const card = db.insert('cards', { name: 'C', limit: 1000, closingDay: 5, dueDay: 12 });
  D.addTransaction({ title: 'Salário', amount: 3000, kind: 'receita', category: 'salario', date: new Date(2026, 10, 5) });
  D.addTransaction({ title: 'Mercado', amount: 200, kind: 'despesa', category: 'alimentacao', date: new Date(2026, 10, 6) });
  D.addTransaction({ title: 'Roupa', amount: 300, kind: 'despesa', category: 'compras', date: new Date(2026, 10, 7), cardId: card.id });
  const now = new Date(2026, 10, 20);
  eq(D.balance(100, new Date(2026, 10, 1), db.all('transactions'), now), 2900);
  eq(D.outstanding(card, now), 300);
  eq(D.spending(db.all('transactions'), { start: new Date(2026, 10, 1), end: now }), 500);
});
t('Planejamento semanal', () => {
  db.initMemory();
  db.setProfile({ initialBalance: 1000, balanceDate: new Date(2026, 10, 1).toISOString() });
  db.insert('recurring', { title: 'Internet', amount: 100, kind: 'despesa', category: 'internet', dueDate: new Date(2026, 10, 25).toISOString(), recurrence: 'mensal', isActive: true });
  const p = D.weeklyPlan(new Date(2026, 10, 16, 12));
  eq(p.available, 900); eq(p.weeksRemaining, 3); eq(p.weeklyAllowance, 300); eq(p.overBudget, false);
});
t('Pagar conta recorrente avança o vencimento', () => {
  db.initMemory();
  const r = db.insert('recurring', { title: 'Luz', amount: 150, kind: 'despesa', category: 'moradia', dueDate: new Date(2026, 10, 10).toISOString(), recurrence: 'mensal', isActive: true });
  D.settleRecurring(r, new Date(2026, 10, 9));
  eq(new Date(db.get('recurring', r.id).dueDate).getMonth(), 11); eq(db.all('transactions').length, 1);
});

// ---------- Estudos, hábitos, receitas ----------
t('Revisão espaçada', () => {
  db.initMemory();
  const tp = db.insert('topics', { title: 'Redes', status: 'naoIniciado' });
  D.setTopicStatus(tp, 'concluido', REF); eq(ymd(new Date(tp.nextReview)), [2026, 11, 13]);
  D.markReviewed(tp, REF); eq(ymd(new Date(tp.nextReview)), [2026, 11, 19]);
});
t('Média ponderada', () => eq(D.weightedAverage([{ value: 8, maxValue: 10, weight: 1 }, { value: 30, maxValue: 50, weight: 2 }]), (8 + 12) / 3));
t('Sequência de hábito', () => {
  const h = { weekdays: [], checkins: [new Date(2026, 10, 10), new Date(2026, 10, 11)].map((d) => d.toISOString()) };
  eq(D.habitStreak(h, REF), 2);
});
t('Sugestão de receitas', () => {
  const s = D.suggestRecipes(D.RECIPE_CATALOG, [{ name: 'Ovos', quantity: 6 }, { name: 'Tomate', quantity: 1 }, { name: 'Cebola', quantity: 1 }]);
  eq(s[0].recipe.id, 'cat:omelete-legumes'); eq(s[0].score, 1);
});
t('Nomes canônicos', () => { eq(D.canonical('Ovos'), 'ovo'); eq(D.canonical('Feijão'), 'feijao'); ok(D.hasIngredient('Sal', new Set())); });

// ---------- Assistente: salvar e desfazer ----------
t('Prova cria matéria e evento sem duplicar; desfazer remove', () => {
  db.initMemory();
  const r = N.interpret('Tenho prova de física dia 20 às 19h', { now: REF });
  const { refs } = D.saveDraft(r.draft);
  const s = db.all('subjects'); eq(s.length, 1); eq(s[0].name, 'Física');
  eq(db.all('events').filter((e) => e.subjectId === s[0].id).length, 1);
  D.undoRefs(refs); eq(db.all('events').length, 0); eq(db.all('subjects').length, 0);
});
t('Mercado: estoque + gasto; desfazer', () => {
  db.initMemory();
  db.insert('pantry', { name: 'Ovos', quantity: 6, unit: 'un' });
  const r = N.interpret('Comprei ovos e arroz no mercado por 40 reais', { now: REF });
  eq(r.type, 'draft');
  const { refs } = D.saveDraft(r.draft);
  eq(db.all('pantry').find((p) => p.name === 'Ovos').quantity, 7); eq(db.all('pantry').length, 2); eq(db.all('transactions').length, 1);
  D.undoRefs(refs); eq(db.all('pantry').length, 1); eq(db.all('pantry')[0].quantity, 6); eq(db.all('transactions').length, 0);
});
t('Hábito: marcar e desfazer', () => {
  db.initMemory();
  const h = db.insert('habits', { name: 'Ler', weekdays: [], checkins: [] });
  const { refs } = D.saveDraft({ kind: 'habitCheck', habitName: 'Ler', date: REF });
  eq(h.checkins.length, 1); D.undoRefs(refs); eq(db.get('habits', h.id).checkins.length, 0);
});

// ---------- Sincronização: mesclagem ----------
t('Mescla: edição mais recente vence', () => {
  const a = [{ id: '1', title: 'velho', updatedAt: '2026-01-01T00:00:00Z' }, { id: '2', title: 'só A', updatedAt: '2026-01-01T00:00:00Z' }];
  const b = [{ id: '1', title: 'novo', updatedAt: '2026-02-01T00:00:00Z' }, { id: '3', title: 'só B', updatedAt: '2026-01-05T00:00:00Z' }];
  const m = db.mergeRecords(a, b, {}).sort((x, y) => x.id.localeCompare(y.id));
  eq(m.map((r) => r.title), ['novo', 'só A', 'só B']);
});
t('Mescla: exclusão vence edição anterior, mas não posterior', () => {
  const recs = [{ id: '1', updatedAt: '2026-01-01T00:00:00Z' }, { id: '2', updatedAt: '2026-03-01T00:00:00Z' }];
  const tombs = { 1: '2026-02-01T00:00:00Z', 2: '2026-02-01T00:00:00Z' };
  eq(db.mergeRecords(recs, [], tombs).map((r) => r.id), ['2']);
});
t('Mescla: registros de exclusão ficam com a data mais recente', () => {
  const m = db.mergeTombstones({ events: { a: '2026-01-01' } }, { events: { a: '2026-02-01', b: '2026-01-10' }, pantry: { c: '2026-01-02' } });
  eq(m, { events: { a: '2026-02-01', b: '2026-01-10' }, pantry: { c: '2026-01-02' } });
});
t('Exclusão gera registro de exclusão; mergeRemote aplica exclusões recebidas', () => {
  db.initMemory();
  const e = db.insert('events', { title: 'X' });
  const f = db.insert('events', { title: 'Y' });
  db.remove('events', e.id);
  ok(db.getValue('tombstones').events[e.id], 'deveria registrar a exclusão');
  db.mergeRemote('tombstones', { events: { [f.id]: '2999-01-01T00:00:00Z' } });
  eq(db.all('events').length, 0);
  ok(db.get('events', f.id) === null);
});
t('mergeRemote junta coleções e mantém updatedAt', () => {
  db.initMemory();
  const mine = db.insert('transactions', { title: 'meu', amount: 1 });
  db.mergeRemote('transactions', [{ id: 'r1', title: 'remoto', amount: 2, updatedAt: '2026-01-01T00:00:00Z' }, { ...mine, title: 'antigo', updatedAt: '2000-01-01T00:00:00Z' }]);
  eq(db.all('transactions').map((x) => x.title).sort(), ['meu', 'remoto']);
  ok(mine.updatedAt, 'insert deve definir updatedAt');
});

// ---------- Backup ----------
t('Backup criptografado: ida e volta, senha errada, adulteração', async () => {
  const payload = { app: 'LifeOS', createdAt: new Date().toISOString(), data: { profile: { name: 'Teste' }, events: [{ id: '1', title: 'Prova' }] }, files: null };
  const text = await B.encryptPayload(payload, 'senha-forte-123');
  const back = await B.decryptPayload(text, 'senha-forte-123');
  eq(back.data.events[0].title, 'Prova');
  await throws(() => B.decryptPayload(text, 'errada-123'));
  const o = JSON.parse(text); const bytes = C.fromB64(o.data); bytes[bytes.length - 3] ^= 0xff; o.data = C.toB64(bytes);
  await throws(() => B.decryptPayload(JSON.stringify(o), 'senha-forte-123'));
  await throws(() => B.encryptPayload(payload, '123'));
});

// ---------- Módulos (Home, Calendário, Treino, Editais) ----------
t('Calendário reúne eventos, contas, treinos e concursos com filtro por módulo', () => {
  db.initMemory();
  const day = new Date(2026, 4, 13); // quarta-feira
  const s = db.insert('subjects', { name: 'Física' });
  db.insert('events', { title: 'Prova', category: 'prova', start: new Date(2026, 4, 13, 19).toISOString(), allDay: false, recurrence: 'nenhuma', subjectId: s.id });
  db.insert('recurring', { kind: 'despesa', title: 'Internet', amount: 100, category: 'moradia', dueDate: new Date(2026, 4, 13).toISOString(), recurrence: 'mensal', isActive: true });
  db.insert('workoutPlans', { name: 'Peito', weekdays: [3], exercises: [], reminder: '07:00' });
  db.insert('contests', { organ: 'TRT', examDate: new Date(2026, 4, 13, 8).toISOString() });
  const all = D.calendarItems(day, new Date(2026, 4, 14));
  eq(all.length, 4);
  eq(D.calendarItems(day, new Date(2026, 4, 14), 'estudos').length, 1);
  eq(D.calendarItems(day, new Date(2026, 4, 14), 'financeiro')[0].kind, 'bill');
  eq(D.calendarItems(day, new Date(2026, 4, 14), 'treino')[0].date.getHours(), 7);
  eq(D.calendarItems(day, new Date(2026, 4, 14), 'editais')[0].to.startsWith('contest/'), true);
  // conta mensal aparece de novo no mês seguinte
  eq(D.calendarItems(new Date(2026, 5, 13), new Date(2026, 5, 14), 'financeiro').length, 1);
});
t('Próximo treino pula o dia se já treinou hoje', () => {
  db.initMemory();
  const wed = new Date(2026, 4, 13, 10);
  db.insert('workoutPlans', { name: 'A', weekdays: [3, 5], exercises: [] });
  eq(D.nextWorkout(wed).day.getDate(), 13);
  db.insert('workoutSessions', { title: 'A', date: wed.toISOString(), minutes: 50, entries: [] });
  eq(D.nextWorkout(wed).day.getDate(), 15);
  eq(D.workoutsInWeek(wed), 1);
});
t('Conclusão do edital considera só os conteúdos daquele concurso', () => {
  db.initMemory();
  const a = db.insert('contests', { organ: 'A' }), b = db.insert('contests', { organ: 'B' });
  const sa = db.insert('contestSubjects', { contestId: a.id, name: 'Português' });
  const sb = db.insert('contestSubjects', { contestId: b.id, name: 'Direito' });
  db.insert('topics', { title: 't1', status: 'concluido', contestSubjectId: sa.id });
  db.insert('topics', { title: 't2', status: 'naoIniciado', contestSubjectId: sa.id });
  db.insert('topics', { title: 't3', status: 'naoIniciado', contestSubjectId: sb.id });
  eq(D.contestCompletion(a.id), 0.5); eq(D.contestCompletion(b.id), 0);
});

// ---------- Execução ----------
(async () => {
  let pass = 0;
  for (const [name, fn] of tests) {
    try { await fn(); pass++; results.push(`<span class="ok">✔ ${name}</span>`); }
    catch (e) { results.push(`<span class="fail">✘ ${name} — ${String(e.message).replace(/</g, '&lt;')}</span>`); }
  }
  out.innerHTML = results.join('\n');
  const s = document.getElementById('summary');
  s.textContent = `${pass} de ${tests.length} testes passaram`;
  s.className = pass === tests.length ? 'ok' : 'fail';
  window.__TEST_RESULT__ = { pass, total: tests.length };
})();
