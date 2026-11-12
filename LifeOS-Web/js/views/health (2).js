import * as db from '../store.js';
import * as D from '../domain.js';
import * as N from '../nlp.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { form, seg, empty, icon, section, stat, confirmDialog, modal, toast, pickFile } from '../ui.js';
import { bars, line, ring } from '../charts.js';
import { liveWorkout } from './live.js';

const ui = { workoutTab: 'divisao', exercise: '', bodyField: 'weight', foodTab: 'estoque', recipeSearch: '' };
const back = (to, label) => `<button class="back" data-act="nav" data-to="${to}">${icon('back', 18)} ${esc(label)}</button>`;
const currentId = () => location.hash.split('/')[2];

// ---------- Treinos ----------
function exerciseList(rows) {
  return `<div class="ex-list">${rows.map((e, i) => `<div class="ex" data-i="${i}">
    <input data-k="name" placeholder="Exercício" value="${esc(e.name || '')}" aria-label="Exercício">
    <input data-k="sets" type="number" min="1" value="${e.sets ?? 3}" aria-label="Séries" title="Séries">
    <span>×</span><input data-k="reps" inputmode="numeric" maxlength="30" value="${e.repsList?.length ? e.repsList.join('-') : (e.reps ?? 10)}" aria-label="Repetições (ou pirâmide, ex.: 15-12-10-8)" title="Repetições — para pirâmide use 15-12-10-8">
    <input data-k="load" inputmode="decimal" placeholder="kg" value="${e.load ? U.num(e.load) : ''}" aria-label="Carga" title="Carga (kg)">
    <input data-k="rest" type="number" min="0" step="15" placeholder="desc." value="${e.rest ?? 60}" aria-label="Descanso (segundos)" title="Descanso (s)">
    <button type="button" class="icon-btn" data-rm aria-label="Remover">${icon('close', 16)}</button>
    <input data-k="video" class="ex-video" type="url" inputmode="url" maxlength="500" placeholder="🎬 Link do vídeo da execução (opcional)" value="${esc(e.video || '')}" aria-label="Link do vídeo da execução"></div>`).join('')}</div>
    <button type="button" class="btn btn-sm" data-add-ex>+ Exercício</button>`;
}
function readExercises(el) {
  return [...el.querySelectorAll('.ex')].map((r) => ({
    name: r.querySelector('[data-k=name]').value.trim(), sets: parseInt(r.querySelector('[data-k=sets]').value, 10) || 3,
    ...repsOf(r.querySelector('[data-k=reps]').value), load: U.parseDecimal(r.querySelector('[data-k=load]').value) || 0,
    rest: (() => { const n = parseInt(r.querySelector('[data-k=rest]')?.value, 10); return Number.isFinite(n) && n >= 0 ? n : 60; })(),
    video: U.safeUrl(r.querySelector('[data-k=video]')?.value),
  })).filter((x) => x.name);
}
/** "12" → 12 repetições; "15-12-10-8" → pirâmide (uma quantidade por série). */
export function repsOf(text) {
  const list = String(text || '').split(/[^0-9]+/).map((n) => parseInt(n, 10)).filter((n) => n > 0 && n < 1000).slice(0, 20);
  return list.length > 1 ? { reps: list[0], repsList: list } : { reps: list[0] || 10, repsList: undefined };
}
export const repsLabel = (e) => (e.repsList?.length ? e.repsList.join('-') : String(e.reps ?? ''));
const badVideo = (el) => [...el.querySelectorAll('[data-k=video]')].some((i) => i.value.trim() && !U.safeUrl(i.value))
  ? 'Um dos links de vídeo não é válido. Cole o endereço completo (ex.: https://youtu.be/...).' : null;
function bindExercises(el) {
  el.addEventListener('click', (e) => {
    if (e.target.closest('[data-rm]')) e.target.closest('.ex').remove();
    if (e.target.closest('[data-add-ex]')) {
      const list = el.querySelector('.ex-list');
      const tmp = document.createElement('div'); tmp.innerHTML = exerciseList([{}]);
      list.appendChild(tmp.querySelector('.ex'));
    }
  });
}

/** Lê um arquivo de fichas ({ format: 'lifeos-fichas', plans: [...] }) e valida cada campo. */
export function parsePlansFile(text) {
  let data;
  try { data = JSON.parse(text); } catch { throw new Error('O arquivo não é um JSON válido.'); }
  if (data?.format !== 'lifeos-fichas' || !Array.isArray(data.plans)) throw new Error('Este arquivo não é um arquivo de fichas do LifeOS.');
  const str = (v, max) => String(v ?? '').trim().slice(0, max);
  const int = (v, min, max, def) => { const n = parseInt(v, 10); return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : def; };
  return data.plans.slice(0, 50).map((p) => ({
    name: str(p.name, 80),
    weekdays: [...new Set((Array.isArray(p.weekdays) ? p.weekdays : []).map((d) => parseInt(d, 10)).filter((d) => d >= 0 && d <= 6))],
    reminder: /^\d{2}:\d{2}$/.test(p.reminder || '') ? p.reminder : '',
    exercises: (Array.isArray(p.exercises) ? p.exercises : []).slice(0, 40).map((e) => {
      const r = repsOf(Array.isArray(e.repsList) && e.repsList.length > 1 ? e.repsList.join('-') : e.reps);
      return { name: str(e.name, 80), sets: int(e.sets, 1, 50, 3), ...r, load: Math.max(0, Number(e.load) || 0), rest: int(e.rest, 0, 900, 60), video: U.safeUrl(e.video) };
    }).filter((e) => e.name),
  })).filter((p) => p.name && p.exercises.length);
}

async function importPlans() {
  const file = await pickFile('.json,application/json');
  if (!file) return;
  if (file.size > 1024 * 1024) { toast('Arquivo grande demais.'); return; }
  let plans;
  try { plans = parsePlansFile(await file.text()); } catch (e) { toast(e.message); return; }
  if (!plans.length) { toast('Nenhuma ficha encontrada no arquivo.'); return; }
  const existing = new Set(db.all('workoutPlans').map((p) => U.fold(p.name)));
  const fresh = plans.filter((p) => !existing.has(U.fold(p.name)));
  const skipped = plans.length - fresh.length;
  if (!fresh.length) { toast('Todas as fichas deste arquivo já existem.'); return; }
  const list = fresh.map((p) => `• ${p.name} (${p.exercises.length} exercícios)`).join('\n');
  const note = skipped ? `\n\n${skipped} já existente(s) serão ignorada(s).` : '';
  if (!(await confirmDialog(`Adicionar ${fresh.length} ficha(s)?\n${list}${note}`, { confirmLabel: 'Adicionar' }))) return;
  for (const p of fresh) db.insert('workoutPlans', p);
  toast(`${fresh.length} ficha(s) adicionada(s). 💪`);
}

function planEditor(p = null) {
  const f = form({
    title: p ? 'Editar ficha' : 'Nova ficha de treino',
    values: { name: p?.name || '', weekdays: p?.weekdays || [], reminder: p?.reminder || '' },
    fields: [
      { name: 'name', label: 'Nome', required: true, placeholder: 'Ex.: A – Peito e Tríceps' },
      { name: 'weekdays', label: 'Dias da semana', type: 'weekdays' },
      { name: 'reminder', label: 'Lembrete (horário)', type: 'time' },
      { name: 'ex', type: 'html', html: `<div class="field"><span class="lbl">Exercícios (séries × repetições · carga · descanso em segundos)</span>${exerciseList(p?.exercises?.length ? p.exercises : [{}])}</div>` },
    ],
    onDelete: p ? () => db.remove('workoutPlans', p.id) : null,
    onSubmit: (v) => {
      if (badVideo(f.el)) return badVideo(f.el);
      const data = { name: v.name, weekdays: v.weekdays, reminder: v.reminder || '', exercises: readExercises(f.el) };
      if (p) db.update('workoutPlans', p.id, data); else db.insert('workoutPlans', data);
    },
  });
  bindExercises(f.el);
}

export function sessionEditor(s = null, plan = null) {
  const entries = s?.entries || plan?.exercises || [{}];
  const f = form({
    title: s ? 'Editar treino' : 'Registrar treino',
    values: { title: s?.title || plan?.name || '', date: s ? new Date(s.date) : new Date(), minutes: s?.minutes ?? 60, notes: s?.notes || '', updatePlan: true },
    fields: [
      { name: 'title', label: 'Treino', required: true, placeholder: 'Ex.: Pernas' },
      { name: 'date', label: 'Data', type: 'date' },
      { name: 'minutes', label: 'Duração (min)', type: 'int', min: 0 },
      { name: 'ex', type: 'html', html: `<div class="field"><span class="lbl">Exercícios e cargas</span>${exerciseList(entries)}</div>` },
      ...(plan ? [{ name: 'updatePlan', label: 'Atualizar cargas da ficha', type: 'checkbox' }] : []),
      { name: 'notes', label: 'Observações', type: 'textarea', rows: 2 },
    ],
    onDelete: s ? () => db.remove('workoutSessions', s.id) : null,
    onSubmit: (v) => {
      if (badVideo(f.el)) return badVideo(f.el);
      const ex = readExercises(f.el);
      const data = { title: v.title, date: (v.date || new Date()).toISOString(), minutes: v.minutes || 0, notes: v.notes, entries: ex, muscleGroups: N.muscleGroupsIn(U.fold(v.title)) };
      if (s) db.update('workoutSessions', s.id, data); else db.insert('workoutSessions', { ...data, planId: plan?.id || null });
      if (plan && v.updatePlan) db.update('workoutPlans', plan.id, { exercises: plan.exercises.map((pe) => { const n = ex.find((x) => x.name === pe.name); return n ? { ...pe, sets: n.sets, reps: n.reps, repsList: n.repsList, load: n.load } : pe; }) });
    },
  });
  bindExercises(f.el);
}

function workoutGoalEditor() {
  form({
    title: 'Meta semanal de treinos', values: { goal: db.profile().weeklyWorkoutGoal || 4 },
    intro: '<p class="muted small">Usada em Treino e no indicador de produtividade da Home.</p>',
    fields: [{ name: 'goal', label: 'Treinos por semana', type: 'int', min: 1, maxv: 14, required: true }],
    onSubmit: (v) => { if (!(v.goal >= 1 && v.goal <= 14)) return 'Escolha entre 1 e 14.'; db.setProfile({ weeklyWorkoutGoal: v.goal }); },
  });
}

function trainingHero() {
  const next = D.nextWorkout();
  const week = D.workoutsInWeek();
  const goal = Math.max(1, db.profile().weeklyWorkoutGoal || 4);
  const p = next?.plan;
  const label = next ? (U.sameDay(next.day, new Date()) ? 'Treino de hoje' : `Próximo treino · ${U.relDay(next.day)}`) : 'Nenhuma ficha programada';
  return `<div class="grad g-fitness hero-col"><div class="row-sb wfull"><div class="grow"><small>${label}</small><h2>${esc(p ? p.name : 'Treino livre')}</h2>
      ${p ? `<small>${(p.exercises || []).length} exercícios · ${(p.exercises || []).reduce((a, e) => a + (e.sets || 0), 0)} séries</small>` : ''}</div>
      <button class="ring-btn" data-act="workoutGoal" aria-label="Meta semanal">${ring(week / goal, { size: 62, color: '#fff', label: `${week}/${goal}` })}<small>semana</small></button></div>
    <button class="btn btn-light wide" data-act="${p ? 'startPlan' : 'startFree'}" data-id="${p ? p.id : ''}">${icon('play', 16)} Iniciar treino</button></div>`;
}

function trainingShortcuts() {
  const last = [...db.all('body')].filter((m) => m.weight).sort((a, b) => new Date(b.date) - new Date(a.date))[0];
  return `<div class="grid2"><button class="card row" data-act="nav" data-to="body"><span class="badge" style="--c:#f97316">⚖️</span><span class="grow"><b>Corpo</b><small>${last ? `${U.num(last.weight)} kg` : 'Peso e medidas'}</small></span></button>
    <button class="card row" data-act="nav" data-to="food"><span class="badge" style="--c:#f59e0b">🍽️</span><span class="grow"><b>Alimentação</b><small>Estoque e receitas</small></span></button></div>`;
}

export const workouts = {
  render() {
    const plans = db.all('workoutPlans');
    const sessions = [...db.all('workoutSessions')].sort((a, b) => new Date(b.date) - new Date(a.date));
    let body;
    if (ui.workoutTab === 'divisao') {
      body = plans.length ? plans.map((p) => `<div class="card"><div class="row-sb"><div><b>${esc(p.name)}</b><small class="muted block">${(p.weekdays || []).sort().map((d) => D.WEEKDAY_NAMES[d]).join(' · ') || 'Sem dias definidos'}${p.reminder ? ` · 🔔 ${p.reminder}` : ''}</small></div>
          <button class="icon-btn" data-act="editPlan" data-id="${p.id}" aria-label="Editar">${icon('edit')}</button></div>
          ${(p.exercises || []).map((e) => `<div class="row-sb small"><span>${esc(e.name)} ${U.videoLink(e.video)}</span><span class="muted">${e.sets}×${repsLabel(e)}${e.load ? ` · ${U.num(e.load)} kg` : ''}</span></div>`).join('')}
          <div class="btn-row"><button class="btn btn-primary" data-act="startPlan" data-id="${p.id}">${icon('play', 16)} Iniciar</button><button class="btn" data-act="logPlan" data-id="${p.id}">Registrar treino passado</button></div></div>`).join('')
        : empty('🏋️', 'Monte sua ficha', 'Ex.: A – Peito e Tríceps (seg/qui), B – Costas e Bíceps (ter/sex), C – Pernas (qua/sáb).', 'newPlan', 'Criar ficha');
    } else if (ui.workoutTab === 'historico') {
      body = sessions.slice(0, 80).map((s) => `<div class="card row" data-act="editSession" data-id="${s.id}"><span class="badge" style="--c:#22c55e">🏋️</span>
        <div class="grow"><b>${esc(s.title)}</b><small>${U.fullDate(s.date)}${s.minutes ? ' · ' + U.duration(s.minutes) : ''}${s.entries?.length ? ` · ${s.entries.length} exercícios` : ''}</small></div></div>`).join('')
        || '<p class="muted">Nenhum treino registrado. Diga ao assistente: "hoje treinei pernas".</p>';
    } else {
      const weeks = [...Array(12).keys()].reverse().map((i) => U.addDays(U.startOfWeek(new Date()), -7 * i));
      const freq = weeks.map((w) => ({ label: U.dayMonth(w), value: sessions.filter((s) => new Date(s.date) >= w && new Date(s.date) < U.addDays(w, 7)).length }));
      const names = [...new Set(sessions.flatMap((s) => (s.entries || []).map((e) => e.name)))].sort();
      const chosen = names.includes(ui.exercise) ? ui.exercise : names[0];
      const loads = sessions.map((s) => ({ x: s.date, y: Math.max(0, ...(s.entries || []).filter((e) => e.name === chosen).map((e) => e.load)) })).filter((p) => p.y > 0).sort((a, b) => new Date(a.x) - new Date(b.x));
      const diff = loads.length >= 2 ? loads[loads.length - 1].y - loads[0].y : null;
      body = `<div class="card"><h3>Frequência semanal</h3>${bars(freq, { height: 130, color: '#22c55e' })}<small class="muted">Média: ${U.num(freq.reduce((a, f) => a + f.value, 0) / 12)} treinos/semana nas últimas 12 semanas</small></div>
        <div class="card"><h3>Evolução de carga</h3>${names.length ? `<select data-change="exercise" aria-label="Exercício">${names.map((n) => `<option ${n === chosen ? 'selected' : ''}>${esc(n)}</option>`).join('')}</select>
          ${line(loads, { color: '#22c55e', format: (v) => U.num(v) + ' kg' }) || '<p class="muted">Registre ao menos 2 treinos com este exercício.</p>'}
          ${diff !== null ? `<small class="${diff >= 0 ? 'green' : 'orange'}">Variação: ${diff >= 0 ? '+' : ''}${U.num(diff)} kg (${U.pct(diff / loads[0].y)})</small>` : ''}` : '<p class="muted">Registre treinos com exercícios e cargas para comparar.</p>'}</div>`;
    }
    return `<header class="top"><h1>Treino</h1><div class="top-a"><button class="btn btn-sm" data-act="importPlans" title="Importar fichas de um arquivo">Importar</button><button class="btn btn-sm" data-act="workoutGoal">Meta</button><button class="icon-btn accent" data-act="newPlan" aria-label="Nova ficha">${icon('plus')}</button></div></header>
      ${trainingHero()}${trainingShortcuts()}
      ${seg('workoutTab', { divisao: 'Fichas', historico: 'Histórico', evolucao: 'Evolução' }, ui.workoutTab)}${body}`;
  },
  actions: {
    workoutTab: (d) => { ui.workoutTab = d.v; },
    newPlan: () => { planEditor(); return false; },
    importPlans: () => { importPlans(); return false; },
    editPlan: (d) => { planEditor(db.get('workoutPlans', d.id)); return false; },
    logPlan: (d) => { sessionEditor(null, db.get('workoutPlans', d.id)); return false; },
    logFree: () => { sessionEditor(); return false; },
    startPlan: (d) => { liveWorkout(db.get('workoutPlans', d.id)); return false; },
    startFree: () => { liveWorkout(null); return false; },
    workoutGoal: () => { workoutGoalEditor(); return false; },
    editSession: (d) => { sessionEditor(db.get('workoutSessions', d.id)); return false; },
  },
  changes: { exercise: (d, el) => { ui.exercise = el.value; } },
};

// ---------- Corpo ----------
const FIELDS = { weight: 'Peso', waist: 'Cintura', arm: 'Braço', chest: 'Peito', leg: 'Perna', hip: 'Quadril', bodyFat: 'Gordura %' };

export function bodyEditor() {
  form({
    title: 'Registrar medidas', values: { date: new Date() },
    fields: [
      { name: 'date', label: 'Data', type: 'date' }, { name: 'weight', label: 'Peso (kg)', type: 'decimal' },
      { name: 'waist', label: 'Cintura (cm)', type: 'decimal' }, { name: 'arm', label: 'Braço (cm)', type: 'decimal' }, { name: 'chest', label: 'Peito (cm)', type: 'decimal' },
      { name: 'leg', label: 'Perna/coxa (cm)', type: 'decimal' }, { name: 'hip', label: 'Quadril (cm)', type: 'decimal' }, { name: 'bodyFat', label: 'Gordura corporal (%)', type: 'decimal' },
      { name: 'note', label: 'Observação' },
    ],
    onSubmit: (v) => {
      const ok = (x, a, b) => (x !== null && x >= a && x <= b ? x : null);
      const m = { date: (v.date || new Date()).toISOString(), weight: ok(v.weight, 20, 400), waist: ok(v.waist, 10, 250), arm: ok(v.arm, 10, 250), chest: ok(v.chest, 10, 250), leg: ok(v.leg, 10, 250), hip: ok(v.hip, 10, 250), bodyFat: ok(v.bodyFat, 2, 70), note: v.note };
      if (!Object.keys(FIELDS).some((k) => m[k] !== null)) return 'Informe pelo menos uma medida válida.';
      db.insert('body', m);
    },
  });
}

export const body = {
  render() {
    const items = [...db.all('body')].sort((a, b) => new Date(a.date) - new Date(b.date));
    const p = db.profile();
    const last = [...items].reverse().find((m) => m.weight)?.weight;
    const bmi = last && p.heightCm ? last / (p.heightCm / 100) ** 2 : null;
    const series = items.filter((m) => m[ui.bodyField]).map((m) => ({ x: m.date, y: m[ui.bodyField] }));
    return `${back('workouts', 'Treino')}<header class="top"><h1>Corpo</h1><div class="top-a"><button class="btn btn-sm" data-act="bodyGoal">Altura e meta</button><button class="icon-btn accent" data-act="newBody" aria-label="Registrar">${icon('plus')}</button></div></header>
      <div class="grid3">${stat('Peso atual', last ? U.num(last) + ' kg' : '–', '⚖️', '#f97316')}${stat('IMC', bmi ? U.num(bmi) : '–', '❤️', '#ec4899')}${stat('Meta', p.targetWeight ? U.num(p.targetWeight) + ' kg' : '–', '🎯', '#22c55e')}</div>
      <div class="card"><div class="chips">${Object.entries(FIELDS).map(([k, l]) => `<button class="chip ${k === ui.bodyField ? 'on' : ''}" data-act="bodyField" data-v="${k}">${l}</button>`).join('')}</div>
        ${line(series, { height: 180, color: '#f97316', target: ui.bodyField === 'weight' ? p.targetWeight || null : null, format: (v) => U.num(v) }) || '<p class="muted">Registre ao menos duas medições para ver o gráfico.</p>'}
        ${series.length >= 2 ? `<small class="muted">Desde ${U.shortDate(series[0].x)}: ${series.at(-1).y >= series[0].y ? '+' : ''}${U.num(series.at(-1).y - series[0].y)}</small>` : ''}</div>
      ${section('Histórico')}
      ${[...items].reverse().map((m) => `<div class="card row"><div class="grow"><b>${U.fullDate(m.date)}</b><small>${Object.entries(FIELDS).filter(([k]) => m[k]).map(([k, l]) => `${l}: ${U.num(m[k])}`).join(' · ')}</small></div>
        <button class="icon-btn" data-act="delBody" data-id="${m.id}" aria-label="Excluir">${icon('trash', 16)}</button></div>`).join('') || empty('⚖️', 'Sem medições', 'Diga "meu peso é 78 kg" ou toque em +.')}`;
  },
  actions: {
    newBody: () => { bodyEditor(); return false; },
    bodyField: (d) => { ui.bodyField = d.v; },
    delBody: async (d) => { if (await confirmDialog('Excluir esta medição?', { danger: true, confirmLabel: 'Excluir' })) db.remove('body', d.id); },
    bodyGoal: () => {
      const p = db.profile();
      form({ title: 'Altura e meta', values: { heightCm: p.heightCm, targetWeight: p.targetWeight },
        fields: [{ name: 'heightCm', label: 'Altura (cm)', type: 'decimal' }, { name: 'targetWeight', label: 'Peso meta (kg)', type: 'decimal' }],
        onSubmit: (v) => db.setProfile({ heightCm: v.heightCm >= 80 && v.heightCm <= 250 ? v.heightCm : null, targetWeight: v.targetWeight >= 20 && v.targetWeight <= 400 ? v.targetWeight : null }) });
      return false;
    },
  },
};

// ---------- Alimentação ----------
export function pantryEditor(item = null) {
  form({
    title: item ? 'Editar alimento' : 'Adicionar alimento',
    values: { name: item?.name || '', quantity: item?.quantity ?? 1, unit: item?.unit || 'un', expiresAt: item?.expiresAt && new Date(item.expiresAt) },
    fields: [{ name: 'name', label: 'Alimento', required: true, list: D.COMMON_FOODS }, { name: 'quantity', label: 'Quantidade', type: 'decimal' },
      { name: 'unit', label: 'Unidade', type: 'select', options: { un: 'unidade', kg: 'kg', g: 'g', L: 'litro', ml: 'ml', pct: 'pacote', cx: 'caixa', lata: 'lata' } },
      { name: 'expiresAt', label: 'Validade (opcional)', type: 'date' }],
    onDelete: item ? () => db.remove('pantry', item.id) : null,
    onSubmit: (v) => {
      const data = { name: U.capFirst(v.name), quantity: Math.max(0, v.quantity ?? 1), unit: v.unit, expiresAt: v.expiresAt?.toISOString() || null };
      if (item) db.update('pantry', item.id, data); else db.insert('pantry', data);
    },
  });
}

/** Foto das compras + seleção rápida dos itens (identificação automática não disponível na versão web). */
export function scanGroceries() {
  const chips = D.COMMON_FOODS.map((n) => `<label class="chip-check"><input type="checkbox" value="${esc(n)}"><span>${esc(n)}</span></label>`).join('');
  modal({
    title: 'Registrar compras',
    body: `<p class="muted small">Tire uma foto para consultar enquanto marca os itens. A foto fica só na tela e não é salva.</p>
      <label class="btn wide"><input type="file" accept="image/*" capture="environment" hidden data-photo>📷 Fotografar ou escolher imagem</label>
      <img class="preview hidden" alt="Foto das compras">
      <h4>Toque nos itens comprados</h4><div class="chips">${chips}</div>
      <div class="field"><label class="lbl">Outros itens (separe por vírgula)</label><textarea data-other rows="2" placeholder="Ex.: 2 kg de arroz, 12 ovos, iogurte"></textarea></div>`,
    footer: '<button class="btn" data-close>Cancelar</button><button class="btn btn-primary" data-ok>Adicionar ao estoque</button>',
    onMount: (el, close) => {
      let url = null;
      el.querySelector('[data-photo]').onchange = (e) => {
        const f = e.target.files?.[0]; if (!f) return;
        if (url) URL.revokeObjectURL(url);
        url = URL.createObjectURL(f);
        const img = el.querySelector('.preview'); img.src = url; img.classList.remove('hidden');
      };
      el.querySelector('[data-ok]').onclick = () => {
        const items = [...el.querySelectorAll('.chip-check input:checked')].map((i) => ({ name: i.value, quantity: 1, unit: 'un' }))
          .concat(N.splitItems(el.querySelector('[data-other]').value));
        if (!items.length) return;
        for (const it of items) {
          const same = db.all('pantry').find((p) => U.fold(p.name) === U.fold(it.name) && p.unit === it.unit);
          if (same) db.update('pantry', same.id, { quantity: same.quantity + it.quantity });
          else db.insert('pantry', { name: it.name, quantity: it.quantity, unit: it.unit, expiresAt: null });
        }
        if (url) URL.revokeObjectURL(url);
        toast(`${items.length} item(ns) adicionados ao estoque.`);
        close();
      };
    },
  });
}

function recipeEditor() {
  form({
    title: 'Nova receita', values: { minutes: 20, servings: 1 },
    fields: [{ name: 'name', label: 'Nome', required: true }, { name: 'minutes', label: 'Tempo (min)', type: 'int', min: 1 }, { name: 'servings', label: 'Porções', type: 'int', min: 1 },
      { name: 'ingredients', label: 'Ingredientes (um por linha: nome - quantidade)', type: 'textarea', rows: 5 }, { name: 'steps', label: 'Modo de preparo (um passo por linha)', type: 'textarea', rows: 5 }],
    onSubmit: (v) => {
      const ingredients = (v.ingredients || '').split('\n').map((l) => l.trim()).filter(Boolean).map((l) => { const [n, ...q] = l.split(' - '); return { name: n.trim(), qty: q.join(' - ').trim() }; });
      db.insert('recipes', { name: v.name, minutes: v.minutes || 20, servings: v.servings || 1, ingredients, steps: (v.steps || '').split('\n').map((s) => s.trim()).filter(Boolean), tags: [] });
    },
  });
}

export const food = {
  render() {
    const pantry = [...db.all('pantry')].sort((a, b) => a.name.localeCompare(b.name));
    const recipes = D.allRecipes();
    const favs = db.profile().favorites || [];
    let bodyHtml;
    if (ui.foodTab === 'estoque') {
      bodyHtml = `<div class="grad g-food" data-act="scan"><span class="big-emoji">🛒</span><div class="grow"><h2>Registrar compras</h2><small>Foto + seleção rápida dos itens</small></div></div>
        ${pantry.map((p) => `<div class="card row"><div class="grow" data-act="editPantry" data-id="${p.id}"><b>${esc(p.name)}</b>${p.expiresAt ? `<small class="${new Date(p.expiresAt) < U.addDays(new Date(), 3) ? 'red' : 'muted'}">Validade ${U.relDay(p.expiresAt)}</small>` : ''}</div>
          <button class="icon-btn" data-act="qty" data-id="${p.id}" data-n="-1" aria-label="Diminuir">−</button><b class="qty">${U.num(p.quantity)} ${esc(p.unit)}</b><button class="icon-btn" data-act="qty" data-id="${p.id}" data-n="1" aria-label="Aumentar">+</button></div>`).join('')
        || empty('🧺', 'Estoque vazio', 'Diga "comprei ovos, arroz e frango" ou registre suas compras.', 'scan', 'Registrar compras')}`;
    } else if (ui.foodTab === 'receitas') {
      const sug = D.suggestRecipes(recipes, pantry).slice(0, 6);
      const q = U.fold(ui.recipeSearch);
      const list = recipes.filter((r) => !q || U.fold(r.name).includes(q) || (r.tags || []).some((t) => U.fold(t).includes(q)));
      bodyHtml = `${section('Com o que você tem em casa')}
        ${sug.map((s) => `<div class="card" data-act="nav" data-to="recipe/${encodeURIComponent(s.recipe.id)}"><div class="row-sb"><b>${esc(s.recipe.name)}</b><b class="green">${U.pct(s.score)}</b></div>
          <small class="muted">${s.recipe.minutes} min · ${s.have.length} de ${s.have.length + s.missing.length} ingredientes em casa</small>${s.missing.length ? `<small class="orange block">Falta: ${esc(s.missing.join(', '))}</small>` : ''}</div>`).join('')
          || `<p class="muted">${pantry.length ? 'Nenhuma receita combina com o estoque atual.' : 'Adicione alimentos ao estoque para receber sugestões.'}</p>`}
        ${section('Catálogo', 'newRecipe', '+ Receita')}
        <input class="search" data-keep id="recipeSearch" data-input="recipeSearch" placeholder="Buscar receita ou tag" value="${esc(ui.recipeSearch)}">
        ${list.map((r) => `<div class="card row" data-act="nav" data-to="recipe/${encodeURIComponent(r.id)}"><div class="grow"><b>${esc(r.name)}</b><small>${r.minutes} min${r.kcal ? ` · ~${r.kcal} kcal` : ''}${r.tags?.length ? ' · ' + esc(r.tags.join(', ')) : ''}</small></div>${favs.includes(r.id) ? '❤️' : ''}</div>`).join('')}`;
    } else {
      const logs = [...db.all('cookLogs')].sort((a, b) => new Date(b.date) - new Date(a.date));
      const favList = recipes.filter((r) => favs.includes(r.id));
      bodyHtml = `${favList.length ? section('Favoritas') + favList.map((r) => `<div class="card row" data-act="nav" data-to="recipe/${encodeURIComponent(r.id)}">❤️ <b class="grow">${esc(r.name)}</b></div>`).join('') : ''}
        ${section('Receitas preparadas')}${logs.map((l) => `<div class="card row"><b class="grow">${esc(l.name)}</b><small>${U.shortDate(l.date)}</small></div>`).join('') || '<p class="muted">Toque em "Preparei hoje" em uma receita para registrar.</p>'}`;
    }
    return `${back('workouts', 'Treino')}<header class="top"><h1>Minha alimentação</h1><div class="top-a"><button class="icon-btn accent" data-act="addPantry" aria-label="Adicionar alimento">${icon('plus')}</button></div></header>
      ${seg('foodTab', { estoque: 'Estoque', receitas: 'Receitas', historico: 'Histórico' }, ui.foodTab)}${bodyHtml}`;
  },
  actions: {
    foodTab: (d) => { ui.foodTab = d.v; },
    scan: () => { scanGroceries(); return false; },
    addPantry: () => { pantryEditor(); return false; },
    editPantry: (d) => { pantryEditor(db.get('pantry', d.id)); return false; },
    qty: (d) => {
      const p = db.get('pantry', d.id); if (!p) return;
      const step = ['kg', 'L'].includes(p.unit) ? 0.5 : ['g', 'ml'].includes(p.unit) ? 100 : 1;
      const q = Math.max(0, p.quantity + step * Number(d.n));
      if (q === 0) db.remove('pantry', p.id); else db.update('pantry', p.id, { quantity: q });
    },
    newRecipe: () => { recipeEditor(); return false; },
  },
  inputs: { recipeSearch: (v) => { ui.recipeSearch = v; } },
};

export const recipe = {
  render(rawId) {
    const id = decodeURIComponent(rawId || '');
    const r = D.allRecipes().find((x) => x.id === id);
    if (!r) return `${back('food', 'Alimentação')}${empty('🤷', 'Receita não encontrada', '')}`;
    const stock = new Set(db.all('pantry').filter((p) => p.quantity > 0).map((p) => D.canonical(p.name)));
    const fav = (db.profile().favorites || []).includes(r.id);
    return `${back('food', 'Alimentação')}<div class="grad g-food"><div class="grow"><h2>${esc(r.name)}</h2><small>${r.minutes} min · ${r.servings} porção(ões)</small></div>
      <button class="icon-btn light" data-act="fav" data-id="${esc(r.id)}" aria-label="Favoritar">${fav ? '❤️' : '🤍'}</button></div>
      <div class="card"><h3>Ingredientes</h3>${r.ingredients.map((i) => { const has = D.hasIngredient(i.name, stock); return `<div class="row-sb"><span>${has ? '✅' : '⚪'} ${esc(i.name)}</span><span class="muted">${esc(i.qty || '')}</span></div>`; }).join('')}</div>
      <div class="card"><h3>Modo de preparo</h3><ol class="steps">${r.steps.map((s) => `<li>${esc(s)}</li>`).join('')}</ol></div>
      ${r.kcal ? `<div class="card"><h3>Informação nutricional estimada (por porção)</h3><div class="grid4"><span><b>${r.kcal}</b><small>kcal</small></span><span><b>${r.protein}g</b><small>proteínas</small></span><span><b>${r.carbs}g</b><small>carboidratos</small></span><span><b>${r.fat}g</b><small>gorduras</small></span></div>
        <small class="muted">Valores aproximados, apenas para referência.</small></div>` : ''}
      <button class="btn btn-primary wide" data-act="cooked" data-id="${esc(r.id)}">🍳 Preparei hoje</button>
      ${r.builtIn ? '' : `<button class="btn btn-danger-ghost wide" data-act="delRecipe" data-id="${esc(r.id)}">Excluir receita</button>`}`;
  },
  actions: {
    fav: (d) => { const f = db.profile().favorites || []; db.setProfile({ favorites: f.includes(d.id) ? f.filter((x) => x !== d.id) : [...f, d.id] }); },
    cooked: (d) => { const r = D.allRecipes().find((x) => x.id === d.id); db.insert('cookLogs', { recipeId: r.id, name: r.name, date: new Date().toISOString() }); toast('Registrado no histórico.'); },
    delRecipe: async (d) => { if (await confirmDialog('Excluir esta receita?', { danger: true, confirmLabel: 'Excluir' })) { db.remove('recipes', d.id); location.hash = '#/food'; } },
  },
};
