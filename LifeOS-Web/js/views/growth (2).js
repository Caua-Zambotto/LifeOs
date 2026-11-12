import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { form, seg, empty, icon, section, confirmDialog } from '../ui.js';
import { bars, line, progress } from '../charts.js';

const ui = { tab: 'habitos' };
const back = (to, label) => `<button class="back" data-act="nav" data-to="${to}">${icon('back', 18)} ${esc(label)}</button>`;
const HABIT_COLORS = ['#22c55e', '#0a84ff', '#ff9f0a', '#ff375f', '#bf5af2', '#5e5ce6', '#64d2ff', '#ffd60a'];
const HABIT_ICONS = { '✅': 'Geral', '📖': 'Leitura', '💧': 'Água', '🚶': 'Caminhada', '🧠': 'Meditação', '😴': 'Sono', '🗣️': 'Idiomas', '🥗': 'Alimentação', '🏋️': 'Exercício', '✍️': 'Escrita', '🎵': 'Música', '❤️': 'Saúde' };

export function habitEditor(h = null) {
  form({
    title: h ? 'Editar hábito' : 'Novo hábito',
    values: { name: h?.name || '', icon: h?.icon || '✅', color: h?.color || HABIT_COLORS[0], weekdays: h?.weekdays || [], reminder: h?.reminder || '' },
    fields: [
      { name: 'name', label: 'Hábito', required: true, placeholder: 'Ex.: Ler 20 páginas' },
      { name: 'icon', label: 'Ícone', type: 'select', options: Object.fromEntries(Object.entries(HABIT_ICONS).map(([k, v]) => [k, `${k} ${v}`])) },
      { name: 'color', label: 'Cor', type: 'color', options: HABIT_COLORS },
      { name: 'weekdays', label: 'Dias', type: 'weekdays', help: 'Nenhum dia marcado = todos os dias.' },
      { name: 'reminder', label: 'Lembrete (horário)', type: 'time' },
    ],
    onDelete: h ? () => db.remove('habits', h.id) : null,
    onSubmit: (v) => { if (h) db.update('habits', h.id, v); else db.insert('habits', { ...v, checkins: [], archived: false }); },
  });
}

export function goalEditor(g = null) {
  form({
    title: g ? 'Editar meta' : 'Nova meta',
    values: { title: g?.title || '', horizon: g?.horizon || 'curto', area: g?.area || 'pessoal', target: g?.target ?? 100, current: g?.current ?? 0, unit: g?.unit || '%', deadline: g?.deadline && new Date(g.deadline), notes: g?.notes || '' },
    fields: [
      { name: 'title', label: 'Meta', required: true, placeholder: 'Ex.: Ler 12 livros' },
      { name: 'horizon', label: 'Prazo', type: 'select', options: D.GOAL_HORIZON },
      { name: 'area', label: 'Área', type: 'select', options: D.GOAL_AREA },
      { name: 'target', label: 'Valor alvo', type: 'decimal', required: true },
      { name: 'current', label: 'Valor atual', type: 'decimal' },
      { name: 'unit', label: 'Unidade (livros, horas, %, kg…)' },
      { name: 'deadline', label: 'Data limite', type: 'date' },
      { name: 'notes', label: 'Por que esta meta importa?', type: 'textarea', rows: 2 },
    ],
    onDelete: g ? () => { db.remove('goals', g.id); location.hash = '#/growth'; } : null,
    onSubmit: (v) => {
      if (!(v.target > 0)) return 'O valor alvo deve ser maior que zero.';
      const data = { ...v, current: Math.max(0, v.current || 0), unit: v.unit || '%', deadline: v.deadline?.toISOString() || null };
      if (g) db.update('goals', g.id, data); else db.insert('goals', { ...data, logs: [], completed: false });
    },
  });
}

function habitsTab() {
  const habits = db.all('habits').filter((h) => !h.archived);
  if (!habits.length) return empty('✅', 'Nenhum hábito', 'Ex.: ler 20 páginas, beber 2L de água, estudar inglês 30 min.', 'newHabit', 'Criar hábito');
  const now = new Date();
  const days = [...Array(7).keys()].reverse().map((i) => U.addDays(U.startOfDay(now), -i));
  const cons = [...Array(30).keys()].reverse().map((i) => {
    const d = U.addDays(U.startOfDay(now), -i);
    const sch = habits.filter((h) => D.habitScheduled(h, d));
    return { label: i % 5 === 0 ? String(d.getDate()) : '', value: sch.length ? (sch.filter((h) => D.habitDone(h, d)).length / sch.length) * 100 : 0 };
  });
  return `<div class="card"><h3>Consistência — últimos 30 dias</h3>${bars(cons, { height: 100, color: '#a855f7', format: (v) => U.num(v) + '%' })}</div>
    ${habits.map((h) => `<div class="card"><div class="row"><span class="badge" style="--c:${h.color}">${esc(h.icon)}</span>
      <div class="grow" data-act="editHabit" data-id="${h.id}"><b>${esc(h.name)}</b><small>Sequência: ${D.habitStreak(h)} · 30 dias: ${U.pct(D.habitConsistency(h, 30))}${h.reminder ? ` · 🔔 ${h.reminder}` : ''}</small></div>
      <button class="chk big" style="--c:${h.color}" data-act="habitDay" data-id="${h.id}" data-d="${U.dateKey(now)}" ${D.habitScheduled(h, now) ? '' : 'disabled'} aria-label="Marcar hoje">${D.habitDone(h, now) ? icon('check', 20) : ''}</button></div>
      <div class="hweek">${days.map((d) => `<button class="hday ${D.habitDone(h, d) ? 'on' : ''} ${D.habitScheduled(h, d) ? '' : 'off'}" style="--c:${h.color}" data-act="habitDay" data-id="${h.id}" data-d="${U.dateKey(d)}" aria-label="${U.dayMonth(d)}"><small>${U.weekdayShort(d).slice(0, 1)}</small></button>`).join('')}</div>
      <div class="row-end"><button class="link" data-act="archiveHabit" data-id="${h.id}">Arquivar</button></div></div>`).join('')}`;
}

function goalsTab() {
  const goals = db.all('goals');
  if (!goals.length) return empty('🎯', 'Nenhuma meta', 'Defina metas de curto, médio e longo prazo: pessoais, profissionais, leitura, idiomas…', 'newGoal', 'Criar meta');
  return Object.entries(D.GOAL_HORIZON).map(([k, label]) => {
    const list = goals.filter((g) => g.horizon === k);
    if (!list.length) return '';
    return `<h4 class="day-h">${label}</h4>` + list.map((g) => {
      const p = Math.min(1, g.current / g.target);
      return `<div class="card" data-act="nav" data-to="goal/${g.id}"><div class="row-sb"><b class="${g.completed ? 'strike' : ''}">${esc(g.title)}</b><b class="${g.completed ? 'green' : ''}">${U.pct(p)}</b></div>
        <small class="muted">${D.GOAL_AREA[g.area]}${g.deadline ? ' · até ' + U.shortDate(g.deadline) : ''}</small>${progress(p, g.completed ? '#22c55e' : '#a855f7')}
        <small class="muted">${U.num(g.current)} de ${U.num(g.target)} ${esc(g.unit)}</small></div>`;
    }).join('');
  }).join('');
}

export const growth = {
  render() {
    return `${back('profile', 'Perfil')}<header class="top"><h1>Desenvolvimento</h1><div class="top-a"><button class="icon-btn accent" data-act="${ui.tab === 'habitos' ? 'newHabit' : 'newGoal'}" aria-label="Adicionar">${icon('plus')}</button></div></header>
      ${seg('growthTab', { habitos: 'Hábitos', metas: 'Metas' }, ui.tab)}${ui.tab === 'habitos' ? habitsTab() : goalsTab()}`;
  },
  actions: {
    growthTab: (d) => { ui.tab = d.v; },
    newHabit: () => { habitEditor(); return false; },
    editHabit: (d) => { habitEditor(db.get('habits', d.id)); return false; },
    habitDay: (d) => { const h = db.get('habits', d.id); const day = U.fromDateKey(d.d); if (h && D.habitScheduled(h, day)) D.toggleHabit(h, day); },
    archiveHabit: async (d) => { if (await confirmDialog('Arquivar este hábito? O histórico é mantido.')) db.update('habits', d.id, { archived: true }); },
    newGoal: () => { goalEditor(); return false; },
  },
};

export const goal = {
  render(id) {
    const g = db.get('goals', id);
    if (!g) return `${back('growth', 'Desenvolvimento')}${empty('🤷', 'Meta não encontrada', '')}`;
    const logs = [...(g.logs || [])].sort((a, b) => new Date(a.date) - new Date(b.date));
    let run = 0;
    const pts = logs.map((l) => { run += l.delta; return { x: l.date, y: run }; });
    const p = Math.min(1, g.current / g.target);
    return `${back('growth', 'Desenvolvimento')}<div class="grad g-growth"><div class="grow"><h2>${esc(g.title)}</h2><small>${D.GOAL_HORIZON[g.horizon]} · ${D.GOAL_AREA[g.area]}</small>
        ${progress(p, '#fff')}<b>${U.num(g.current)} de ${U.num(g.target)} ${esc(g.unit)} · ${U.pct(p)}</b></div><button class="icon-btn light" data-act="editGoal" aria-label="Editar">${icon('edit')}</button></div>
      <form class="card" data-submit="logGoal"><h3>Registrar progresso</h3><div class="row"><input name="delta" inputmode="decimal" placeholder="Quanto avançou (${esc(g.unit)})" aria-label="Avanço"><button class="btn btn-primary">Salvar</button></div>
        <input name="note" placeholder="Observação (opcional)" maxlength="200" aria-label="Observação"></form>
      ${pts.length >= 2 ? `<div class="card">${line(pts, { color: '#a855f7' })}</div>` : ''}
      ${g.notes ? `<div class="card"><h3>Observações</h3><p>${esc(g.notes)}</p></div>` : ''}
      <label class="card check"><input type="checkbox" data-change="goalDone" ${g.completed ? 'checked' : ''}><span>Meta concluída</span></label>
      ${section('Histórico')}${[...logs].reverse().map((l) => `<div class="card row"><div class="grow"><b>${l.delta >= 0 ? '+' : ''}${U.num(l.delta)} ${esc(g.unit)}</b>${l.note ? `<small>${esc(l.note)}</small>` : ''}</div><small>${U.shortDate(l.date)}</small></div>`).join('') || '<p class="muted">Nenhum registro ainda.</p>'}`;
  },
  submit: {
    logGoal: (f) => {
      const g = db.get('goals', location.hash.split('/')[2]);
      const v = U.parseDecimal(f.delta.value);
      if (!g || !v) return;
      const current = Math.max(0, g.current + v);
      db.update('goals', g.id, { current, logs: [...(g.logs || []), { date: new Date().toISOString(), delta: v, note: f.note.value.trim().slice(0, 200) }], completed: g.completed || current >= g.target });
    },
  },
  actions: { editGoal: () => { goalEditor(db.get('goals', location.hash.split('/')[2])); return false; } },
  changes: { goalDone: (d, el) => db.update('goals', location.hash.split('/')[2], { completed: el.checked }) },
};
