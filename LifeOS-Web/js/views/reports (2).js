import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { seg, icon, stat, download } from '../ui.js';
import { bars, line, hbars, progress } from '../charts.js';
import { financeCharts } from './finance.js';
import * as B from '../backup.js';

const ui = { period: 'mes' };

export const reports = {
  render() {
    const i = U.periodInterval(ui.period);
    const inI = (d) => U.inInterval(d, i);
    const txs = db.all('transactions');
    const study = db.all('studySessions').filter((s) => inI(s.date));
    const minutes = study.reduce((a, s) => a + s.minutes, 0);
    const workouts = db.all('workoutSessions').filter((w) => inI(w.date));
    const weights = db.all('body').filter((m) => m.weight && inI(m.date)).sort((a, b) => new Date(a.date) - new Date(b.date));
    const days = Math.max(1, Math.round((i.end - i.start) / 86400000));
    const habits = db.all('habits').filter((h) => !h.archived);
    const habitRate = habits.length ? habits.reduce((a, h) => a + D.habitConsistency(h, days), 0) / habits.length : null;
    const topics = db.all('topics').filter((t) => t.subjectId);
    const weeks = [];
    for (let w = U.startOfWeek(i.start); w <= i.end; w = U.addDays(w, 7)) weeks.push(w);
    const grades = db.all('subjects').map((s) => ({ label: s.name, value: D.weightedAverage(db.all('grades').filter((g) => g.subjectId === s.id)), color: s.color })).filter((x) => x.value !== null);
    const goals = db.all('goals');
    return `<button class="back no-print" data-act="nav" data-to="profile">${icon('back', 18)} Perfil</button>
      <header class="top"><h1>Relatórios</h1><div class="top-a no-print"><button class="btn btn-sm" data-act="printReport">📄 PDF</button><button class="btn btn-sm" data-act="csvAll">📊 CSV</button></div></header>
      <div class="no-print">${seg('period', U.PERIODS, ui.period)}</div>
      <p class="muted small print-only">LifeOS — relatório (${U.PERIODS[ui.period]}) gerado em ${U.dateTime(new Date())}</p>
      <div class="grid2">
        ${stat('Saldo do período', U.money(D.income(txs, i) - D.spending(txs, i)), '💰', '#22c55e')}
        ${stat('Horas estudadas', U.duration(minutes), '📚', '#8b5cf6')}
        ${stat('Treinos', String(workouts.length), '🏋️', '#22c55e')}
        ${stat('Variação de peso', weights.length >= 2 ? `${U.num(weights.at(-1).weight - weights[0].weight)} kg` : '–', '⚖️', '#f97316')}
        ${stat('Hábitos cumpridos', habitRate === null ? '–' : U.pct(habitRate), '✅', '#6366f1')}
        ${stat('Conteúdo acadêmico', U.pct(D.topicProgress(topics)), '🎓', '#ec4899')}
      </div>
      ${minutes ? `<div class="card"><h3>Horas de estudo por semana</h3>${bars(weeks.map((w) => ({ label: U.dayMonth(w), value: db.all('studySessions').filter((s) => new Date(s.date) >= w && new Date(s.date) < U.addDays(w, 7)).reduce((a, s) => a + s.minutes, 0) / 60 })), { height: 120, color: '#8b5cf6', format: (v) => U.num(v) + 'h' })}</div>` : ''}
      ${weights.length >= 2 ? `<div class="card"><h3>Evolução do peso</h3>${line(weights.map((m) => ({ x: m.date, y: m.weight })), { color: '#f97316', format: (v) => U.num(v) + ' kg' })}</div>` : ''}
      ${workouts.length ? `<div class="card"><h3>Frequência de treinos</h3>${bars(weeks.map((w) => ({ label: U.dayMonth(w), value: workouts.filter((s) => new Date(s.date) >= w && new Date(s.date) < U.addDays(w, 7)).length })), { height: 110, color: '#22c55e' })}</div>` : ''}
      ${grades.length ? `<div class="card"><h3>Média por matéria</h3>${hbars(grades, { format: (v) => U.num(v) })}</div>` : ''}
      ${habits.length ? `<div class="card"><h3>Hábitos</h3>${hbars(habits.map((h) => ({ label: h.name, value: D.habitConsistency(h, days) * 100, color: h.color })), { format: (v) => U.num(v, 0) + '%' })}</div>` : ''}
      ${goals.length ? `<div class="card"><h3>Metas</h3>${goals.filter((g) => !g.completed).slice(0, 8).map((g) => `<div class="goal"><div class="row-sb"><span>${esc(g.title)}</span><b>${U.pct(g.current / g.target)}</b></div>${progress(g.current / g.target, '#a855f7')}</div>`).join('')}<small class="muted">${goals.filter((g) => g.completed).length} meta(s) concluída(s)</small></div>` : ''}
      <h2>Finanças</h2>${financeCharts(ui.period)}`;
  },
  actions: {
    period: (d) => { ui.period = d.v; },
    printReport: () => { window.print(); return false; },
    csvAll: () => {
      const i = U.periodInterval(ui.period);
      const f = (col) => db.all(col).filter((x) => U.inInterval(x.date, i));
      const csvType = 'text/csv;charset=utf-8';
      download('LifeOS-financas.csv', B.csvTransactions(f('transactions')), csvType);
      setTimeout(() => download('LifeOS-estudos.csv', B.csvStudy(f('studySessions')), csvType), 400);
      setTimeout(() => download('LifeOS-treinos.csv', B.csvWorkouts(f('workoutSessions')), csvType), 800);
      setTimeout(() => download('LifeOS-corpo.csv', B.csvBody(f('body')), csvType), 1200);
      setTimeout(() => download('LifeOS-habitos.csv', B.csvHabits(db.all('habits')), csvType), 1600);
      return false;
    },
  },
};
