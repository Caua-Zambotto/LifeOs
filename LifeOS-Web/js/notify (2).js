// Notificações locais (sem servidor). A agenda de avisos é recalculada a cada alteração.
// Uma cópia SEM títulos (só horários) fica fora da criptografia para que, mesmo com o app
// bloqueado, um aviso genérico possa ser exibido.
import * as db from './store.js';
import * as D from './domain.js';
import * as U from './util.js';

const HORIZON_DAYS = 45;
let titles = new Map(); // chave -> texto (só em memória, com o app desbloqueado)
let timer = null;

export const notificationPermission = () => (typeof Notification === 'undefined' ? 'unsupported' : Notification.permission);
export async function requestNotifications() {
  if (typeof Notification === 'undefined') return 'unsupported';
  return Notification.requestPermission();
}

async function show(title, body, tag) {
  if (notificationPermission() !== 'granted') return;
  const opts = { body, tag, icon: 'icons/icon-192.png', badge: 'icons/icon-192.png' };
  try {
    const reg = await navigator.serviceWorker?.getRegistration();
    if (reg) { await reg.showNotification(title, opts); return; }
  } catch { /* usa a API direta */ }
  try { new Notification(title, opts); } catch { /* sem suporte */ }
}

/** Aviso imediato (ex.: fim do descanso no treino ao vivo). */
export const notifyNow = (title, body, tag = 'now') => show(title, body, tag);

export function testNotification() {
  if (notificationPermission() !== 'granted') { requestNotifications().then((p) => p === 'granted' && show('LifeOS', 'As notificações estão funcionando.', 'test')); return; }
  show('LifeOS', 'As notificações estão funcionando.', 'test');
}

function settingFor(cat) {
  const s = db.profile().notif?.[cat] || {};
  return { on: s.on !== false, lead: s.lead ?? D.NOTIF_CATS[cat].lead };
}
const atHour = (d) => { const x = new Date(d); x.setHours(db.profile().notifDefaultHour ?? 8, 0, 0, 0); return x; };
const atTime = (d, hhmm) => { const [h, m] = (hhmm || '08:00').split(':').map(Number); const x = new Date(d); x.setHours(h || 0, m || 0, 0, 0); return x; };

/** Calcula os próximos avisos a partir dos dados (apenas com o app desbloqueado). */
export function rebuild() {
  if (!db.isUnlocked()) return;
  const now = new Date();
  const until = U.addDays(now, HORIZON_DAYS);
  const items = [];
  const add = (key, at, cat, title, body) => {
    if (!settingFor(cat).on || at < U.addDays(now, -0.5) || at > until) return;
    items.push({ key, at: at.getTime(), cat });
    titles.set(key, { title, body });
  };
  titles = new Map();
  for (const o of D.occurrences(db.all('events').filter((e) => e.notify && !e.done), U.addDays(now, -1), until)) {
    const e = o.event;
    const base = e.allDay ? atHour(o.date) : o.date;
    add(`ev:${e.id}:${o.date.getTime()}`, new Date(base - (e.lead || 0) * 60000), D.notifCatForEvent(e.category),
      `${D.EVENT_CATS[e.category]?.label}: ${e.title}`, e.allDay ? U.dayMonth(o.date) : U.dateTime(o.date));
  }
  const bl = settingFor('contas').lead;
  for (const r of db.all('recurring').filter((x) => x.isActive && x.kind === 'despesa' && x.notify !== false)) {
    add(`bill:${r.id}:${r.dueDate}`, new Date(atHour(r.dueDate) - bl * 60000), 'contas', `Conta a vencer: ${r.title}`, `Vencimento ${U.relDay(r.dueDate)}.`);
  }
  for (const h of db.all('habits').filter((x) => !x.archived && x.reminder)) {
    for (let i = 0; i < 7; i++) {
      const d = U.addDays(U.startOfDay(now), i);
      if (D.habitScheduled(h, d) && !D.habitDone(h, d)) add(`habit:${h.id}:${U.dateKey(d)}`, atTime(d, h.reminder), 'habitos', 'Hábito', h.name);
    }
  }
  for (const p of db.all('workoutPlans').filter((x) => x.reminder)) {
    for (let i = 0; i < 7; i++) {
      const d = U.addDays(U.startOfDay(now), i);
      if ((p.weekdays || []).includes(d.getDay())) add(`wk:${p.id}:${U.dateKey(d)}`, atTime(d, p.reminder), 'treinos', 'Hora do treino', p.name);
    }
  }
  for (const t of db.all('topics').filter((x) => x.nextReview)) add(`rev:${t.id}:${t.nextReview}`, atHour(t.nextReview), 'revisoes', 'Revisão de estudo', t.title);
  const gl = settingFor('metas').lead;
  for (const g of db.all('goals').filter((x) => x.deadline && !x.completed)) add(`goal:${g.id}:${g.deadline}`, new Date(atHour(g.deadline) - gl * 60000), 'metas', 'Prazo de meta', g.title);
  const pl = settingFor('provas').lead;
  for (const c of db.all('contests')) {
    if (c.examDate) add(`ce:${c.id}:${c.examDate}`, new Date(new Date(c.examDate) - pl * 60000), 'provas', 'Prova de concurso', c.organ);
    if (c.regEnd) add(`cr:${c.id}:${c.regEnd}`, new Date(atHour(c.regEnd) - 86400000), 'provas', 'Inscrições terminam amanhã', c.organ);
  }
  items.sort((a, b) => a.at - b.at);
  db.putMeta('schedule', items.slice(0, 300)).catch(() => {});
}

/** Verifica avisos vencidos e exibe (chamado periodicamente e ao abrir o app). */
export async function tick() {
  const now = Date.now();
  const schedule = (await db.getMeta('schedule')) || [];
  const fired = new Set((await db.getMeta('fired')) || []);
  let changed = false;
  for (const it of schedule) {
    if (it.at > now || it.at < now - 12 * 3600000 || fired.has(it.key)) continue;
    fired.add(it.key); changed = true;
    const t = db.isUnlocked() ? titles.get(it.key) : null;
    await show(t ? t.title : 'LifeOS', t ? t.body : 'Você tem um lembrete. Abra o LifeOS para ver.', it.key);
  }
  if (changed) await db.putMeta('fired', [...fired].slice(-500));
  if (db.isUnlocked()) budgetCheck();
}

function budgetCheck() {
  const plan = D.weeklyPlan();
  const key = 'budget:' + U.dateKey(U.startOfWeek(new Date()));
  if (plan.overBudget && plan.weeklyAllowance > 0 && settingFor('contas').on && localStorage.getItem('lifeos.budgetAlert') !== key) {
    localStorage.setItem('lifeos.budgetAlert', key);
    show('Orçamento da semana ultrapassado', 'Seus gastos passaram do planejado para esta semana.', key);
  }
}

export function start() {
  clearInterval(timer);
  timer = setInterval(() => tick().catch(() => {}), 30000);
  tick().catch(() => {});
}
