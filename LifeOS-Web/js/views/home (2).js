// HOME — dashboard geral: resumo inteligente de todos os módulos.
// Cada card abre o módulo correspondente; tudo é calculado dos dados reais e atualiza sozinho.
import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { icon, modal } from '../ui.js';
import { ring, progress } from '../charts.js';
import { eventEditor } from './agenda.js';

export const SECTIONS = {
  alerts: 'Avisos importantes', today: 'Hoje', indicators: 'Estudos, editais e treino', workout: 'Próximo treino',
  finance: 'Resumo financeiro do mês', bills: 'Contas a vencer', upcoming: 'Próximas atividades',
  growth: 'Metas e hábitos', productivity: 'Produtividade da semana',
};
const enabledSections = () => db.profile().homeSections || Object.keys(SECTIONS);

const head = (title, emoji, to, detail = '') => `<button class="card-h" ${to ? `data-act="nav" data-to="${to}"` : 'disabled'}>
  <span class="card-h-i">${emoji}</span><b>${esc(title)}</b><span class="grow"></span>${detail ? `<small class="muted">${esc(detail)}</small>` : ''}${to ? icon('chevron', 16) : ''}</button>`;

function stats(now) {
  const p = db.profile();
  const today = U.startOfDay(now);
  const college = db.all('topics').filter((t) => t.subjectId);
  const contestT = db.all('topics').filter((t) => t.contestSubjectId);
  const month = { start: U.startOfMonth(now), end: now };
  const txs = db.all('transactions');
  const plan = D.weeklyPlan(now);
  const weekStart = U.startOfWeek(now);
  const tasks = db.all('events').filter((e) => (D.TASK_CATS.includes(e.category) || e.category === 'prova') && e.recurrence === 'nenhuma'
    && new Date(e.start) >= weekStart && new Date(e.start) <= now);
  const habits = db.all('habits').filter((h) => !h.archived);
  const s = {
    studyMin: D.studyMinutesInWeek(now), studyGoal: Math.max(1, p.weeklyStudyGoalMinutes || 600),
    college: D.topicProgress(college), collegeN: college.length, contest: D.topicProgress(contestT), contestN: contestT.length,
    workouts: D.workoutsInWeek(now), workoutGoal: Math.max(1, p.weeklyWorkoutGoal || 4), next: D.nextWorkout(now),
    income: D.income(txs, month), spent: D.spending(txs, month), cats: D.byCategory(txs, month).slice(0, 3), plan,
    tasksDone: tasks.filter((e) => e.done).length, tasksTotal: tasks.length,
    habitRate: habits.length ? habits.reduce((a, h) => a + D.habitConsistency(h, 7, now), 0) / habits.length : null,
    reviews: db.all('topics').filter((t) => D.isReviewDue(t, now)).length,
    today: D.calendarItems(today, U.addDays(today, 1)).filter((x) => x.kind !== 'workout'),
  };
  s.studyRate = Math.min(1, s.studyMin / s.studyGoal);
  s.workoutRate = Math.min(1, s.workouts / s.workoutGoal);
  s.taskRate = s.tasksTotal ? s.tasksDone / s.tasksTotal : null;
  const parts = [s.studyRate, s.workoutRate, s.taskRate, s.habitRate].filter((x) => x !== null);
  s.productivity = parts.length ? parts.reduce((a, b) => a + b, 0) / parts.length : 0;
  return s;
}

function alertsCard(now) {
  const overdue = db.all('recurring').filter((r) => r.isActive && r.kind === 'despesa' && new Date(r.dueDate) < U.startOfDay(now));
  const soon = D.calendarItems(U.startOfDay(now), U.addDays(U.startOfDay(now), 4))
    .filter((x) => (x.kind === 'event' && x.event.category === 'prova' && !x.event.done) || (x.kind === 'contest' && x.title.startsWith('Prova')));
  const plan = D.weeklyPlan(now);
  const items = [
    ...overdue.map((b) => ['#ef4444', `Conta atrasada: ${b.title}`, `venceu ${U.relDay(b.dueDate)}`, 'finance']),
    ...soon.map((x) => [x.color, x.title, U.capFirst(U.relDay(x.date)), x.module === 'editais' ? x.to || 'contests' : 'studies']),
    ...(plan.overBudget && plan.weeklyAllowance > 0 ? [['#f97316', 'Orçamento semanal ultrapassado', 'Veja o planejamento', 'finance']] : []),
  ];
  if (!items.length) return '';
  return `<div class="card alerts">${items.map(([c, t, sub, to]) => `<button class="al" data-act="nav" data-to="${to}"><i style="background:${c}"></i><div><b>${esc(t)}</b><small>${esc(sub)}</small></div></button>`).join('')}</div>`;
}

function todayCard(s) {
  const items = s.today.slice(0, 5);
  return `<div class="card">${head('Hoje', '📅', 'agenda', s.today.length ? `${s.today.length} item(ns)` : '')}
    ${items.length ? items.map((x) => x.kind === 'event'
      ? `<div class="li" data-act="openEvent" data-id="${x.event.id}">${x.event.recurrence === 'nenhuma'
        ? `<button class="chk" style="--c:${x.color}" data-act="toggleDone" data-id="${x.event.id}" aria-label="Concluir">${x.event.done ? icon('check', 16) : ''}</button>`
        : `<span class="dot" style="background:${x.color}"></span>`}
        <div class="grow ${x.event.done ? 'strike' : ''}"><b>${esc(x.title)}</b><small>${x.allDay ? 'Dia inteiro' : U.time(x.date)}${x.subtitle ? ' · ' + esc(x.subtitle) : ''}</small></div>${x.event.priority === 2 ? '<span class="flag">●</span>' : ''}</div>`
      : `<div class="li" data-act="nav" data-to="${x.to}"><span class="dot" style="background:${x.color}"></span><div class="grow"><b>${esc(x.title)}</b><small>${esc(x.subtitle)}</small></div></div>`).join('')
      : '<p class="muted">Nenhum compromisso hoje. Bom momento para adiantar os estudos.</p>'}
    ${s.today.length > 5 ? `<button class="link small" data-act="nav" data-to="agenda">Ver mais ${s.today.length - 5} no calendário</button>` : ''}</div>`;
}

function kpi(title, value, detail, rate, color, to) {
  return `<button class="card kpi" data-act="nav" data-to="${to}">${ring(rate, { size: 46, color, label: '' })}
    <span class="kpi-t"><b class="num">${esc(value)}</b><span>${esc(title)}</span><small>${esc(detail)}</small></span></button>`;
}

function indicators(s) {
  return `<div class="grid2">
    ${kpi('Estudo na semana', U.duration(s.studyMin), `meta ${U.duration(s.studyGoal)}`, s.studyRate, '#d946ef', 'studies')}
    ${kpi('Faculdade', U.pct(s.college), s.collegeN ? `${s.collegeN} conteúdos` : 'sem conteúdos', s.college, '#a855f7', 'studies')}
    ${kpi('Editais', U.pct(s.contest), s.contestN ? `${s.contestN} conteúdos` : 'sem conteúdos', s.contest, '#6366f1', 'contests')}
    ${kpi('Treinos na semana', `${s.workouts}/${s.workoutGoal}`, s.workouts >= s.workoutGoal ? 'meta batida 🎉' : `faltam ${s.workoutGoal - s.workouts}`, s.workoutRate, '#16a34a', 'workouts')}
  </div>`;
}

function workoutCard(s) {
  const n = s.next;
  return `<div class="grad g-fitness" data-act="nav" data-to="workouts"><div class="grow"><small>${n ? (U.sameDay(n.day, new Date()) ? 'Treino de hoje' : `Próximo treino · ${U.relDay(n.day)}`) : 'Próximo treino'}</small>
    <h2>${esc(n ? n.plan.name : 'Monte sua ficha')}</h2><small>${n ? `${(n.plan.exercises || []).length} exercícios` : 'Toque para criar seus treinos'}</small></div>
    ${n ? `<button class="btn btn-light" data-act="startPlan" data-id="${n.plan.id}">${icon('play', 16)} Iniciar</button>` : '<span class="big-emoji">🏋️</span>'}</div>`;
}

function financeCard(s) {
  const total = s.cats.reduce((a, c) => a + c.total, 0) || 1;
  const result = s.income - s.spent;
  return `<div class="card" data-act="nav" data-to="finance">${head(`Financeiro · ${U.monthYear(new Date())}`, '💰', 'finance')}
    <div class="money3"><span><small>Entradas</small><b class="green num">${U.money(s.income)}</b></span><span><small>Saídas</small><b class="red num">${U.money(s.spent)}</b></span>
      <span><small>Saldo</small><b class="num ${s.plan.balance < 0 ? 'red' : ''}">${U.money(s.plan.balance)}</b></span></div>
    ${s.cats.map((c) => `<div class="catbar"><span>${D.FIN_CATS[c.category].icon} ${D.FIN_CATS[c.category].label}</span>${progress(c.total / total, D.FIN_CATS[c.category].color)}<b class="num">${U.money(c.total)}</b></div>`).join('')}
    <small class="${s.plan.overBudget ? 'orange' : 'green'}">${s.plan.overBudget ? '⚠️ Acima do planejado para a semana' : `✓ Pode gastar ${U.money(Math.max(0, s.plan.remaining))} nesta semana`}${result ? ` · resultado do mês ${U.signedMoney(result)}` : ''}</small></div>`;
}

function billsCard(now) {
  const bills = db.all('recurring').filter((r) => r.isActive && r.kind === 'despesa' && new Date(r.dueDate) <= U.addDays(now, 7)).sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate)).slice(0, 4);
  if (!bills.length) return '';
  return `<div class="card" data-act="nav" data-to="finance">${head('Contas a vencer', '🧾', 'finance', U.money(bills.reduce((a, b) => a + b.amount, 0)))}
    ${bills.map((b) => `<div class="li"><span class="badge sm" style="--c:${D.FIN_CATS[b.category]?.color}">${D.FIN_CATS[b.category]?.icon}</span>
      <div class="grow"><b>${esc(b.title)}</b><small class="${new Date(b.dueDate) < U.startOfDay(now) ? 'red' : ''}">${new Date(b.dueDate) < U.startOfDay(now) ? 'Atrasada' : 'Vence'} ${U.relDay(b.dueDate)}</small></div><b class="num">${U.money(b.amount)}</b></div>`).join('')}</div>`;
}

function upcomingCard(now) {
  const from = U.addDays(U.startOfDay(now), 1);
  const items = D.calendarItems(from, U.addDays(from, 7)).filter((x) => x.kind !== 'workout' && x.kind !== 'bill' && !(x.event && x.event.done)).slice(0, 5);
  return `<div class="card">${head('Próximas atividades', '🗓️', 'agenda', '7 dias')}
    ${items.length ? items.map((x) => { const d = U.daysUntil(x.date, now); const to = x.kind === 'event' ? (x.module === 'estudos' ? 'studies' : x.module === 'editais' ? 'contests' : 'agenda') : x.to;
      return `<div class="li" data-act="nav" data-to="${to}"><span class="badge sm" style="--c:${x.color}">${x.icon}</span><div class="grow"><b>${esc(x.title)}</b><small>${x.allDay ? U.dayMonth(x.date) : U.dateTime(x.date)}</small></div>
        <span class="pill" style="--c:${x.color}">${d === 1 ? 'Amanhã' : `${d} dias`}</span></div>`; }).join('')
      : '<p class="muted">Nada programado para os próximos dias.</p>'}</div>`;
}

function growthCard(now) {
  const habits = db.all('habits').filter((h) => !h.archived && D.habitScheduled(h, now));
  const goals = db.all('goals').filter((g) => !g.completed).slice(0, 3);
  return `<div class="card">${head('Metas e hábitos', '🎯', 'growth')}
    ${!habits.length && !goals.length ? '<p class="muted">Crie hábitos e metas para acompanhar sua evolução.</p>' : ''}
    ${habits.length ? `<div class="chips">${habits.map((h) => { const done = D.habitDone(h, now);
      return `<button class="hchip ${done ? 'on' : ''}" style="--c:${h.color || '#22c55e'}" data-act="toggleHabit" data-id="${h.id}">${done ? '✓' : esc(h.icon || '○')} ${esc(h.name)}</button>`; }).join('')}</div>` : ''}
    ${goals.map((g) => { const p = g.target ? Math.min(1, g.current / g.target) : 0; return `<div class="goal"><div class="row-sb"><span>${esc(g.title)}</span><small class="muted">${U.pct(p)}</small></div>${progress(p, '#a855f7')}</div>`; }).join('')}</div>`;
}

function productivityCard(s) {
  const metric = (label, v, color) => `<div class="metric"><span>${esc(label)}</span>${progress(v, color)}<small>${U.pct(v)}</small></div>`;
  return `<div class="card">${head('Produtividade da semana', '⚡', 'reports')}
    <div class="prod">${ring(s.productivity, { size: 84, color: '#7c5cff', label: U.pct(s.productivity) })}
      <div class="grow">${metric('Estudo', s.studyRate, '#d946ef')}${metric('Treino', s.workoutRate, '#16a34a')}
      ${s.taskRate !== null ? metric(`Tarefas ${s.tasksDone}/${s.tasksTotal}`, s.taskRate, '#3b82f6') : ''}${s.habitRate !== null ? metric('Hábitos', s.habitRate, '#a855f7') : ''}</div></div>
    ${s.reviews ? `<button class="link small" data-act="nav" data-to="studies">↻ ${s.reviews} revisão(ões) pendente(s)</button>` : ''}</div>`;
}

function customize() {
  const current = enabledSections();
  const order = [...current, ...Object.keys(SECTIONS).filter((k) => !current.includes(k))];
  modal({
    title: 'Personalizar Home',
    body: `<p class="muted">Marque os blocos e use as setas para ordenar.</p><ul class="sortable">${order.map((k) => `<li data-k="${k}"><label class="check"><input type="checkbox" ${current.includes(k) ? 'checked' : ''}><span>${SECTIONS[k]}</span></label><span><button class="icon-btn" data-up aria-label="Subir">↑</button><button class="icon-btn" data-down aria-label="Descer">↓</button></span></li>`).join('')}</ul>`,
    footer: '<button class="btn" data-reset>Restaurar padrão</button><button class="btn btn-primary" data-ok>Salvar</button>',
    onMount: (el, close) => {
      const ul = el.querySelector('ul');
      ul.addEventListener('click', (e) => {
        const li = e.target.closest('li');
        if (e.target.closest('[data-up]') && li.previousElementSibling) ul.insertBefore(li, li.previousElementSibling);
        if (e.target.closest('[data-down]') && li.nextElementSibling) ul.insertBefore(li.nextElementSibling, li);
      });
      el.querySelector('[data-reset]').onclick = () => { db.setProfile({ homeSections: null }); close(); };
      el.querySelector('[data-ok]').onclick = () => { db.setProfile({ homeSections: [...ul.children].filter((li) => li.querySelector('input').checked).map((li) => li.dataset.k) }); close(); };
    },
  });
}

export default {
  render() {
    const now = new Date();
    const name = db.profile().name;
    const s = stats(now);
    const R = { alerts: () => alertsCard(now), today: () => todayCard(s), indicators: () => indicators(s), workout: () => workoutCard(s),
      finance: () => financeCard(s), bills: () => billsCard(now), upcoming: () => upcomingCard(now), growth: () => growthCard(now), productivity: () => productivityCard(s) };
    return `<header class="hello"><div class="grow"><small>${U.fullDate(now)}</small><h1>${U.greeting(now)}${name ? ', ' + esc(name) : ''}</h1></div>
        <div class="top-a"><button class="icon-btn round" data-act="quickAdd" aria-label="Adicionar">${icon('plus')}</button><button class="icon-btn round" data-act="nav" data-to="profile" aria-label="Perfil e ajustes">${icon('gear')}</button></div></header>
      <button class="card ask" data-act="nav" data-to="assistant"><span class="avatar sm">✨</span><span class="grow"><b>Registrar conversando</b><small>"Gastei 35 no almoço", "Tenho prova sexta às 19h"…</small></span>${icon('chevron', 16)}</button>
      <div class="stack">${enabledSections().map((k) => (R[k] ? R[k]() : '')).join('')}</div>
      <button class="btn btn-ghost wide" data-act="customize">⚙️ Personalizar Home</button>`;
  },
  actions: {
    toggleDone: (d) => { const e = db.get('events', d.id); if (e) db.update('events', e.id, { done: !e.done }); },
    openEvent: (d) => { const e = db.get('events', d.id); if (e) eventEditor(e); return false; },
    toggleHabit: (d) => { const h = db.get('habits', d.id); if (h) D.toggleHabit(h, new Date()); },
    reviewed: (d) => { const t = db.get('topics', d.id); if (t) D.markReviewed(t); },
    customize: () => { customize(); return false; },
  },
};
