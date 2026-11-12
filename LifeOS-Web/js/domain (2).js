// Regras de negócio: rótulos, finanças, estudos, receitas, hábitos, agenda
// e a gravação dos registros preparados pelo assistente (com desfazer).

import * as db from './store.js';
import { fold, startOfDay, addDays, addMonths, startOfWeek, startOfMonth, endOfMonth, sameDay, toDate, money, duration, dateTime, dayMonth, num } from './util.js';
import { bestMatch } from './nlp.js';

// ---------- Rótulos ----------
export const EVENT_CATS = {
  compromisso: { label: 'Compromisso', icon: '📅', color: '#4f8bff' },
  reuniao: { label: 'Reunião', icon: '👥', color: '#6366f1' },
  pessoal: { label: 'Pessoal', icon: '🙂', color: '#14b8a6' },
  prova: { label: 'Prova', icon: '🎓', color: '#ec4899' },
  trabalho: { label: 'Trabalho', icon: '📝', color: '#8b5cf6' },
  entrega: { label: 'Entrega', icon: '📤', color: '#f97316' },
  consulta: { label: 'Consulta', icon: '🩺', color: '#ef4444' },
  treino: { label: 'Treino', icon: '🏋️', color: '#22c55e' },
  lembrete: { label: 'Lembrete', icon: '🔔', color: '#eab308' },
  dataImportante: { label: 'Data importante', icon: '⭐', color: '#10b981' },
  estudo: { label: 'Estudo', icon: '📚', color: '#06b6d4' },
};
export const TASK_CATS = ['trabalho', 'entrega', 'estudo', 'lembrete'];
export const ACADEMIC_CATS = ['prova', 'trabalho', 'entrega', 'estudo'];
export const PRIORITIES = { 0: 'Baixa', 1: 'Média', 2: 'Alta' };
export const RECURRENCES = { nenhuma: 'Não repete', diaria: 'Diariamente', semanal: 'Semanalmente', mensal: 'Mensalmente', anual: 'Anualmente' };

export const FIN_CATS = {
  salario: { label: 'Salário', icon: '💼', color: '#22c55e', kind: 'receita' },
  rendaExtra: { label: 'Renda extra', icon: '✨', color: '#10b981', kind: 'receita' },
  servicos: { label: 'Serviços', icon: '🛠️', color: '#14b8a6', kind: 'receita' },
  outrasReceitas: { label: 'Outras entradas', icon: '⬇️', color: '#06b6d4', kind: 'receita' },
  alimentacao: { label: 'Alimentação', icon: '🍽️', color: '#f97316', kind: 'despesa' },
  transporte: { label: 'Transporte', icon: '🚗', color: '#3b82f6', kind: 'despesa' },
  moradia: { label: 'Moradia', icon: '🏠', color: '#a16207', kind: 'despesa' },
  faculdade: { label: 'Faculdade', icon: '🎓', color: '#8b5cf6', kind: 'despesa' },
  saude: { label: 'Saúde', icon: '❤️', color: '#ef4444', kind: 'despesa' },
  lazer: { label: 'Lazer', icon: '🎮', color: '#ec4899', kind: 'despesa' },
  compras: { label: 'Compras', icon: '🛍️', color: '#6366f1', kind: 'despesa' },
  assinaturas: { label: 'Assinaturas', icon: '🔁', color: '#eab308', kind: 'despesa' },
  internet: { label: 'Internet e telefone', icon: '📶', color: '#0ea5e9', kind: 'despesa' },
  dividas: { label: 'Dívidas', icon: '💳', color: '#b91c1c', kind: 'despesa' },
  reserva: { label: 'Reserva e metas', icon: '🏦', color: '#16a34a', kind: 'despesa' },
  outros: { label: 'Outros', icon: '•', color: '#94a3b8', kind: 'despesa' },
  faturaCartao: { label: 'Pagamento de fatura', icon: '💳', color: '#64748b', kind: 'despesa', hidden: true },
};
export const finCatsFor = (kind) => Object.entries(FIN_CATS).filter(([, v]) => v.kind === kind && !v.hidden).map(([k]) => k);

export const TOPIC_STATUS = {
  naoIniciado: { label: 'Não iniciado', icon: '○', color: '#94a3b8' },
  estudando: { label: 'Estudando', icon: '◐', color: '#3b82f6' },
  concluido: { label: 'Concluído', icon: '●', color: '#22c55e' },
  revisar: { label: 'Precisa revisar', icon: '↻', color: '#f97316' },
};
export const CONTEST_STATUS = {
  interesse: 'Edital de interesse', previsto: 'Previsto', inscricoesAbertas: 'Inscrições abertas',
  inscrito: 'Inscrito', realizado: 'Prova realizada', encerrado: 'Encerrado',
};
export const GOAL_HORIZON = { curto: 'Curto prazo', medio: 'Médio prazo', longo: 'Longo prazo' };
export const GOAL_AREA = {
  pessoal: '🙂 Pessoal', profissional: '💼 Profissional', leitura: '📖 Leitura', aprendizado: '💡 Aprendizado',
  idiomas: '🗣️ Idiomas', saude: '❤️ Saúde', financeira: '💰 Financeira',
};
export const DOC_CATS = {
  edital: '📜 Edital', comprovante: '✅ Comprovante', academico: '🎓 Acadêmico', recibo: '🧾 Recibo',
  anotacao: '🗒️ Anotação', pessoal: '🪪 Pessoal', outro: '📄 Outro',
};
export const NOTIF_CATS = {
  provas: { label: 'Provas', lead: 1440 }, trabalhos: { label: 'Trabalhos e entregas', lead: 1440 },
  compromissos: { label: 'Compromissos', lead: 60 }, contas: { label: 'Contas e vencimentos', lead: 1440 },
  treinos: { label: 'Treinos', lead: 0 }, revisoes: { label: 'Revisões e estudos', lead: 0 },
  habitos: { label: 'Hábitos', lead: 0 }, metas: { label: 'Metas', lead: 1440 },
};
export const LEAD_OPTIONS = { 0: 'No horário', 15: '15 min antes', 30: '30 min antes', 60: '1 hora antes', 120: '2 horas antes', 1440: '1 dia antes', 2880: '2 dias antes', 10080: '1 semana antes' };
export const notifCatForEvent = (c) => ({ prova: 'provas', trabalho: 'trabalhos', entrega: 'trabalhos', treino: 'treinos', estudo: 'revisoes' }[c] || 'compromissos');
export const WEEKDAY_NAMES = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

// ---------- Recorrência e agenda ----------
export function nextRecurrence(d, rec) {
  const x = toDate(d);
  switch (rec) {
    case 'diaria': return addDays(x, 1);
    case 'semanal': return addDays(x, 7);
    case 'mensal': return addMonths(x, 1);
    case 'anual': return addMonths(x, 12);
    default: return null;
  }
}

/** Expande eventos recorrentes no intervalo [from, to). */
export function occurrences(events, from, to) {
  const out = [];
  for (const e of events) {
    let d = toDate(e.start);
    if (!e.recurrence || e.recurrence === 'nenhuma') {
      if (d >= from && d < to) out.push({ event: e, date: d });
      continue;
    }
    for (let i = 0; d < to && i < 1000; i++) {
      if (d >= from) out.push({ event: e, date: d });
      d = nextRecurrence(d, e.recurrence);
    }
  }
  return out.sort((a, b) => a.date - b.date);
}

// ---------- Finanças ----------
export const affectsBalance = (t) => !t.cardId || t.isInvoicePayment;
export const signed = (t) => (t.kind === 'receita' ? t.amount : -t.amount);
const within = (d, i) => { const x = toDate(d); return x >= i.start && x <= i.end; };

export function balance(initial, since, txs, now = new Date()) {
  const s = toDate(since);
  return txs.filter((t) => toDate(t.date) >= s && toDate(t.date) <= now && affectsBalance(t)).reduce((a, t) => a + signed(t), Number(initial) || 0);
}
export const spending = (txs, i) => txs.filter((t) => t.kind === 'despesa' && !t.isInvoicePayment && within(t.date, i)).reduce((a, t) => a + t.amount, 0);
export const income = (txs, i) => txs.filter((t) => t.kind === 'receita' && within(t.date, i)).reduce((a, t) => a + t.amount, 0);
export function byCategory(txs, i) {
  const m = {};
  for (const t of txs) if (t.kind === 'despesa' && !t.isInvoicePayment && within(t.date, i)) m[t.category] = (m[t.category] || 0) + t.amount;
  return Object.entries(m).map(([category, total]) => ({ category, total })).sort((a, b) => b.total - a.total);
}

/** Mês da fatura (compras após o fechamento vão para a fatura seguinte). */
export function invoiceMonth(date, closingDay) {
  const d = toDate(date);
  const m = startOfMonth(d);
  return d.getDate() > closingDay ? addMonths(m, 1) : m;
}
export const invoiceKey = (m) => `${m.getFullYear()}-${String(m.getMonth() + 1).padStart(2, '0')}`;
const cardTxs = (card) => db.all('transactions').filter((t) => t.cardId === card.id);
export const invoiceTotal = (card, month) => cardTxs(card)
  .filter((t) => !t.isInvoicePayment && t.kind === 'despesa' && invoiceMonth(t.date, card.closingDay).getTime() === startOfMonth(month).getTime())
  .reduce((a, t) => a + t.amount, 0);
export function outstanding(card, now = new Date()) {
  const txs = cardTxs(card);
  const bought = txs.filter((t) => !t.isInvoicePayment && t.kind === 'despesa' && toDate(t.date) <= now).reduce((a, t) => a + t.amount, 0);
  const paid = txs.filter((t) => t.isInvoicePayment).reduce((a, t) => a + t.amount, 0);
  return Math.max(0, bought - paid);
}
export const futureInstallments = (card, now = new Date()) => cardTxs(card).filter((t) => !t.isInvoicePayment && toDate(t.date) > now).reduce((a, t) => a + t.amount, 0);

/** Quanto posso gastar por semana. */
export function weeklyPlan(now = new Date()) {
  const p = db.profile();
  const txs = db.all('transactions');
  const monthEnd = endOfMonth(now);
  const monthStart = startOfMonth(now);
  const bal = balance(p.initialBalance, p.balanceDate, txs, now);
  const active = db.all('recurring').filter((r) => r.isActive);
  const expectedIncome = active.filter((r) => r.kind === 'receita' && toDate(r.dueDate) > now && toDate(r.dueDate) <= monthEnd).reduce((a, r) => a + r.amount, 0);
  const pendingBills = active.filter((r) => r.kind === 'despesa' && toDate(r.dueDate) <= monthEnd).reduce((a, r) => a + r.amount, 0);
  const debtPayments = db.all('debts').filter((d) => d.remainingAmount > 0).reduce((a, d) => {
    const paid = (d.payments || []).some((x) => toDate(x.date) >= monthStart);
    return a + (paid ? 0 : Math.min(d.monthlyPayment || 0, d.remainingAmount));
  }, 0);
  const cardInvoices = db.all('cards').reduce((a, c) => a + outstanding(c, now), 0);
  const savingsDone = txs.filter((t) => t.category === 'reserva' && toDate(t.date) >= monthStart && toDate(t.date) <= now).reduce((a, t) => a + t.amount, 0);
  const savingsTarget = Math.max(0, (p.monthlySavingsTarget || 0) - savingsDone);
  const daysLeft = Math.round((startOfDay(monthEnd) - startOfDay(now)) / 86400000) + 1;
  const weeksRemaining = Math.max(1, Math.ceil(daysLeft / 7));
  const spentThisWeek = spending(txs, { start: startOfWeek(now), end: now });
  const available = bal + expectedIncome - pendingBills - debtPayments - cardInvoices - savingsTarget;
  const weeklyAllowance = Math.max(0, (available + spentThisWeek) / weeksRemaining);
  const remaining = weeklyAllowance - spentThisWeek;
  return { balance: bal, expectedIncome, pendingBills, debtPayments, cardInvoices, savingsTarget, weeksRemaining,
    spentThisWeek, available, weeklyAllowance, remaining, overBudget: remaining < 0 };
}

/** Cria transação; compras parceladas no cartão viram N transações mensais. */
export function addTransaction({ title, amount, kind, category, date, cardId = null, installments = 1, note = '' }) {
  const n = cardId ? Math.max(1, installments) : 1;
  const total = Math.round(amount * 100) / 100;
  const base = Math.floor((total / n) * 100) / 100;
  const group = n > 1 ? crypto.randomUUID() : null;
  const out = [];
  for (let i = 0; i < n; i++) {
    const value = i === n - 1 ? Math.round((total - base * (n - 1)) * 100) / 100 : base;
    out.push(db.insert('transactions', {
      title: n > 1 ? `${title} (${i + 1}/${n})` : title, amount: value, kind, category,
      date: addMonths(toDate(date), i).toISOString(), note, cardId, isInvoicePayment: false,
      installmentGroup: group, installmentNumber: n > 1 ? i + 1 : 0, installmentCount: n > 1 ? n : 0,
    }));
  }
  return out;
}

export function settleRecurring(r, date = new Date()) {
  db.insert('transactions', { title: r.title, amount: r.amount, kind: r.kind, category: r.category, date: date.toISOString(), note: 'Conta recorrente', cardId: null });
  const next = nextRecurrence(r.dueDate, r.recurrence);
  db.update('recurring', r.id, next ? { dueDate: next.toISOString(), lastSettledAt: date.toISOString() } : { isActive: false, lastSettledAt: date.toISOString() });
}

export function payInvoice(card, amount) {
  db.insert('transactions', { title: `Fatura ${card.name}`, amount, kind: 'despesa', category: 'faturaCartao', date: new Date().toISOString(), cardId: card.id, isInvoicePayment: true });
}

export function payDebt(debt, amount, registerExpense) {
  const remaining = Math.max(0, debt.remainingAmount - amount);
  const payments = [...(debt.payments || []), { date: new Date().toISOString(), amount, remainingAfter: remaining }];
  db.update('debts', debt.id, { remainingAmount: remaining, payments });
  if (registerExpense) db.insert('transactions', { title: `Pagamento ${debt.creditor}`, amount, kind: 'despesa', category: 'dividas', date: new Date().toISOString(), cardId: null });
}

// ---------- Estudos ----------
export const REVIEW_INTERVALS = [1, 7, 15, 30, 60];
export function setTopicStatus(topic, status, now = new Date()) {
  const patch = { status };
  if (status === 'concluido') Object.assign(patch, { lastStudied: now.toISOString(), reviewStage: 0, nextReview: addDays(startOfDay(now), 1).toISOString() });
  if (status === 'revisar') patch.nextReview = startOfDay(now).toISOString();
  if (status === 'estudando') patch.lastStudied = now.toISOString();
  if (status === 'naoIniciado') Object.assign(patch, { nextReview: null, reviewStage: 0 });
  db.update('topics', topic.id, patch);
}
export function markReviewed(topic, now = new Date()) {
  const stage = (topic.reviewStage || 0) + 1;
  db.update('topics', topic.id, {
    status: 'concluido', lastStudied: now.toISOString(), reviewStage: stage,
    nextReview: stage < REVIEW_INTERVALS.length ? addDays(startOfDay(now), REVIEW_INTERVALS[stage]).toISOString() : null,
  });
}
export const isReviewDue = (t, now = new Date()) => !!t.nextReview && toDate(t.nextReview) <= now;
export function topicProgress(topics) {
  if (!topics.length) return 0;
  return topics.filter((t) => t.status === 'concluido').length / topics.length;
}
export function weightedAverage(grades) {
  const w = grades.reduce((a, g) => a + (g.weight || 1), 0);
  if (!w) return null;
  return grades.reduce((a, g) => a + (g.maxValue ? (g.value / g.maxValue) * 10 : 0) * (g.weight || 1), 0) / w;
}

/** Percentual concluído do edital (todos os conteúdos das disciplinas do concurso). */
export function contestTopics(contestId) {
  const subs = new Set(db.all('contestSubjects').filter((s) => s.contestId === contestId).map((s) => s.id));
  return db.all('topics').filter((t) => subs.has(t.contestSubjectId));
}
export const contestCompletion = (contestId) => topicProgress(contestTopics(contestId));

// ---------- Treino ----------
/** Próxima ficha programada (hoje só conta se o treino de hoje ainda não foi registrado). */
export function nextWorkout(now = new Date()) {
  const trainedToday = db.all('workoutSessions').some((s) => sameDay(s.date, now));
  let best = null;
  for (const p of db.all('workoutPlans')) {
    for (let i = 0; i < 8; i++) {
      if (i === 0 && trainedToday) continue;
      const d = addDays(startOfDay(now), i);
      if ((p.weekdays || []).includes(d.getDay())) { if (!best || d < best.day) best = { plan: p, day: d }; break; }
    }
  }
  return best;
}
export const workoutsInWeek = (now = new Date()) => db.all('workoutSessions').filter((s) => toDate(s.date) >= startOfWeek(now) && toDate(s.date) <= now).length;
export const studyMinutesInWeek = (now = new Date()) => db.all('studySessions').filter((s) => toDate(s.date) >= startOfWeek(now) && toDate(s.date) <= now).reduce((a, s) => a + (s.minutes || 0), 0);

// ---------- Calendário integrado ----------
export const CAL_MODULES = {
  todos: { label: 'Todos', icon: '◎', color: '#7c5cff' },
  estudos: { label: 'Estudos', icon: '📚', color: '#d946ef' },
  treino: { label: 'Treino', icon: '🏋️', color: '#22c55e' },
  editais: { label: 'Editais', icon: '🏛️', color: '#6366f1' },
  financeiro: { label: 'Financeiro', icon: '💰', color: '#10b981' },
  pessoal: { label: 'Pessoal', icon: '📅', color: '#3b82f6' },
};
export function moduleOfEvent(e) {
  if (e.contestId) return 'editais';
  if (ACADEMIC_CATS.includes(e.category)) return 'estudos';
  if (e.category === 'treino') return 'treino';
  return 'pessoal';
}

/** Junta eventos, contas, treinos programados e datas de concursos no intervalo [from, to). */
export function calendarItems(from, to, filter = 'todos') {
  const out = [];
  for (const o of occurrences(db.all('events'), from, to)) {
    const e = o.event, c = EVENT_CATS[e.category] || EVENT_CATS.compromisso;
    const subj = e.subjectId && db.get('subjects', e.subjectId);
    const cont = e.contestId && db.get('contests', e.contestId);
    out.push({ key: `e-${e.id}-${+o.date}`, kind: 'event', event: e, date: o.date, allDay: !!e.allDay, module: moduleOfEvent(e),
      icon: c.icon, color: c.color, title: e.title, subtitle: [c.label, subj?.name, cont?.organ].filter(Boolean).join(' · ') });
  }
  for (const r of db.all('recurring').filter((x) => x.isActive)) {
    let d = toDate(r.dueDate);
    for (let i = 0; d && d < to && i < 60; i++) {
      if (d >= from) out.push({ key: `b-${r.id}-${+d}`, kind: 'bill', date: d, allDay: true, module: 'financeiro', icon: r.kind === 'receita' ? '⬇' : '💳',
        color: r.kind === 'receita' ? '#22c55e' : '#f97316', title: `${r.kind === 'receita' ? 'Receber' : 'Vencimento'}: ${r.title}`, subtitle: money(r.amount), to: 'finance' });
      d = nextRecurrence(d, r.recurrence);
    }
  }
  for (let d = startOfDay(from); d < to; d = addDays(d, 1)) {
    for (const p of db.all('workoutPlans')) {
      if (!(p.weekdays || []).includes(d.getDay())) continue;
      const at = new Date(d);
      if (p.reminder) { const [h, m] = p.reminder.split(':').map(Number); at.setHours(h || 0, m || 0, 0, 0); }
      out.push({ key: `w-${p.id}-${+d}`, kind: 'workout', date: at, allDay: !p.reminder, module: 'treino', icon: '🏋️', color: '#22c55e',
        title: `Treino: ${p.name}`, subtitle: `${(p.exercises || []).length} exercícios`, to: 'workouts' });
    }
  }
  for (const c of db.all('contests')) {
    for (const [field, label] of [['examDate', 'Prova'], ['regStart', 'Início das inscrições'], ['regEnd', 'Fim das inscrições']]) {
      const d = c[field] && toDate(c[field]);
      if (d && d >= from && d < to) out.push({ key: `c-${c.id}-${field}`, kind: 'contest', date: d, allDay: field !== 'examDate', module: 'editais', icon: '🏛️',
        color: '#6366f1', title: `${label}: ${c.organ}`, subtitle: c.role || '', to: `contest/${c.id}` });
    }
  }
  return out.filter((x) => filter === 'todos' || x.module === filter)
    .sort((a, b) => (a.allDay === b.allDay ? a.date - b.date : a.allDay ? -1 : 1));
}

// ---------- Hábitos ----------
export const habitScheduled = (h, d) => !h.weekdays?.length || h.weekdays.includes(toDate(d).getDay());
export const habitDone = (h, d) => (h.checkins || []).some((c) => sameDay(c, d));
export function toggleHabit(h, d) {
  const list = (h.checkins || []).filter((c) => !sameDay(c, d));
  if (list.length === (h.checkins || []).length) list.push(startOfDay(d).toISOString());
  db.update('habits', h.id, { checkins: list });
}
export function habitStreak(h, now = new Date()) {
  let day = startOfDay(now), n = 0;
  if (habitScheduled(h, day) && !habitDone(h, day)) day = addDays(day, -1);
  for (let i = 0; i < 366; i++) {
    if (habitScheduled(h, day)) { if (habitDone(h, day)) n++; else break; }
    day = addDays(day, -1);
  }
  return n;
}
export function habitConsistency(h, days, now = new Date()) {
  const ds = [...Array(days).keys()].map((i) => addDays(startOfDay(now), -i)).filter((d) => habitScheduled(h, d));
  return ds.length ? ds.filter((d) => habitDone(h, d)).length / ds.length : 0;
}

// ---------- Receitas ----------
export const RECIPE_CATALOG = [
  ['omelete-legumes', 'Omelete de legumes', 10, 1, [['Ovos', '2 unidades'], ['Tomate', '1/2 unidade'], ['Cebola', '1/4 unidade'], ['Sal', 'a gosto']], ['Bata os ovos com uma pitada de sal.', 'Pique o tomate e a cebola e misture aos ovos.', 'Despeje em frigideira untada e cozinhe em fogo baixo, tampado, por 4 minutos.', 'Dobre ao meio e sirva.'], [190, 13, 6, 12], ['rápida', 'proteica']],
  ['arroz-feijao-ovo', 'Prato feito com ovo', 15, 1, [['Arroz', '1 xícara cozido'], ['Feijão', '1 concha'], ['Ovos', '1 unidade'], ['Alface', 'folhas a gosto']], ['Aqueça o arroz e o feijão já cozidos.', 'Frite ou cozinhe o ovo.', 'Monte o prato com salada de alface.'], [480, 19, 72, 11], ['econômica', 'equilibrada']],
  ['frango-grelhado-batata', 'Frango grelhado com batata', 30, 2, [['Frango', '300 g de peito'], ['Batata', '2 unidades'], ['Alho', '2 dentes'], ['Limão', '1/2 unidade'], ['Sal', 'a gosto']], ['Tempere o frango com alho, limão e sal.', 'Cozinhe as batatas em cubos por 12 minutos.', 'Grelhe o frango 5 minutos de cada lado.', 'Doure as batatas na mesma frigideira e sirva.'], [390, 38, 33, 9], ['proteica']],
  ['frango-arroz-brocolis', 'Frango com arroz e brócolis', 25, 2, [['Frango', '300 g'], ['Arroz', '1 xícara cru'], ['Brócolis', '1 maço pequeno'], ['Alho', '2 dentes'], ['Sal', 'a gosto']], ['Cozinhe o arroz.', 'Doure o frango em cubos com alho.', 'Cozinhe o brócolis no vapor por 5 minutos.', 'Misture tudo e ajuste o sal.'], [520, 40, 68, 8], ['equilibrada', 'marmita']],
  ['macarrao-atum', 'Macarrão alho e óleo com atum', 20, 2, [['Macarrão', '200 g'], ['Atum', '1 lata'], ['Alho', '3 dentes'], ['Azeite', '2 colheres'], ['Sal', 'a gosto']], ['Cozinhe o macarrão em água com sal.', 'Doure o alho no azeite.', 'Junte o atum escorrido e o macarrão.', 'Misture bem e sirva.'], [560, 30, 78, 14], ['rápida', 'econômica']],
  ['carne-moida-batata', 'Carne moída com batata', 30, 3, [['Carne moída', '400 g'], ['Batata', '3 unidades'], ['Cebola', '1 unidade'], ['Tomate', '1 unidade'], ['Sal', 'a gosto']], ['Refogue a cebola e a carne até dourar.', 'Junte o tomate picado.', 'Acrescente batatas em cubos e um pouco de água.', 'Cozinhe tampado por 15 minutos.'], [410, 29, 28, 19], ['marmita']],
  ['panqueca-banana', 'Panqueca de banana e aveia', 10, 1, [['Banana', '1 unidade'], ['Ovos', '1 unidade'], ['Aveia', '2 colheres']], ['Amasse a banana.', 'Misture o ovo e a aveia.', 'Cozinhe em frigideira antiaderente, 2 minutos de cada lado.'], [250, 10, 36, 7], ['café da manhã', 'rápida']],
  ['crepioca', 'Crepioca com queijo', 8, 1, [['Ovos', '1 unidade'], ['Tapioca', '2 colheres'], ['Queijo', '1 fatia']], ['Misture o ovo e a goma de tapioca.', 'Despeje na frigideira quente.', 'Recheie com queijo, dobre e sirva.'], [260, 13, 25, 11], ['café da manhã', 'rápida']],
  ['cuscuz-ovos', 'Cuscuz com ovos mexidos', 15, 1, [['Flocão de milho', '1/2 xícara'], ['Ovos', '2 unidades'], ['Sal', 'a gosto']], ['Hidrate o flocão com água e sal por 5 minutos.', 'Cozinhe no vapor por 8 minutos.', 'Faça os ovos mexidos e sirva junto.'], [380, 16, 48, 11], ['econômica', 'café da manhã']],
  ['sopa-legumes', 'Sopa de legumes', 30, 3, [['Batata', '2 unidades'], ['Cenoura', '1 unidade'], ['Abobrinha', '1 unidade'], ['Cebola', '1 unidade'], ['Sal', 'a gosto']], ['Pique todos os legumes.', 'Refogue a cebola.', 'Junte os legumes e cubra com água.', 'Cozinhe por 20 minutos e ajuste o sal.'], [150, 4, 30, 2], ['leve', 'econômica']],
  ['salada-grao-bico', 'Salada de grão-de-bico', 10, 2, [['Grão-de-bico', '1 xícara cozido'], ['Tomate', '1 unidade'], ['Cebola', '1/2 unidade'], ['Limão', '1/2 unidade'], ['Azeite', '1 colher']], ['Escorra o grão-de-bico.', 'Pique tomate e cebola.', 'Tempere com limão, azeite e sal.'], [260, 11, 35, 8], ['vegetariana', 'sem fogão']],
  ['iogurte-frutas', 'Iogurte com frutas e aveia', 5, 1, [['Iogurte', '1 pote'], ['Banana', '1 unidade'], ['Aveia', '2 colheres']], ['Coloque o iogurte em uma tigela.', 'Adicione banana em rodelas e aveia.'], [280, 11, 45, 6], ['lanche', 'sem fogão']],
  ['peixe-legumes', 'Peixe assado com legumes', 30, 2, [['Peixe', '2 filés'], ['Batata', '2 unidades'], ['Cenoura', '1 unidade'], ['Limão', '1 unidade'], ['Azeite', '1 colher']], ['Tempere o peixe com limão e sal.', 'Corte os legumes em rodelas finas.', 'Asse tudo a 200 °C por 25 minutos.'], [340, 32, 30, 9], ['proteica', 'forno']],
  ['mexido-feijao', 'Mexido de feijão com ovo', 15, 2, [['Feijão', '2 xícaras cozido'], ['Ovos', '2 unidades'], ['Farinha de mandioca', '4 colheres'], ['Cebola', '1/2 unidade']], ['Refogue a cebola.', 'Junte os ovos e mexa.', 'Acrescente o feijão escorrido e a farinha aos poucos.'], [360, 17, 50, 9], ['econômica']],
  ['wrap-frango', 'Wrap de frango', 15, 2, [['Pão folha', '2 unidades'], ['Frango', '200 g desfiado'], ['Alface', 'folhas'], ['Tomate', '1 unidade'], ['Requeijão', '2 colheres']], ['Aqueça o frango desfiado temperado.', 'Passe requeijão no pão folha.', 'Recheie com frango, alface e tomate e enrole.'], [380, 30, 35, 12], ['rápida', 'lanche']],
  ['arroz-forno', 'Arroz de forno com frango', 35, 4, [['Arroz', '3 xícaras cozido'], ['Frango', '250 g desfiado'], ['Milho', '1 lata'], ['Queijo', '100 g'], ['Tomate', '1 unidade']], ['Misture arroz, frango, milho e tomate picado.', 'Coloque em refratário e cubra com queijo.', 'Asse até gratinar (15 minutos).'], [430, 26, 52, 12], ['forno', 'marmita']],
  ['pure-carne', 'Purê de batata com carne', 30, 2, [['Batata', '4 unidades'], ['Leite', '1/2 xícara'], ['Manteiga', '1 colher'], ['Carne moída', '250 g']], ['Cozinhe e amasse as batatas com leite e manteiga.', 'Refogue a carne moída temperada.', 'Sirva o purê com a carne por cima.'], [470, 28, 42, 20], ['conforto']],
  ['salada-atum', 'Salada completa com atum', 10, 1, [['Atum', '1 lata'], ['Alface', '1 prato'], ['Tomate', '1 unidade'], ['Milho', '2 colheres'], ['Ovos', '1 cozido']], ['Lave e corte as folhas e o tomate.', 'Junte atum, milho e ovo cozido.', 'Tempere com azeite, limão e sal.'], [330, 34, 14, 15], ['leve', 'proteica', 'sem fogão']],
  ['abobora-carne', 'Abóbora refogada com carne', 25, 2, [['Abóbora', '400 g'], ['Carne moída', '200 g'], ['Cebola', '1 unidade'], ['Alho', '2 dentes']], ['Refogue cebola, alho e carne.', 'Junte a abóbora em cubos e um pouco de água.', 'Cozinhe tampado até amaciar.'], [330, 24, 22, 15], ['equilibrada']],
  ['arroz-lentilha', 'Arroz com lentilha', 30, 3, [['Arroz', '1 xícara cru'], ['Lentilha', '1 xícara'], ['Cebola', '1 unidade'], ['Azeite', '1 colher']], ['Cozinhe a lentilha por 10 minutos.', 'Refogue a cebola, junte arroz, lentilha e água.', 'Cozinhe até secar.'], [390, 16, 70, 5], ['vegetariana', 'econômica']],
  ['vitamina-banana', 'Vitamina de banana', 5, 1, [['Leite', '300 ml'], ['Banana', '1 unidade'], ['Aveia', '1 colher']], ['Bata tudo no liquidificador e sirva gelado.'], [300, 12, 45, 8], ['lanche', 'rápida']],
].map(([key, name, minutes, servings, ingr, steps, [kcal, protein, carbs, fat], tags]) => ({
  id: 'cat:' + key, builtIn: true, name, minutes, servings, ingredients: ingr.map(([n, q]) => ({ name: n, qty: q })), steps, kcal, protein, carbs, fat, tags,
}));

export const allRecipes = () => [...RECIPE_CATALOG, ...db.all('recipes')];
const STAPLES = new Set(['sal', 'pimenta', 'agua', 'oleo', 'azeite', 'acucar', 'alho', 'temperos']);
export function canonical(name) {
  let n = fold(name).trim().replace(/\s+de\s+/g, ' ').replace(/-/g, ' ');
  if (n.endsWith('oes')) n = n.slice(0, -3) + 'ao';
  else if (n.endsWith('s') && n.length > 3) n = n.slice(0, -1);
  return n;
}
export function hasIngredient(name, stock) {
  const c = canonical(name);
  if (STAPLES.has(c)) return true;
  for (const s of stock) if (s === c || s.includes(c) || c.includes(s)) return true;
  return false;
}
export function suggestRecipes(recipes, pantry, minScore = 0.5) {
  const stock = new Set(pantry.filter((p) => p.quantity > 0).map((p) => canonical(p.name)));
  return recipes.map((r) => {
    const rel = r.ingredients.map((i) => i.name).filter((n) => !STAPLES.has(canonical(n)));
    const have = rel.filter((n) => hasIngredient(n, stock));
    const missing = rel.filter((n) => !hasIngredient(n, stock));
    return { recipe: r, have, missing, score: rel.length ? have.length / rel.length : 0 };
  }).filter((s) => s.score >= minScore && s.have.length).sort((a, b) => b.score - a.score || a.recipe.minutes - b.recipe.minutes);
}

export const COMMON_FOODS = ['Arroz', 'Feijão', 'Ovos', 'Frango', 'Carne moída', 'Batata', 'Cebola', 'Alho', 'Tomate', 'Leite', 'Queijo',
  'Pão', 'Macarrão', 'Banana', 'Maçã', 'Aveia', 'Iogurte', 'Manteiga', 'Cenoura', 'Alface', 'Brócolis', 'Peixe', 'Atum', 'Café',
  'Farinha de mandioca', 'Abóbora', 'Abobrinha', 'Limão', 'Milho', 'Lentilha', 'Grão-de-bico', 'Tapioca', 'Flocão de milho', 'Requeijão', 'Pão folha'];

// ---------- Assistente: contexto, gravação e desfazer ----------
export function interpreterContext() {
  return {
    subjectNames: db.all('subjects').map((s) => s.name),
    contestSubjectNames: db.all('contestSubjects').map((s) => s.name),
    habitNames: db.all('habits').filter((h) => !h.archived).map((h) => h.name),
    cardNames: db.all('cards').map((c) => c.name),
    now: new Date(),
  };
}

const findByName = (col, name) => { const list = db.all(col); const m = bestMatch(name, list.map((x) => x.name)); return m ? list.find((x) => x.name === m) : null; };

export function draftSummary(d) {
  const rows = [];
  const date = d.date ? (d.hasTime ? dateTime(d.date) : dayMonth(d.date)) : null;
  switch (d.kind) {
    case 'expense': case 'income':
      rows.push(['Descrição', d.title]);
      if (d.amount) rows.push(['Valor', money(d.amount)]);
      rows.push(['Categoria', FIN_CATS[d.financeCategory]?.label || d.financeCategory]);
      if (date) rows.push(['Data', date]);
      if (d.cardName) rows.push(['Cartão', d.cardName]);
      if (d.installments > 1 && d.amount) rows.push(['Parcelas', `${d.installments}x de ${money(d.amount / d.installments)}`]);
      break;
    case 'bill':
      rows.push(['Conta', d.title]);
      if (d.amount) rows.push(['Valor', money(d.amount)]);
      if (date) rows.push(['Vencimento', date]);
      rows.push(['Repetição', RECURRENCES[d.recurrence]]);
      rows.push(['Categoria', FIN_CATS[d.financeCategory]?.label]);
      break;
    case 'event':
      rows.push(['Tipo', EVENT_CATS[d.eventCategory].label]);
      rows.push(['Título', d.title]);
      if (date) rows.push(['Quando', d.hasTime ? date : `${date} (dia inteiro)`]);
      if (d.subjectName) rows.push(['Matéria', d.subjectName + (d.subjectExists ? '' : ' (nova)')]);
      rows.push(['Prioridade', PRIORITIES[d.priority]]);
      break;
    case 'studySession':
      if (d.subjectName) rows.push(['Assunto', d.subjectName]);
      if (d.minutes) rows.push(['Duração', duration(d.minutes)]);
      if (date) rows.push(['Data', date]);
      break;
    case 'body': {
      const labels = { waist: 'Cintura', arm: 'Braço', chest: 'Peito', leg: 'Perna', hip: 'Quadril', bodyFat: 'Gordura corporal' };
      if (d.weight) rows.push(['Peso', `${num(d.weight)} kg`]);
      for (const [k, v] of Object.entries(d.measurements)) rows.push([labels[k], k === 'bodyFat' ? `${num(v)}%` : `${num(v)} cm`]);
      if (date) rows.push(['Data', date]);
      break;
    }
    case 'workout':
      rows.push(['Treino', d.title]);
      if (d.minutes) rows.push(['Duração', duration(d.minutes)]);
      if (date) rows.push(['Data', date]);
      break;
    case 'groceries':
      rows.push(['Itens', d.items.map((i) => (i.quantity === 1 && i.unit === 'un' ? i.name : `${num(i.quantity)} ${i.unit} ${i.name}`)).join(', ')]);
      if (d.amount) rows.push(['Valor gasto', money(d.amount)]);
      break;
    case 'habitCheck':
      rows.push(['Hábito', d.habitName]);
      break;
    default: break;
  }
  return rows;
}

export const DRAFT_LABEL = {
  expense: 'despesa', income: 'receita', bill: 'conta a pagar', event: 'agenda', studySession: 'sessão de estudo',
  body: 'medidas corporais', workout: 'treino', groceries: 'compras de mercado', habitCheck: 'hábito',
};

/** Grava o rascunho confirmado. Retorna { refs, message }. */
export function saveDraft(d) {
  const refs = [];
  const iso = (x) => toDate(x || new Date()).toISOString();
  let message = 'Pronto! Registro salvo.';
  switch (d.kind) {
    case 'expense': case 'income': {
      const card = d.cardName ? db.all('cards').find((c) => c.name === d.cardName) : null;
      addTransaction({ title: d.title, amount: d.amount, kind: d.kind === 'income' ? 'receita' : 'despesa', category: d.financeCategory,
        date: iso(d.date), cardId: card?.id || null, installments: d.installments })
        .forEach((t) => refs.push(`transactions:${t.id}`));
      message = d.kind === 'income' ? 'Receita registrada em Finanças.' : 'Despesa registrada em Finanças.';
      break;
    }
    case 'bill': {
      const r = db.insert('recurring', { title: d.title, amount: d.amount, kind: 'despesa', category: d.financeCategory, dueDate: iso(d.date), recurrence: d.recurrence, isActive: true, notify: true });
      refs.push(`recurring:${r.id}`);
      message = 'Conta adicionada. Vou lembrar antes do vencimento.';
      break;
    }
    case 'event': {
      let subjectId = null;
      if (d.subjectName) {
        const s = findByName('subjects', d.subjectName);
        if (s) subjectId = s.id;
        else if (!d.subjectExists && ['prova', 'trabalho'].includes(d.eventCategory)) {
          const ns = db.insert('subjects', { name: d.subjectName, professor: '', semester: '', color: '#8b5cf6', notes: '' });
          subjectId = ns.id;
          refs.push(`subjects:${ns.id}`);
        }
      }
      const e = db.insert('events', {
        title: d.title, details: d.sourceText, start: iso(d.hasTime ? d.date : startOfDay(d.date)), allDay: !d.hasTime,
        category: d.eventCategory, priority: d.priority, recurrence: 'nenhuma', notify: true,
        lead: NOTIF_CATS[notifCatForEvent(d.eventCategory)].lead, done: false, subjectId, contestId: null,
      });
      refs.unshift(`events:${e.id}`);
      const s = subjectId && db.get('subjects', subjectId);
      message = s ? `Salvo na Agenda e na matéria ${s.name}.` : 'Salvo na Agenda.';
      break;
    }
    case 'studySession': {
      const s = d.subjectName && findByName('subjects', d.subjectName);
      const cs = !s && d.subjectName && findByName('contestSubjects', d.subjectName);
      const x = db.insert('studySessions', { date: iso(d.date), minutes: d.minutes, note: d.subjectName || '', subjectId: s?.id || null,
        contestSubjectId: cs?.id || null, contestId: cs?.contestId || null });
      refs.push(`studySessions:${x.id}`);
      message = `Sessão de ${duration(d.minutes)} registrada.`;
      break;
    }
    case 'body': {
      const m = db.insert('body', { date: iso(d.date), weight: d.weight, ...d.measurements });
      refs.push(`body:${m.id}`);
      message = 'Medidas registradas. O gráfico foi atualizado.';
      break;
    }
    case 'workout': {
      const groups = d.muscleGroups.map(fold);
      const plan = groups.length ? db.all('workoutPlans').find((p) => groups.every((g) => fold(p.name).includes(g))) : null;
      const w = db.insert('workoutSessions', { date: iso(d.date), title: d.title, muscleGroups: d.muscleGroups, minutes: d.minutes || 0,
        notes: '', planId: plan?.id || null, entries: plan ? plan.exercises.map((e) => ({ name: e.name, sets: e.sets, reps: e.reps, load: e.load })) : [] });
      refs.push(`workoutSessions:${w.id}`);
      message = plan ? `Treino registrado com os exercícios da divisão "${plan.name}".` : 'Treino registrado no histórico.';
      break;
    }
    case 'groceries': {
      for (const it of d.items) {
        const same = db.all('pantry').find((p) => fold(p.name) === fold(it.name) && p.unit === it.unit);
        if (same) { db.update('pantry', same.id, { quantity: same.quantity + it.quantity }); refs.push(`pantryAdd:${same.id}:${it.quantity}`); }
        else refs.push(`pantry:${db.insert('pantry', { name: it.name, quantity: it.quantity, unit: it.unit, expiresAt: null }).id}`);
      }
      if (d.amount > 0) addTransaction({ title: 'Mercado', amount: d.amount, kind: 'despesa', category: 'alimentacao', date: iso(d.date) }).forEach((t) => refs.push(`transactions:${t.id}`));
      message = `${d.items.length} item(ns) no estoque.${d.amount ? ' Gasto lançado em Finanças.' : ''} Veja receitas em Alimentação.`;
      break;
    }
    case 'habitCheck': {
      const h = db.all('habits').find((x) => x.name === d.habitName);
      if (h && !habitDone(h, d.date || new Date())) { toggleHabit(h, d.date || new Date()); refs.push(`checkin:${h.id}:${startOfDay(d.date || new Date()).toISOString()}`); }
      message = `Hábito "${d.habitName}" marcado.`;
      break;
    }
    default: break;
  }
  return { refs, message };
}

export function undoRefs(refs) {
  for (const ref of refs) {
    const [col, id, extra] = splitRef(ref);
    if (col === 'pantryAdd') {
      const p = db.get('pantry', id);
      if (p) { const q = Math.max(0, p.quantity - Number(extra)); q ? db.update('pantry', id, { quantity: q }) : db.remove('pantry', id); }
    } else if (col === 'checkin') {
      const h = db.get('habits', id);
      if (h) db.update('habits', id, { checkins: (h.checkins || []).filter((c) => !sameDay(c, extra)) });
    } else if (col === 'subjects') {
      const others = db.all('events').some((e) => e.subjectId === id && !refs.includes(`events:${e.id}`));
      if (!others) db.remove('subjects', id);
    } else if (db.COLLECTIONS.includes(col)) {
      db.remove(col, id);
    }
  }
}
function splitRef(ref) {
  const i = ref.indexOf(':');
  const j = ref.indexOf(':', i + 1);
  if (j < 0) return [ref.slice(0, i), ref.slice(i + 1), null];
  return [ref.slice(0, i), ref.slice(i + 1, j), ref.slice(j + 1)];
}
