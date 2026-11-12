// Treino AO VIVO: uma única tela para registrar o treino durante a execução.
// Séries marcáveis, carga/repetições com botões grandes, cronômetro de descanso e tela sempre acesa.
import * as db from '../store.js';
import * as N from '../nlp.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { modal, confirmDialog, toast, icon } from '../ui.js';
import { notifyNow } from '../notify.js';

const clock = (ms) => {
  const t = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}` : `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
};

export function liveWorkout(plan = null) {
  const st = {
    title: plan?.name || 'Treino livre',
    startedAt: Date.now(),
    restEnd: null,
    updatePlan: true,
    exercises: (plan?.exercises || []).map((e) => ({
      name: e.name, rest: e.rest ?? 60, video: e.video || '',
      repsList: e.repsList,
      sets: Array.from({ length: Math.max(1, e.sets || 3) }, (_, i) => ({ reps: e.repsList?.[i] ?? e.repsList?.at(-1) ?? e.reps ?? 10, load: e.load || 0, done: false })),
    })),
  };
  let timer = null, restTimer = null, wakeLock = null, finished = false;

  const doneSets = () => st.exercises.reduce((a, e) => a + e.sets.filter((s) => s.done).length, 0);
  const totalSets = () => st.exercises.reduce((a, e) => a + e.sets.length, 0);
  const volume = () => st.exercises.reduce((a, e) => a + e.sets.filter((s) => s.done).reduce((b, s) => b + s.load * s.reps, 0), 0);

  const html = () => `
    <div class="live-stats"><span><b data-clock>${clock(Date.now() - st.startedAt)}</b><small>Tempo</small></span>
      <span><b>${doneSets()}/${totalSets()}</b><small>Séries</small></span><span><b>${U.num(volume(), 0)} kg</b><small>Volume</small></span></div>
    <div data-rest class="rest ${st.restEnd ? '' : 'hidden'}"><span>⏱</span><div class="grow"><small data-rest-label>Descanso</small><b data-rest-clock></b></div>
      <button class="btn btn-sm" data-l="rest+">+15s</button><button class="btn btn-sm" data-l="restSkip">Pular</button></div>
    ${st.exercises.length ? '' : '<p class="muted center">Adicione os exercícios e marque as séries conforme for fazendo.</p>'}
    ${st.exercises.map((e, ei) => {
      const all = e.sets.length && e.sets.every((s) => s.done);
      return `<div class="card live-ex ${all ? 'done' : ''}"><div class="row-sb"><b>${all ? '✅' : '🏋️'} ${esc(e.name)} ${U.videoLink(e.video)}</b>
        <span class="live-ex-a"><select data-lc="rest" data-e="${ei}" aria-label="Descanso">${[...new Set([0, 30, 45, 60, 90, 120, 180, e.rest])].sort((a, b) => a - b).map((r) => `<option value="${r}" ${r === e.rest ? 'selected' : ''}>${r ? r + 's' : 'Sem descanso'}</option>`).join('')}</select>
        <button class="icon-btn" data-l="delEx" data-e="${ei}" aria-label="Remover exercício">${icon('trash', 16)}</button></span></div>
        <div class="set-h"><span>Série</span><span>Carga (kg)</span><span>Reps</span><span></span></div>
        ${e.sets.map((s, si) => `<div class="set ${s.done ? 'on' : ''}"><span class="set-n">${si + 1}</span>
          <span class="stepper"><button data-l="load-" data-e="${ei}" data-s="${si}" aria-label="Diminuir carga">−</button><b>${U.num(s.load)}</b><button data-l="load+" data-e="${ei}" data-s="${si}" aria-label="Aumentar carga">+</button></span>
          <span class="stepper"><button data-l="reps-" data-e="${ei}" data-s="${si}" aria-label="Menos repetições">−</button><b>${s.reps}</b><button data-l="reps+" data-e="${ei}" data-s="${si}" aria-label="Mais repetições">+</button></span>
          <button class="set-chk" data-l="done" data-e="${ei}" data-s="${si}" aria-label="${s.done ? 'Desmarcar' : 'Marcar'} série ${si + 1}">${s.done ? '✓' : ''}</button></div>`).join('')}
        <div class="row-sb"><button class="link small" data-l="addSet" data-e="${ei}">+ Série</button>${e.sets.length > 1 ? `<button class="link small muted" data-l="delSet" data-e="${ei}">− Remover série</button>` : ''}</div></div>`;
    }).join('')}
    <form class="card inline-add" data-l-form><input name="ex" placeholder="Adicionar exercício" maxlength="80" aria-label="Novo exercício"><button class="icon-btn accent" aria-label="Adicionar">${icon('plus')}</button></form>
    ${plan ? `<label class="check card"><input type="checkbox" data-lc="updatePlan" ${st.updatePlan ? 'checked' : ''}><span>Atualizar cargas da ficha ao concluir</span></label>` : ''}`;

  modal({
    title: st.title, wide: true, persistent: true,
    body: '<div class="live" data-live></div>',
    footer: '<button class="btn" data-cancel>Cancelar</button><button class="btn btn-primary" data-finish>✓ Concluir treino</button>',
    onMount: (el, close) => {
      el.classList.add('live-modal');
      const box = el.querySelector('[data-live]');
      const draw = () => { const y = box.parentElement.scrollTop; box.innerHTML = html(); box.parentElement.scrollTop = y; tickRest(); };
      const tickRest = () => {
        const r = box.querySelector('[data-rest]');
        if (!r) return;
        if (!st.restEnd) { r.classList.add('hidden'); return; }
        const left = st.restEnd - Date.now();
        r.classList.remove('hidden');
        r.classList.toggle('over', left <= 0);
        r.querySelector('[data-rest-label]').textContent = left > 0 ? 'Descanso' : 'Descanso concluído';
        r.querySelector('[data-rest-clock]').textContent = left > 0 ? clock(left) : 'Próxima série!';
      };
      const startRest = (sec) => {
        st.restEnd = Date.now() + sec * 1000;
        clearTimeout(restTimer);
        restTimer = setTimeout(() => {
          try { navigator.vibrate?.([200, 100, 200]); } catch { /* */ }
          if (document.visibilityState === 'hidden') notifyNow('Descanso concluído', 'Hora da próxima série.', 'rest');
        }, sec * 1000);
      };
      timer = setInterval(() => {
        const c = box.querySelector('[data-clock]');
        if (c) c.textContent = clock(Date.now() - st.startedAt);
        tickRest();
      }, 1000);
      navigator.wakeLock?.request('screen').then((w) => { wakeLock = w; }).catch(() => {});

      box.addEventListener('click', (e) => {
        const b = e.target.closest('[data-l]');
        if (!b) return;
        e.preventDefault();
        const ex = st.exercises[Number(b.dataset.e)];
        const set = ex && ex.sets[Number(b.dataset.s)];
        switch (b.dataset.l) {
          case 'load-': set.load = Math.max(0, Math.round((set.load - 2.5) * 10) / 10); break;
          case 'load+': set.load = Math.round((set.load + 2.5) * 10) / 10; break;
          case 'reps-': set.reps = Math.max(1, set.reps - 1); break;
          case 'reps+': set.reps += 1; break;
          case 'done':
            set.done = !set.done;
            if (set.done) { try { navigator.vibrate?.(30); } catch { /* */ } if (ex.rest > 0) startRest(ex.rest); else { st.restEnd = null; clearTimeout(restTimer); } }
            break;
          case 'addSet': { const last = ex.sets[ex.sets.length - 1] || { reps: 10, load: 0 }; ex.sets.push({ reps: last.reps, load: last.load, done: false }); break; }
          case 'delSet': ex.sets.pop(); break;
          case 'delEx': st.exercises.splice(Number(b.dataset.e), 1); break;
          case 'rest+': st.restEnd = Math.max(Date.now(), st.restEnd || 0) + 15000; startRest(Math.round((st.restEnd - Date.now()) / 1000)); break;
          case 'restSkip': st.restEnd = null; clearTimeout(restTimer); break;
          default: break;
        }
        draw();
      });
      box.addEventListener('change', (e) => {
        const t = e.target;
        if (t.dataset.lc === 'rest') st.exercises[Number(t.dataset.e)].rest = Number(t.value);
        if (t.dataset.lc === 'updatePlan') st.updatePlan = t.checked;
      });
      box.addEventListener('submit', (e) => {
        e.preventDefault();
        const name = e.target.ex.value.trim();
        if (!name) return;
        st.exercises.push({ name: name.slice(0, 80), rest: 60, sets: [{ reps: 10, load: 0, done: false }] });
        draw();
        box.querySelector('[data-l-form] input')?.focus();
      });
      el.querySelector('[data-cancel]').onclick = async () => {
        if (doneSets() && !(await confirmDialog('Descartar este treino? As séries marcadas não serão salvas.', { danger: true, confirmLabel: 'Descartar' }))) return;
        finished = true; close();
      };
      el.querySelector('[data-finish]').onclick = async () => {
        if (!doneSets()) { toast('Marque pelo menos uma série feita.'); return; }
        if (!(await confirmDialog(`Salvar o treino com ${doneSets()} série(s)?`, { confirmLabel: 'Salvar treino' }))) return;
        save();
        finished = true; close();
        toast('Treino salvo no histórico. 💪');
      };
      draw();
    },
    onClose: () => {
      clearInterval(timer); clearTimeout(restTimer);
      try { wakeLock?.release(); } catch { /* */ }
      if (!finished && doneSets()) toast('Treino descartado.');
    },
  });

  function save() {
    const entries = [];
    for (const e of st.exercises) {
      const done = e.sets.filter((s) => s.done);
      if (!done.length) continue;
      entries.push({ name: e.name, video: e.video || undefined, sets: done.length, reps: Math.round(done.reduce((a, s) => a + s.reps, 0) / done.length), load: Math.max(...done.map((s) => s.load)), rest: e.rest });
    }
    db.insert('workoutSessions', {
      title: st.title, date: new Date(st.startedAt).toISOString(), minutes: Math.max(1, Math.round((Date.now() - st.startedAt) / 60000)),
      notes: '', entries, planId: plan?.id || null, muscleGroups: N.muscleGroupsIn(U.fold(st.title)),
    });
    if (plan && st.updatePlan) {
      db.update('workoutPlans', plan.id, {
        exercises: (plan.exercises || []).map((pe) => {
          const live = st.exercises.find((x) => x.name === pe.name);
          const done = live?.sets.filter((s) => s.done) || [];
          return done.length ? { ...pe, load: Math.max(...done.map((s) => s.load)), ...(pe.repsList?.length ? {} : { reps: done[done.length - 1].reps }), sets: live.sets.length, rest: live.rest } : pe;
        }),
      });
    }
  }
}
