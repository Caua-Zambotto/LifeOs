import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { form, seg, empty, icon, confirmDialog } from '../ui.js';

const ui = { mode: 'mes', filter: 'todos', selected: U.startOfDay(new Date()), month: U.startOfMonth(new Date()) };

export function eventEditor(event = null, defaults = {}) {
  const e = event || {};
  const cat = e.category || defaults.category || 'compromisso';
  const start = e.start ? new Date(e.start) : (() => { const d = new Date(defaults.date || new Date()); if (U.sameDay(d, new Date())) d.setHours(new Date().getHours() + 1, 0, 0, 0); else d.setHours(9, 0, 0, 0); return d; })();
  const subjects = Object.fromEntries([['', 'Nenhuma'], ...db.all('subjects').map((s) => [s.id, s.name])]);
  const contests = Object.fromEntries([['', 'Nenhum'], ...db.all('contests').map((c) => [c.id, `${c.organ} ${c.role ? '· ' + c.role : ''}`])]);
  form({
    title: event ? 'Editar evento' : 'Novo evento',
    values: {
      title: e.title || '', details: e.details || '', category: cat, priority: String(e.priority ?? (['prova', 'trabalho', 'entrega'].includes(cat) ? 2 : 1)),
      allDay: !!e.allDay, start, startDate: start, recurrence: e.recurrence || 'nenhuma', notify: e.notify ?? true,
      lead: String(e.lead ?? D.NOTIF_CATS[D.notifCatForEvent(cat)].lead), subjectId: e.subjectId || defaults.subjectId || '', contestId: e.contestId || defaults.contestId || '',
    },
    fields: [
      { name: 'title', label: 'Título', required: true, max: 200 },
      { name: 'category', label: 'Categoria', type: 'select', options: Object.fromEntries(Object.entries(D.EVENT_CATS).map(([k, v]) => [k, `${v.icon} ${v.label}`])) },
      { name: 'priority', label: 'Prioridade', type: 'select', options: D.PRIORITIES },
      { name: 'allDay', label: 'Dia inteiro', type: 'checkbox' },
      { name: 'start', label: 'Data e hora', type: 'datetime', show: (v) => !v.allDay },
      { name: 'startDate', label: 'Data', type: 'date', show: (v) => v.allDay },
      { name: 'recurrence', label: 'Repetir', type: 'select', options: D.RECURRENCES },
      { name: 'notify', label: 'Avisar (notificação)', type: 'checkbox' },
      { name: 'lead', label: 'Antecedência', type: 'select', options: D.LEAD_OPTIONS, show: (v) => v.notify },
      { name: 'subjectId', label: 'Matéria', type: 'select', options: subjects, show: () => db.all('subjects').length > 0 },
      { name: 'contestId', label: 'Concurso', type: 'select', options: contests, show: () => db.all('contests').length > 0 },
      { name: 'details', label: 'Descrição', type: 'textarea' },
    ],
    onDelete: event ? () => db.remove('events', event.id) : null,
    onSubmit: (v) => {
      const date = v.allDay ? v.startDate : v.start;
      if (!date) return 'Informe a data.';
      const data = {
        title: v.title.slice(0, 200), details: v.details, category: v.category, priority: Number(v.priority), allDay: v.allDay,
        start: (v.allDay ? U.startOfDay(date) : date).toISOString(), recurrence: v.recurrence, notify: v.notify, lead: Number(v.lead),
        subjectId: v.subjectId || null, contestId: v.contestId || null,
      };
      if (event) db.update('events', event.id, data); else db.insert('events', { ...data, done: false });
    },
  });
}

export function eventRow(o) {
  const e = o.event, c = D.EVENT_CATS[e.category] || D.EVENT_CATS.compromisso;
  const subj = e.subjectId && db.get('subjects', e.subjectId);
  return `<div class="card row ev ${e.done ? 'done' : ''}" data-act="editEvent" data-id="${e.id}">
    <span class="ev-bar" style="background:${c.color}"></span>
    ${e.recurrence === 'nenhuma' ? `<button class="chk" data-act="toggleEvent" data-id="${e.id}" aria-label="Concluir" style="--c:${c.color}">${e.done ? icon('check', 16) : ''}</button>` : ''}
    <div class="grow"><b>${c.icon} ${esc(e.title)}${e.priority === 2 ? ' <span class="flag">●</span>' : ''}</b>
    <small>${e.allDay ? 'Dia inteiro' : U.time(o.date)}${subj ? ' · ' + esc(subj.name) : ''}${e.recurrence !== 'nenhuma' ? ' · ↻' : ''}${e.notify ? ' · 🔔' : ''}</small></div></div>`;
}

// ---------- Calendário integrado (eventos + contas + treinos + concursos) ----------
const items = (from, to) => D.calendarItems(from, to, ui.filter);

function filterBar() {
  return `<div class="chips scroll-x">${Object.entries(D.CAL_MODULES).map(([k, m]) =>
    `<button class="chip ${ui.filter === k ? 'on' : ''}" style="--c:${m.color}" data-act="calFilter" data-v="${k}">${m.icon} ${m.label}</button>`).join('')}</div>`;
}

const dots = (list) => list.slice(0, 4).map((x) => `<i style="background:${x.color}"></i>`).join('');

function monthGrid() {
  const m = ui.month;
  const lead = m.getDay();
  const days = new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate();
  const marks = {};
  for (const x of items(m, U.addMonths(m, 1))) (marks[U.dateKey(x.date)] ||= []).push(x);
  let cells = '';
  for (let i = 0; i < lead; i++) cells += '<span></span>';
  for (let d = 1; d <= days; d++) {
    const date = new Date(m.getFullYear(), m.getMonth(), d);
    const k = U.dateKey(date);
    const n = (marks[k] || []).length;
    cells += `<button class="day ${U.sameDay(date, ui.selected) ? 'sel' : ''} ${U.sameDay(date, new Date()) ? 'today' : ''}" data-act="pickDay" data-d="${k}" aria-label="${U.fullDate(date)}, ${n} item(ns)">${d}<span class="dots">${dots(marks[k] || [])}</span></button>`;
  }
  return `<div class="card cal">
    <div class="cal-h"><button class="icon-btn" data-act="month" data-n="-1" aria-label="Mês anterior">${icon('back')}</button><b>${U.monthYear(m)}</b><button class="icon-btn" data-act="month" data-n="1" aria-label="Próximo mês">${icon('chevron')}</button></div>
    <div class="cal-g">${['D', 'S', 'T', 'Q', 'Q', 'S', 'S'].map((x) => `<span class="wd-h">${x}</span>`).join('')}${cells}</div></div>`;
}

function weekStrip() {
  const s = U.startOfWeek(ui.selected);
  const all = items(s, U.addDays(s, 7));
  return `<div class="cal-h"><button class="icon-btn" data-act="week" data-n="-7" aria-label="Semana anterior">${icon('back')}</button><b>${U.dayMonth(s)} – ${U.dayMonth(U.addDays(s, 6))}</b><button class="icon-btn" data-act="week" data-n="7" aria-label="Próxima semana">${icon('chevron')}</button></div>
  <div class="week">${[...Array(7).keys()].map((i) => {
    const d = U.addDays(s, i);
    const list = all.filter((x) => U.sameDay(x.date, d));
    return `<button class="wday ${U.sameDay(d, ui.selected) ? 'sel' : ''}" data-act="pickDay" data-d="${U.dateKey(d)}"><small>${U.weekdayShort(d)}</small><b>${d.getDate()}</b><span class="dots">${dots(list)}</span></button>`;
  }).join('')}</div>`;
}

function dayHeader() {
  const d = ui.selected;
  return `<div class="card dayhead"><button class="icon-btn" data-act="week" data-n="-1" aria-label="Dia anterior">${icon('back')}</button>
    <div><small>${U.weekdayShort(d)}</small><b>${d.getDate()}</b><small>${U.monthYear(d)}</small></div>
    <button class="icon-btn" data-act="week" data-n="1" aria-label="Próximo dia">${icon('chevron')}</button></div>`;
}

function moduleRow(x) {
  const m = D.CAL_MODULES[x.module];
  return `<div class="card row" data-act="nav" data-to="${x.to}"><span class="badge" style="--c:${x.color}">${x.icon}</span>
    <div class="grow"><b>${esc(x.title)}</b><small>${[x.allDay ? 'Dia inteiro' : U.time(x.date), x.subtitle].filter(Boolean).map(esc).join(' · ')}</small></div>
    <span class="pill" style="--c:${m.color}">${m.label}</span></div>`;
}

function dayList() {
  const sel = ui.selected;
  const list = items(sel, U.addDays(sel, 1));
  const label = D.CAL_MODULES[ui.filter].label;
  return `<div class="sec"><h3>${ui.mode === 'dia' ? 'Programação' : U.fullDate(sel)}</h3>${list.length ? `<small class="muted">${list.length} item(ns)</small>` : ''}</div>
  ${list.length ? list.map((x) => (x.kind === 'event' ? eventRow({ event: x.event, date: x.date }) : moduleRow(x))).join('')
    : empty('🗓️', 'Dia livre', ui.filter === 'todos' ? 'Nenhum compromisso neste dia.' : `Nada de ${label} neste dia.`, 'newEvent', 'Adicionar evento')}`;
}

export default {
  title: 'Calendário',
  render() {
    return `<header class="top"><h1>Calendário</h1><div class="top-a"><button class="btn btn-sm" data-act="today">Hoje</button><button class="icon-btn accent" data-act="newEvent" aria-label="Novo evento">${icon('plus')}</button></div></header>
      ${seg('mode', { mes: 'Mês', semana: 'Semana', dia: 'Dia' }, ui.mode)}
      ${filterBar()}
      ${ui.mode === 'mes' ? monthGrid() : ui.mode === 'semana' ? weekStrip() : dayHeader()}
      ${dayList()}`;
  },
  actions: {
    mode: (d) => { ui.mode = d.v; },
    calFilter: (d) => { ui.filter = d.v; },
    month: (d) => { ui.month = U.addMonths(ui.month, Number(d.n)); },
    week: (d) => { ui.selected = U.addDays(ui.selected, Number(d.n)); ui.month = U.startOfMonth(ui.selected); },
    pickDay: (d) => { ui.selected = U.fromDateKey(d.d); },
    today: () => { ui.selected = U.startOfDay(new Date()); ui.month = U.startOfMonth(new Date()); },
    newEvent: () => { eventEditor(null, { date: ui.selected }); return false; },
    editEvent: (d) => { const e = db.get('events', d.id); if (e) eventEditor(e); return false; },
    toggleEvent: (d, el, ev) => { ev.stopPropagation(); const e = db.get('events', d.id); if (e) db.update('events', e.id, { done: !e.done }); },
  },
};
