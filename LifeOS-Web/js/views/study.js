import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { form, seg, empty, icon, section, stat, confirmDialog, modal } from '../ui.js';
import { bars, line, ring, progress, donut } from '../charts.js';
import { eventEditor, eventRow } from './agenda.js';
import { docRow, importDocument } from './docs.js';

const ui = { subjectTab: 'conteudo', contestTab: 'acompanhando' };
const COLORS = ['#8b5cf6', '#ec4899', '#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#14b8a6', '#6366f1'];

const topicsOf = (key, id) => db.all('topics').filter((t) => t[key] === id);
const back = (to, label) => `<button class="back" data-act="nav" data-to="${to}">${icon('back', 18)} ${esc(label)}</button>`;

// ---------- Assuntos (árvore) ----------
function topicTree(key, ownerId) {
  const all = topicsOf(key, ownerId);
  const rowsFor = (parentId, level) => all.filter((t) => (t.parentId || null) === parentId).sort((a, b) => (a.order || 0) - (b.order || 0)).map((t) => {
    const st = D.TOPIC_STATUS[t.status] || D.TOPIC_STATUS.naoIniciado;
    const due = D.isReviewDue(t);
    return `<div class="topic" style="--lvl:${level}">
      <select class="st" data-change="topicStatus" data-id="${t.id}" style="color:${st.color}" aria-label="Status">${Object.entries(D.TOPIC_STATUS).map(([k, v]) => `<option value="${k}" ${k === t.status ? 'selected' : ''}>${v.icon} ${v.label}</option>`).join('')}</select>
      <div class="grow"><b>${esc(t.title)}</b>${t.nextReview ? `<small class="${due ? 'orange' : 'muted'}">revisão ${U.relDay(t.nextReview)}</small>` : ''}</div>
      ${due ? `<button class="btn btn-sm" data-act="reviewed" data-id="${t.id}">Revisado</button>` : ''}
      ${level < 2 ? `<button class="icon-btn" data-act="addTopic" data-key="${key}" data-owner="${ownerId}" data-parent="${t.id}" aria-label="Subtópico">${icon('plus', 16)}</button>` : ''}
      <button class="icon-btn" data-act="delTopic" data-id="${t.id}" aria-label="Excluir">${icon('trash', 16)}</button></div>${rowsFor(t.id, level + 1)}`;
  }).join('');
  const counts = Object.entries(D.TOPIC_STATUS).map(([k, v]) => ({ label: v.label, value: all.filter((t) => t.status === k).length, color: v.color })).filter((x) => x.value);
  return `${all.length ? `<div class="card donut-row">${donut(counts, { center: U.pct(D.topicProgress(all)), sub: 'concluído', size: 110 })}<ul class="legend">${counts.map((c) => `<li><i style="background:${c.color}"></i>${c.label}<b>${c.value}</b></li>`).join('')}</ul></div>` : ''}
    <form class="card inline-add" data-submit="addRootTopic" data-key="${key}" data-owner="${ownerId}"><input name="title" placeholder="Novo assunto" maxlength="200" aria-label="Novo assunto"><button class="icon-btn accent" aria-label="Adicionar">${icon('plus')}</button></form>
    <div class="card topics">${rowsFor(null, 0) || '<p class="muted">Cadastre os assuntos para acompanhar o progresso.</p>'}</div>`;
}

// ---------- Faculdade ----------
export function subjectEditor(s = null) {
  form({
    title: s ? 'Editar matéria' : 'Nova matéria',
    values: { name: s?.name || '', professor: s?.professor || '', semester: s?.semester || db.profile().semester || '', color: s?.color || COLORS[0], notes: s?.notes || '' },
    fields: [
      { name: 'name', label: 'Nome', required: true }, { name: 'professor', label: 'Professor(a)' }, { name: 'semester', label: 'Semestre' },
      { name: 'color', label: 'Cor', type: 'color', options: COLORS }, { name: 'notes', label: 'Observações', type: 'textarea' },
    ],
    onDelete: s ? () => { db.removeWhere('topics', (t) => t.subjectId === s.id); db.removeWhere('grades', (g) => g.subjectId === s.id); db.all('events').filter((e) => e.subjectId === s.id).forEach((e) => db.update('events', e.id, { subjectId: null })); db.remove('subjects', s.id); location.hash = '#/studies'; } : null,
    onSubmit: (v) => { if (s) db.update('subjects', s.id, v); else db.insert('subjects', v); },
  });
}

export function courseEditor() {
  const p = db.profile();
  form({ title: 'Meu curso', values: p,
    fields: [{ name: 'course', label: 'Curso' }, { name: 'institution', label: 'Instituição' }, { name: 'semester', label: 'Semestre atual' }],
    onSubmit: (v) => db.setProfile(v) });
}

export const college = {
  render() {
    const p = db.profile();
    const subs = [...db.all('subjects')].sort((a, b) => a.name.localeCompare(b.name));
    const topics = db.all('topics').filter((t) => t.subjectId);
    const avgs = subs.map((s) => D.weightedAverage(db.all('grades').filter((g) => g.subjectId === s.id))).filter((x) => x !== null);
    return `${back('profile', 'Perfil')}<header class="top"><h1>Faculdade</h1><div class="top-a"><button class="icon-btn accent" data-act="newSubject" aria-label="Nova matéria">${icon('plus')}</button></div></header>
      <div class="grad g-study" data-act="course"><div class="grow"><h2>${esc(p.course || 'Toque para informar seu curso')}</h2><small>${esc([p.institution, p.semester ? p.semester + 'º semestre' : ''].filter(Boolean).join(' · '))}</small>
        <div class="kpis"><span><b>${subs.length}</b>matérias</span><span><b>${U.pct(D.topicProgress(topics))}</b>conteúdo</span><span><b>${avgs.length ? U.num(avgs.reduce((a, b) => a + b, 0) / avgs.length) : '–'}</b>média</span></div></div><span class="big-emoji">🎓</span></div>
      ${subs.length ? subs.map((s) => {
        const ts = topicsOf('subjectId', s.id);
        const avg = D.weightedAverage(db.all('grades').filter((g) => g.subjectId === s.id));
        const next = db.all('events').filter((e) => e.subjectId === s.id && !e.done && new Date(e.start) >= U.startOfDay(new Date())).sort((a, b) => new Date(a.start) - new Date(b.start))[0];
        return `<div class="card row" data-act="nav" data-to="subject/${s.id}">${ring(D.topicProgress(ts), { size: 54, color: s.color, label: U.pct(D.topicProgress(ts)) })}
          <div class="grow"><b>${esc(s.name)}</b><small>${esc(s.professor || '')}</small>${next ? `<small style="color:${D.EVENT_CATS[next.category].color}">${D.EVENT_CATS[next.category].icon} ${D.EVENT_CATS[next.category].label} ${U.relDay(next.start)}</small>` : ''}</div>
          ${avg !== null ? `<b class="${avg >= 6 ? 'green' : 'orange'}">${U.num(avg)}</b>` : ''}${icon('chevron', 18)}</div>`;
      }).join('') : empty('📚', 'Nenhuma matéria', 'Cadastre suas matérias ou diga ao assistente: "Tenho prova de cálculo dia 20".', 'newSubject', 'Nova matéria')}`;
  },
  actions: {
    newSubject: () => { subjectEditor(); return false; },
    course: () => { courseEditor(); return false; },
  },
};

export const subject = {
  render(id) {
    const s = db.get('subjects', id);
    if (!s) return `${back('studies', 'Estudos')}${empty('🤷', 'Matéria não encontrada', '')}`;
    const tab = ui.subjectTab;
    let body = '';
    if (tab === 'conteudo') {
      const mins = db.all('studySessions').filter((x) => x.subjectId === id).reduce((a, x) => a + x.minutes, 0);
      body = `${mins ? `<p class="muted">⏱ ${U.duration(mins)} estudadas</p>` : ''}${topicTree('subjectId', id)}`;
    } else if (tab === 'avaliacoes') {
      const evs = db.all('events').filter((e) => e.subjectId === id).sort((a, b) => new Date(a.start) - new Date(b.start));
      body = `<div class="btn-row"><button class="btn" data-act="addEval" data-c="prova">+ Prova</button><button class="btn" data-act="addEval" data-c="trabalho">+ Trabalho</button><button class="btn" data-act="addEval" data-c="entrega">+ Entrega</button></div>
        ${evs.map((e) => eventRow({ event: e, date: new Date(e.start) })).join('') || '<p class="muted">Provas, trabalhos e entregas desta matéria aparecem aqui e na Agenda.</p>'}`;
    } else if (tab === 'notas') {
      const gs = db.all('grades').filter((g) => g.subjectId === id).sort((a, b) => new Date(a.date) - new Date(b.date));
      const avg = D.weightedAverage(gs);
      body = `<div class="row-sb">${avg !== null ? `<div><small class="muted">Média ponderada</small><h1 class="${avg >= 6 ? 'green' : 'orange'}">${U.num(avg, 2)}</h1></div>` : '<span></span>'}<button class="btn btn-primary" data-act="addGrade">+ Nota</button></div>
        ${gs.length >= 2 ? `<div class="card">${line(gs.map((g) => ({ x: g.date, y: (g.value / g.maxValue) * 10 })), { color: s.color, format: (v) => U.num(v) })}</div>` : ''}
        ${gs.map((g) => `<div class="card row"><div class="grow"><b>${esc(g.title)}</b><small>${U.shortDate(g.date)} · peso ${U.num(g.weight)}</small></div><b>${U.num(g.value)} / ${U.num(g.maxValue)}</b><button class="icon-btn" data-act="delGrade" data-id="${g.id}" aria-label="Excluir">${icon('trash', 16)}</button></div>`).join('')}`;
    } else {
      const docs = db.all('documents').filter((d) => d.subjectId === id);
      body = `<button class="btn btn-primary" data-act="attach">📎 Anexar PDF ou imagem</button>${docs.map(docRow).join('') || '<p class="muted">Os arquivos ficam criptografados no cofre.</p>'}`;
    }
    return `${back('studies', 'Estudos')}<header class="top"><h1><span class="dot-l" style="background:${s.color}"></span>${esc(s.name)}</h1><div class="top-a">
      <button class="btn btn-sm" data-act="studyLog">⏱ Registrar estudo</button><button class="icon-btn" data-act="editSubject" aria-label="Editar">${icon('edit')}</button></div></header>
      ${seg('subjectTab', { conteudo: 'Conteúdo', avaliacoes: 'Avaliações', notas: 'Notas', materiais: 'Materiais' }, tab)}${body}`;
  },
  actions: {
    subjectTab: (d) => { ui.subjectTab = d.v; },
    editSubject: () => { subjectEditor(db.get('subjects', currentId())); return false; },
    addEval: (d) => { eventEditor(null, { category: d.c, subjectId: currentId() }); return false; },
    addGrade: () => {
      form({ title: 'Nova nota', values: { title: '', value: '', maxValue: 10, weight: 1, date: new Date() },
        fields: [{ name: 'title', label: 'Avaliação (ex.: P1)' }, { name: 'value', label: 'Nota obtida', type: 'decimal', required: true }, { name: 'maxValue', label: 'Nota máxima', type: 'decimal', required: true }, { name: 'weight', label: 'Peso', type: 'decimal' }, { name: 'date', label: 'Data', type: 'date' }],
        onSubmit: (v) => {
          if (!(v.maxValue > 0) || v.value < 0 || v.value > v.maxValue) return 'A nota deve estar entre 0 e a nota máxima.';
          db.insert('grades', { subjectId: currentId(), title: v.title || 'Avaliação', value: v.value, maxValue: v.maxValue, weight: v.weight || 1, date: (v.date || new Date()).toISOString() });
        } });
      return false;
    },
    delGrade: async (d) => { if (await confirmDialog('Excluir esta nota?', { danger: true, confirmLabel: 'Excluir' })) db.remove('grades', d.id); },
    attach: () => { importDocument({ subjectId: currentId(), category: 'academico', folder: db.get('subjects', currentId())?.name }); return false; },
    studyLog: () => { studyEditor({ subjectId: currentId() }); return false; },
  },
};

export function studyEditor(link) {
  form({ title: 'Registrar estudo', values: { minutes: 60, date: new Date(), note: '' },
    fields: [{ name: 'minutes', label: 'Duração (minutos)', type: 'int', min: 5, required: true }, { name: 'date', label: 'Data', type: 'date' }, { name: 'note', label: 'O que estudou?', type: 'textarea', rows: 2 }],
    onSubmit: (v) => { if (!(v.minutes > 0)) return 'Duração inválida.'; db.insert('studySessions', { ...link, minutes: v.minutes, date: (v.date || new Date()).toISOString(), note: v.note }); } });
}

const currentId = () => location.hash.split('/')[2];

// ---------- Concursos ----------
function contestEditor(c = null, asInterest = false) {
  form({
    title: c ? 'Editar concurso' : 'Novo concurso',
    intro: '<p class="muted small">Use apenas dados confirmados no edital oficial.</p>',
    values: c ? { ...c, regStart: c.regStart && new Date(c.regStart), regEnd: c.regEnd && new Date(c.regEnd), examDate: c.examDate && new Date(c.examDate) } : { status: asInterest ? 'interesse' : 'previsto' },
    fields: [
      { name: 'organ', label: 'Órgão', required: true }, { name: 'role', label: 'Cargo' }, { name: 'area', label: 'Área' }, { name: 'board', label: 'Banca' },
      { name: 'status', label: 'Situação', type: 'select', options: D.CONTEST_STATUS },
      { name: 'salary', label: 'Salário (R$)', type: 'money' }, { name: 'vacancies', label: 'Número de vagas', type: 'int', min: 0 },
      { name: 'requirements', label: 'Requisitos', type: 'textarea', rows: 2 },
      { name: 'regStart', label: 'Início das inscrições', type: 'date' }, { name: 'regEnd', label: 'Fim das inscrições', type: 'date' },
      { name: 'examDate', label: 'Data da prova', type: 'datetime' },
      { name: 'link', label: 'Link oficial (https://)', max: 500 }, { name: 'notes', label: 'Observações', type: 'textarea', rows: 2 },
    ],
    onDelete: c ? () => {
      const subs = db.all('contestSubjects').filter((s) => s.contestId === c.id).map((s) => s.id);
      db.removeWhere('topics', (t) => subs.includes(t.contestSubjectId)); db.removeWhere('questionLogs', (q) => subs.includes(q.contestSubjectId));
      db.removeWhere('contestSubjects', (s) => s.contestId === c.id); db.removeWhere('mockExams', (m) => m.contestId === c.id);
      db.remove('contests', c.id); location.hash = '#/contests';
    } : null,
    onSubmit: (v) => {
      let link = (v.link || '').trim();
      if (link && !/^https:\/\//i.test(link)) link = 'https://' + link.replace(/^\w+:\/\//, '');
      const data = { ...v, link, regStart: v.regStart?.toISOString() || null, regEnd: v.regEnd?.toISOString() || null, examDate: v.examDate?.toISOString() || null };
      if (c) db.update('contests', c.id, data); else db.insert('contests', data);
    },
  });
}

/** Resumo da preparação: conclusão média dos editais, horas na semana e prova mais próxima. */
function contestsOverview(list) {
  const avg = list.reduce((a, c) => a + D.contestCompletion(c.id), 0) / list.length;
  const weekStart = U.startOfWeek(new Date());
  const mins = db.all('studySessions').filter((s) => (s.contestId || s.contestSubjectId) && new Date(s.date) >= weekStart).reduce((a, s) => a + s.minutes, 0);
  const next = list.filter((c) => c.examDate && new Date(c.examDate) >= U.startOfDay(new Date())).sort((a, b) => new Date(a.examDate) - new Date(b.examDate))[0];
  return `<div class="grad g-contest"><div class="grow"><small>Preparação geral</small><h2>${list.length} concurso(s)</h2><small>${U.duration(mins)} estudadas nesta semana</small>
    ${next ? `<span class="tag">📅 Próxima prova: ${esc(next.organ)} · ${U.daysUntil(next.examDate) === 0 ? 'hoje' : `em ${U.daysUntil(next.examDate)} dias`}</span>` : ''}</div>
    ${ring(avg, { size: 64, color: '#fff', label: U.pct(avg) })}</div>`;
}

/** Datas do edital + eventos ligados ao concurso (aparecem também no Calendário). */
function importantDates(c) {
  const today = U.startOfDay(new Date());
  const fixed = [['Início das inscrições', c.regStart, '📝'], ['Fim das inscrições', c.regEnd, '⏳'], ['Prova', c.examDate, '🏛️']].filter((x) => x[1]);
  const evs = db.all('events').filter((e) => e.contestId === c.id).sort((a, b) => new Date(a.start) - new Date(b.start));
  const row = (title, date, emoji, act = '') => { const past = new Date(date) < today; const d = U.daysUntil(date);
    return `<div class="li" ${act}><span class="badge sm" style="--c:${past ? '#94a3b8' : '#6366f1'}">${emoji}</span><div class="grow"><b class="${past ? 'muted' : ''}">${esc(title)}</b><small>${U.fullDate(date)}</small></div>
      ${past ? '' : `<span class="pill" style="--c:#6366f1">${d === 0 ? 'Hoje' : `${d} dias`}</span>`}</div>`; };
  if (!fixed.length && !evs.length) return '<p class="muted">Cadastre as datas do edital: inscrições, prova, resultado, recursos…</p>';
  return `<div class="card">${fixed.map(([t, d, e]) => row(t, d, e)).join('')}${evs.map((e) => row(e.title, e.start, D.EVENT_CATS[e.category]?.icon || '📅', `data-act="editEvent" data-id="${e.id}"`)).join('')}</div>`;
}

/** Revisões pendentes dos conteúdos deste edital. */
function contestReviews(contestId) {
  const due = D.contestTopics(contestId).filter((t) => D.isReviewDue(t));
  if (!due.length) return '';
  return `${section('Revisões para hoje')}<div class="card">${due.slice(0, 6).map((t) => `<div class="li"><div class="grow"><b>${esc(t.title)}</b><small>${esc(db.get('contestSubjects', t.contestSubjectId)?.name || '')}</small></div>
    <button class="btn btn-sm btn-primary" data-act="reviewed" data-id="${t.id}">Revisado</button></div>`).join('')}</div>`;
}

export const contests = {
  render() {
    const all = [...db.all('contests')].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    const following = all.filter((c) => c.status !== 'interesse'), interest = all.filter((c) => c.status === 'interesse');
    const list = ui.contestTab === 'acompanhando' ? following : interest;
    return `<header class="top"><h1>Editais</h1><div class="top-a"><button class="icon-btn accent" data-act="newContest" aria-label="Novo concurso">${icon('plus')}</button></div></header>
      ${following.length ? contestsOverview(following) : ''}
      ${seg('contestTab', { acompanhando: `Acompanhando (${following.length})`, interesse: `De interesse (${interest.length})` }, ui.contestTab)}
      ${list.length ? list.map((c) => {
        const subs = db.all('contestSubjects').filter((s) => s.contestId === c.id).map((s) => s.id);
        const ts = db.all('topics').filter((t) => subs.includes(t.contestSubjectId));
        const d = c.examDate && U.daysUntil(c.examDate);
        return `<div class="card" data-act="nav" data-to="contest/${c.id}"><div class="row-sb"><div><b>${esc(c.organ)}</b><small class="muted block">${esc(c.role || '')}</small></div><span class="pill">${esc(D.CONTEST_STATUS[c.status])}</span></div>
          <small class="muted">${[c.examDate ? (d >= 0 ? `📅 Prova em ${d} dias` : `📅 Prova em ${U.shortDate(c.examDate)}`) : '', c.salary ? `💰 ${U.money(c.salary)}` : '', c.board ? `🏢 ${esc(c.board)}` : ''].filter(Boolean).join(' · ')}</small>
          ${ts.length ? `${progress(D.topicProgress(ts), '#6366f1')}<small class="muted">${U.pct(D.topicProgress(ts))} do edital concluído</small>` : ''}</div>`;
      }).join('') : empty('🏛️', ui.contestTab === 'acompanhando' ? 'Nenhum concurso acompanhado' : 'Nenhum edital de interesse', 'Cadastre os dados a partir do edital oficial. O LifeOS não busca informações na internet nesta versão.', 'newContest', 'Cadastrar concurso')}`;
  },
  actions: {
    contestTab: (d) => { ui.contestTab = d.v; },
    newContest: () => { contestEditor(null, ui.contestTab === 'interesse'); return false; },
  },
};

export const contest = {
  render(id) {
    const c = db.get('contests', id);
    if (!c) return `${back('contests', 'Editais')}${empty('🤷', 'Concurso não encontrado', '')}`;
    const subs = db.all('contestSubjects').filter((s) => s.contestId === id).sort((a, b) => (a.order || 0) - (b.order || 0));
    const sessions = db.all('studySessions').filter((s) => s.contestId === id);
    const minutes = sessions.reduce((a, s) => a + s.minutes, 0);
    const logs = db.all('questionLogs').filter((q) => subs.some((s) => s.id === q.contestSubjectId));
    const tot = logs.reduce((a, q) => a + q.total, 0), cor = logs.reduce((a, q) => a + q.correct, 0);
    const weeks = [7, 6, 5, 4, 3, 2, 1, 0].map((i) => { const w = U.addDays(U.startOfWeek(new Date()), -7 * i); return { label: U.dayMonth(w), value: sessions.filter((s) => new Date(s.date) >= w && new Date(s.date) < U.addDays(w, 7)).reduce((a, s) => a + s.minutes, 0) / 60 }; });
    const mocks = db.all('mockExams').filter((m) => m.contestId === id).sort((a, b) => new Date(a.date) - new Date(b.date));
    const docs = db.all('documents').filter((d) => d.contestId === id);
    const info = (l, v) => `<span><small>${l}</small><b>${esc(v || '–')}</b></span>`;
    return `${back('contests', 'Editais')}<header class="top"><h1>${esc(c.organ)}</h1><div class="top-a"><button class="btn btn-sm" data-act="contestStudy">⏱ Horas</button><button class="icon-btn" data-act="editContest" aria-label="Editar">${icon('edit')}</button></div></header>
      <div class="grad g-contest"><div class="grow"><div class="row-sb wfull"><div><h2>${esc(c.role || c.organ)}</h2><small>${esc(D.CONTEST_STATUS[c.status])}</small></div>${ring(D.contestCompletion(id), { size: 64, color: '#fff', label: U.pct(D.contestCompletion(id)) })}</div>
        <div class="info-grid">${info('Banca', c.board)}${info('Área', c.area)}${info('Salário', c.salary ? U.money(c.salary) : '')}${info('Vagas', c.vacancies ?? '')}${info('Inscrições até', c.regEnd ? U.shortDate(c.regEnd) : '')}${info('Prova', c.examDate ? U.shortDate(c.examDate) : '')}</div>
        ${c.link && /^https:\/\//i.test(c.link) ? `<a class="lnk" href="${esc(c.link)}" target="_blank" rel="noopener noreferrer">Abrir link oficial ↗</a>` : ''}</div></div>
      <div class="grid3">${stat('Horas estudadas', U.duration(minutes), '⏱', '#6366f1')}${stat('Acertos', tot ? U.pct(cor / tot) : '–', '🎯', '#22c55e')}${stat('Questões', String(tot), '📝', '#f97316')}</div>
      ${minutes ? `<div class="card"><h3>Horas por semana</h3>${bars(weeks, { height: 120, color: '#6366f1', format: (v) => U.num(v) + 'h' })}</div>` : ''}
      ${section('Datas importantes', 'addContestDate', 'Adicionar')}${importantDates(c)}${contestReviews(id)}
      ${section('Matérias do edital', 'addCS', 'Adicionar')}
      ${subs.map((s) => { const ts = topicsOf('contestSubjectId', s.id); const ql = db.all('questionLogs').filter((q) => q.contestSubjectId === s.id); const t = ql.reduce((a, q) => a + q.total, 0), k = ql.reduce((a, q) => a + q.correct, 0);
        return `<div class="card" data-act="nav" data-to="contestSubject/${s.id}"><div class="row-sb"><b>${esc(s.name)}</b>${icon('chevron', 18)}</div>${progress(D.topicProgress(ts), '#6366f1')}<small class="muted">${U.pct(D.topicProgress(ts))} do conteúdo${t ? ` · ${U.pct(k / t)} de acertos` : ''}</small></div>`; }).join('') || '<p class="muted">Adicione as matérias do conteúdo programático.</p>'}
      ${section('Simulados', 'addMock', 'Registrar')}
      ${mocks.length ? `<div class="card">${mocks.length >= 2 ? line(mocks.map((m) => ({ x: m.date, y: (m.correct / m.total) * 100 })), { color: '#6366f1', format: (v) => U.num(v) + '%' }) : ''}
        ${[...mocks].reverse().map((m) => `<div class="li"><div class="grow"><b>${esc(m.title)}</b><small>${U.shortDate(m.date)}</small></div><b>${m.correct}/${m.total} · ${U.pct(m.correct / m.total)}</b><button class="icon-btn" data-act="delMock" data-id="${m.id}" aria-label="Excluir">${icon('trash', 16)}</button></div>`).join('')}</div>` : '<p class="muted">Registre simulados para acompanhar sua evolução.</p>'}
      ${section('Edital e documentos', 'importEdital', 'Importar PDF')}
      ${docs.map(docRow).join('') || '<p class="muted">Importe o PDF do edital para consultar offline.</p>'}
      ${c.requirements || c.notes ? `<div class="card">${c.requirements ? `<h4>Requisitos</h4><p>${esc(c.requirements)}</p>` : ''}${c.notes ? `<h4>Observações</h4><p>${esc(c.notes)}</p>` : ''}</div>` : ''}`;
  },
  actions: {
    editContest: () => { contestEditor(db.get('contests', currentId())); return false; },
    addContestDate: () => { eventEditor(null, { category: 'dataImportante', contestId: currentId() }); return false; },
    contestStudy: () => { studyEditor({ contestId: currentId() }); return false; },
    addCS: () => {
      form({ title: 'Nova matéria do edital', fields: [{ name: 'name', label: 'Nome', required: true }],
        onSubmit: (v) => { db.insert('contestSubjects', { contestId: currentId(), name: v.name, order: db.all('contestSubjects').filter((s) => s.contestId === currentId()).length }); } });
      return false;
    },
    addMock: () => {
      form({ title: 'Simulado', values: { date: new Date() }, fields: [{ name: 'title', label: 'Nome' }, { name: 'total', label: 'Total de questões', type: 'int', min: 1, required: true }, { name: 'correct', label: 'Acertos', type: 'int', min: 0, required: true }, { name: 'date', label: 'Data', type: 'date' }],
        onSubmit: (v) => { if (!(v.total > 0) || v.correct < 0 || v.correct > v.total) return 'Valores inválidos.'; db.insert('mockExams', { contestId: currentId(), title: v.title || 'Simulado', total: v.total, correct: v.correct, date: (v.date || new Date()).toISOString() }); } });
      return false;
    },
    delMock: async (d) => { if (await confirmDialog('Excluir este simulado?', { danger: true, confirmLabel: 'Excluir' })) db.remove('mockExams', d.id); },
    importEdital: () => { const c = db.get('contests', currentId()); importDocument({ contestId: c.id, category: 'edital', folder: c.organ }); return false; },
  },
};

export const contestSubject = {
  render(id) {
    const s = db.get('contestSubjects', id);
    if (!s) return empty('🤷', 'Matéria não encontrada', '');
    const logs = db.all('questionLogs').filter((q) => q.contestSubjectId === id).sort((a, b) => new Date(a.date) - new Date(b.date));
    return `${back('contest/' + s.contestId, 'Concurso')}<header class="top"><h1>${esc(s.name)}</h1><div class="top-a"><button class="btn btn-sm" data-act="csStudy">⏱ Horas</button><button class="icon-btn" data-act="delCS" aria-label="Excluir">${icon('trash')}</button></div></header>
      <form class="card" data-submit="addQuestions"><h3>Registrar questões</h3><div class="row"><input name="total" type="number" min="1" placeholder="Total" aria-label="Total"><input name="correct" type="number" min="0" placeholder="Acertos" aria-label="Acertos"><button class="btn btn-primary">Salvar</button></div>
        ${logs.length >= 2 ? line(logs.map((q) => ({ x: q.date, y: (q.correct / q.total) * 100 })), { height: 110, color: '#6366f1', format: (v) => U.num(v) + '%' }) : ''}
        ${logs.length ? `<small class="muted">${logs.reduce((a, q) => a + q.total, 0)} questões · ${U.pct(logs.reduce((a, q) => a + q.correct, 0) / logs.reduce((a, q) => a + q.total, 0))} de acertos</small>` : ''}</form>
      ${topicTree('contestSubjectId', id)}`;
  },
  submit: {
    addQuestions: (f) => {
      const t = parseInt(f.total.value, 10), c = parseInt(f.correct.value, 10);
      if (!(t > 0) || !(c >= 0) || c > t) return;
      db.insert('questionLogs', { contestSubjectId: currentId(), total: t, correct: c, date: new Date().toISOString() });
    },
  },
  actions: {
    csStudy: () => { const s = db.get('contestSubjects', currentId()); studyEditor({ contestSubjectId: s.id, contestId: s.contestId }); return false; },
    delCS: async () => {
      const s = db.get('contestSubjects', currentId());
      if (await confirmDialog(`Excluir ${s.name} e seus assuntos?`, { danger: true, confirmLabel: 'Excluir' })) {
        db.removeWhere('topics', (t) => t.contestSubjectId === s.id); db.removeWhere('questionLogs', (q) => q.contestSubjectId === s.id);
        db.remove('contestSubjects', s.id); location.hash = '#/contest/' + s.contestId;
      }
    },
  },
};

// Ações compartilhadas da árvore de assuntos.
export const topicActions = {
  addTopic: (d) => {
    form({ title: 'Novo subtópico', fields: [{ name: 'title', label: 'Título', required: true }],
      onSubmit: (v) => { db.insert('topics', { title: v.title, status: 'naoIniciado', [d.key]: d.owner, parentId: d.parent, order: db.all('topics').filter((t) => t.parentId === d.parent).length }); } });
    return false;
  },
  delTopic: async (d) => {
    if (!(await confirmDialog('Excluir este assunto e seus subtópicos?', { danger: true, confirmLabel: 'Excluir' }))) return;
    const kill = (id) => { db.all('topics').filter((t) => t.parentId === id).forEach((t) => kill(t.id)); db.remove('topics', id); };
    kill(d.id);
  },
  reviewed: (d) => { const t = db.get('topics', d.id); if (t) D.markReviewed(t); },
};
export const topicChanges = {
  topicStatus: (d, el) => { const t = db.get('topics', d.id); if (t) D.setTopicStatus(t, el.value); },
};
export const topicSubmits = {
  addRootTopic: (f) => {
    const title = f.title.value.trim();
    if (!title) return;
    const { key, owner } = f.dataset;
    db.insert('topics', { title: title.slice(0, 200), status: 'naoIniciado', [key]: owner, parentId: null, order: db.all('topics').filter((t) => t[key] === owner && !t.parentId).length });
  },
};
