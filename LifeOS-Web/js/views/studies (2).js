// ESTUDOS — faculdade: matérias, conteúdos, avaliações, revisões, horas, metas e desempenho.
import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { form, seg, empty, icon, confirmDialog } from '../ui.js';
import { bars, hbars, ring, progress } from '../charts.js';
import { eventEditor, eventRow } from './agenda.js';
import { subjectEditor, courseEditor } from './study.js';

const ui = { tab: 'materias' };
const TABS = { materias: 'Matérias', avaliacoes: 'Avaliações', revisoes: 'Revisões', historico: 'Histórico' };
const academic = () => db.all('events').filter((e) => D.ACADEMIC_CATS.includes(e.category) && !e.contestId).sort((a, b) => new Date(a.start) - new Date(b.start));
const subjectTopics = (id) => db.all('topics').filter((t) => t.subjectId === id);

export function studyLog(subjectId = '') {
  form({
    title: 'Registrar estudo', values: { subjectId, minutes: 60, date: new Date(), note: '' },
    fields: [
      { name: 'subjectId', label: 'Matéria', type: 'select', options: { '': 'Sem matéria', ...Object.fromEntries(db.all('subjects').map((s) => [s.id, s.name])) } },
      { name: 'minutes', label: 'Duração (minutos)', type: 'int', min: 5, required: true },
      { name: 'date', label: 'Data', type: 'date' },
      { name: 'note', label: 'O que estudou?', type: 'textarea', rows: 2 },
    ],
    onSubmit: (v) => {
      if (!(v.minutes > 0) || v.minutes > 1440) return 'Duração inválida.';
      db.insert('studySessions', { subjectId: v.subjectId || null, minutes: v.minutes, date: (v.date || new Date()).toISOString(), note: v.note || '' });
    },
  });
}

function goalEditor() {
  form({
    title: 'Meta semanal de estudo', values: { hours: Math.round((db.profile().weeklyStudyGoalMinutes || 600) / 60) },
    intro: '<p class="muted small">Usada em Estudos e no indicador de produtividade da Home.</p>',
    fields: [{ name: 'hours', label: 'Horas por semana', type: 'int', min: 1, maxv: 80, required: true }],
    onSubmit: (v) => { if (!(v.hours >= 1 && v.hours <= 80)) return 'Escolha entre 1 e 80 horas.'; db.setProfile({ weeklyStudyGoalMinutes: v.hours * 60 }); },
  });
}

function hero() {
  const p = db.profile();
  const topics = db.all('topics').filter((t) => t.subjectId);
  const done = topics.filter((t) => t.status === 'concluido').length;
  const prog = D.topicProgress(topics);
  const next = academic().find((e) => !e.done && new Date(e.start) >= U.startOfDay(new Date()));
  return `<div class="grad g-study" data-act="course"><div class="grow"><h2>${esc(p.course || 'Toque para informar seu curso')}</h2>
      <small>${esc([p.institution, p.semester ? p.semester + 'º semestre' : ''].filter(Boolean).join(' · '))}</small>
      <div class="kpis"><span><b>${db.all('subjects').length}</b>matérias</span><span><b>${done}/${topics.length}</b>conteúdos</span><span><b>${U.duration(D.studyMinutesInWeek())}</b>na semana</span></div>
      ${next ? `<span class="tag">${D.EVENT_CATS[next.category].icon} ${esc(next.title)} · ${U.relDay(next.start)}</span>` : ''}</div>
    ${ring(prog, { size: 64, color: '#fff', label: U.pct(prog) })}</div>`;
}

function weeklyGoal() {
  const goal = Math.max(1, db.profile().weeklyStudyGoalMinutes || 600);
  const min = D.studyMinutesInWeek();
  return `<div class="card"><div class="row-sb"><b>Meta da semana</b><button class="link small" data-act="studyGoal">Ajustar</button></div>
    ${progress(min / goal, '#d946ef')}<div class="row-sb"><small class="muted">${U.duration(min)} de ${U.duration(goal)}</small>
    <button class="link small" data-act="studyLog">+ Registrar estudo</button></div></div>`;
}

function materias() {
  const subs = [...db.all('subjects')].sort((a, b) => a.name.localeCompare(b.name));
  if (!subs.length) return empty('📚', 'Nenhuma matéria', 'Cadastre suas matérias ou diga ao assistente: "Tenho prova de cálculo dia 20".', 'newSubject', 'Nova matéria');
  return subs.map((s) => {
    const ts = subjectTopics(s.id);
    const avg = D.weightedAverage(db.all('grades').filter((g) => g.subjectId === s.id));
    const next = academic().find((e) => e.subjectId === s.id && !e.done && new Date(e.start) >= U.startOfDay(new Date()));
    const mins = db.all('studySessions').filter((x) => x.subjectId === s.id).reduce((a, x) => a + x.minutes, 0);
    return `<div class="card row" data-act="nav" data-to="subject/${s.id}">${ring(D.topicProgress(ts), { size: 54, color: s.color, label: U.pct(D.topicProgress(ts)) })}
      <div class="grow"><b>${esc(s.name)}</b><small>${[s.professor, mins ? `${U.duration(mins)} estudadas` : ''].filter(Boolean).map(esc).join(' · ')}</small>
      ${next ? `<small style="color:${D.EVENT_CATS[next.category].color}">${D.EVENT_CATS[next.category].icon} ${D.EVENT_CATS[next.category].label} ${U.relDay(next.start)}</small>` : ''}</div>
      ${avg !== null ? `<b class="${avg >= 6 ? 'green' : 'orange'}">${U.num(avg)}</b>` : ''}${icon('chevron', 18)}</div>`;
  }).join('');
}

function avaliacoes() {
  const all = academic();
  const today = U.startOfDay(new Date());
  const overdue = all.filter((e) => !e.done && new Date(e.start) < today);
  const upcoming = all.filter((e) => !e.done && new Date(e.start) >= today);
  const done = all.filter((e) => e.done).reverse().slice(0, 15);
  const list = (title, cls, items) => (items.length ? `<h4 class="day-h ${cls}">${title}</h4>${items.map((e) => eventRow({ event: e, date: new Date(e.start) })).join('')}` : '');
  return `<div class="btn-row">${['prova', 'trabalho', 'entrega'].map((c) => `<button class="btn btn-sm" data-act="addEval" data-c="${c}">+ ${D.EVENT_CATS[c].label}</button>`).join('')}</div>
    ${all.length ? '' : empty('🎓', 'Sem avaliações', 'Provas, trabalhos e entregas aparecem aqui e no Calendário.')}
    ${list('Atrasadas', 'red', overdue)}${list('Próximas', '', upcoming)}${list('Concluídas', 'muted', done)}`;
}

function revisoes() {
  const now = new Date();
  const ts = db.all('topics').filter((t) => t.subjectId);
  const due = ts.filter((t) => D.isReviewDue(t, now)).sort((a, b) => new Date(a.nextReview) - new Date(b.nextReview));
  const soon = ts.filter((t) => t.nextReview && new Date(t.nextReview) > now && new Date(t.nextReview) <= U.addDays(now, 14)).sort((a, b) => new Date(a.nextReview) - new Date(b.nextReview));
  const row = (t, isDue) => { const s = db.get('subjects', t.subjectId);
    return `<div class="card row"><span class="dot" style="background:${s?.color || '#8b5cf6'}"></span><div class="grow"><b>${esc(t.title)}</b>
      <small>${esc(s?.name || '')} · revisão ${(t.reviewStage || 0) + 1} · ${U.relDay(t.nextReview)}</small></div>${isDue ? `<button class="btn btn-sm btn-primary" data-act="reviewed" data-id="${t.id}">Revisado</button>` : ''}</div>`; };
  return `<p class="muted small">Ao concluir um conteúdo, o LifeOS agenda revisões em 1, 7, 15, 30 e 60 dias.</p>
    ${!due.length && !soon.length ? empty('↻', 'Nenhuma revisão agendada', 'Marque conteúdos como concluídos dentro de cada matéria.') : ''}
    ${due.length ? `<h4 class="day-h orange">Para hoje</h4>${due.map((t) => row(t, true)).join('')}` : ''}
    ${soon.length ? `<h4 class="day-h">Próximos 14 dias</h4>${soon.map((t) => row(t, false)).join('')}` : ''}`;
}

function historico() {
  const goalH = (db.profile().weeklyStudyGoalMinutes || 600) / 60;
  const sessions = [...db.all('studySessions')].sort((a, b) => new Date(b.date) - new Date(a.date));
  const weeks = [7, 6, 5, 4, 3, 2, 1, 0].map((i) => U.addDays(U.startOfWeek(new Date()), -7 * i));
  const data = weeks.map((w) => { const h = sessions.filter((s) => new Date(s.date) >= w && new Date(s.date) < U.addDays(w, 7)).reduce((a, s) => a + s.minutes, 0) / 60;
    return { label: U.dayMonth(w), value: h, color: h >= goalH ? '#16a34a' : '#d946ef' }; });
  const monthAgo = U.addDays(new Date(), -30);
  const bySubject = db.all('subjects').map((s) => ({ label: s.name, color: s.color,
    value: sessions.filter((x) => x.subjectId === s.id && new Date(x.date) >= monthAgo).reduce((a, x) => a + x.minutes, 0) / 60 })).filter((x) => x.value > 0).sort((a, b) => b.value - a.value);
  const college = sessions.filter((s) => !s.contestId && !s.contestSubjectId);
  return `<div class="card"><h3>Horas por semana</h3>${bars(data, { height: 140, format: (v) => U.num(v) + 'h', showValues: true })}
      <small class="muted">Verde = meta de ${U.num(goalH)}h batida</small></div>
    ${bySubject.length ? `<div class="card"><h3>Últimos 30 dias por matéria</h3>${hbars(bySubject, { format: (v) => U.num(v) + 'h' })}</div>` : ''}
    ${college.length ? `<h4 class="day-h">Sessões</h4>${college.slice(0, 40).map((s) => { const sub = s.subjectId && db.get('subjects', s.subjectId);
      return `<div class="card row"><span class="badge sm" style="--c:${sub?.color || '#d946ef'}">⏱</span><div class="grow"><b>${esc(sub?.name || s.note || 'Estudo')}</b><small>${U.fullDate(s.date)}</small></div>
        <b class="num">${U.duration(s.minutes)}</b><button class="icon-btn" data-act="delSession" data-id="${s.id}" aria-label="Excluir">${icon('trash', 16)}</button></div>`; }).join('')}`
      : empty('⏱', 'Sem sessões registradas', 'Registre aqui ou diga ao assistente: "Estudei 1h30 de cálculo".', 'studyLog', 'Registrar estudo')}`;
}

export const studies = {
  render() {
    const body = { materias, avaliacoes, revisoes, historico }[ui.tab] || materias;
    return `<header class="top"><h1>Estudos</h1><div class="top-a"><button class="btn btn-sm" data-act="studyLog">⏱ Registrar</button>
      <button class="icon-btn accent" data-act="studyMenu" aria-label="Adicionar">${icon('plus')}</button></div></header>
      ${hero()}${weeklyGoal()}${seg('studyTab', TABS, ui.tab)}${body()}`;
  },
  actions: {
    studyTab: (d) => { ui.tab = d.v; },
    studyLog: () => { studyLog(); return false; },
    studyGoal: () => { goalEditor(); return false; },
    course: () => { courseEditor(); return false; },
    newSubject: () => { subjectEditor(); return false; },
    addEval: (d) => { eventEditor(null, { category: d.c }); return false; },
    delSession: async (d) => { if (await confirmDialog('Excluir esta sessão de estudo?', { danger: true, confirmLabel: 'Excluir' })) db.remove('studySessions', d.id); },
    studyMenu: () => {
      form({
        title: 'Adicionar em Estudos', submitLabel: 'Continuar', values: { what: 'subject' },
        fields: [{ name: 'what', label: 'O que você quer adicionar?', type: 'select',
          options: { subject: 'Nova matéria', prova: 'Prova', trabalho: 'Trabalho', entrega: 'Entrega', session: 'Sessão de estudo', goal: 'Meta semanal' } }],
        onSubmit: (v) => {
          setTimeout(() => {
            if (v.what === 'subject') subjectEditor();
            else if (v.what === 'session') studyLog();
            else if (v.what === 'goal') goalEditor();
            else eventEditor(null, { category: v.what });
          }, 220);
        },
      });
      return false;
    },
  },
};
