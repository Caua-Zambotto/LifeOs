// Inicialização, bloqueio, navegação e despacho de ações da interface.
import * as db from './store.js';
import * as U from './util.js';
import { esc } from './util.js';
import { passwordStrength } from './crypto.js';
import { icon, modal, toast, hasOpenModal } from './ui.js';
import * as notify from './notify.js';
import home from './views/home.js';
import agenda, { eventEditor } from './views/agenda.js';
import assistant, { send as assistantSend } from './views/assistant.js';
import finance, { transactionEditor } from './views/finance.js';
import { liveWorkout } from './views/live.js';
import { college, subject, contests, contest, contestSubject, topicActions, topicChanges, topicSubmits } from './views/study.js';
import { studies } from './views/studies.js';
import { workouts, body, food, recipe, bodyEditor, sessionEditor, pantryEditor, scanGroceries } from './views/health.js';
import { growth, goal, goalEditor, habitEditor } from './views/growth.js';
import { docs, docActions, importDocument } from './views/docs.js';
import { reports } from './views/reports.js';
import { profile, settings, security, backup, notifications, storage, install, limits, sync } from './views/settings.js';
import * as S from './sync.js';

window.LIFEOS_VERSION = '1.2.2';

const VIEWS = { home, studies, agenda, assistant, finance, profile, college: studies, subject, contests, contest, contestSubject, workouts, body, food, recipe,
  growth, goal, docs, reports, settings, security, backup, notifications, storage, install, limits, sync };

/** Os seis módulos da barra inferior (rota, ícone, nome). */
const MODULES = [
  ['home', 'home', 'Home'], ['studies', 'book', 'Estudos'], ['agenda', 'calendar', 'Calendário'],
  ['workouts', 'dumbbell', 'Treino'], ['contests', 'columns', 'Editais'], ['finance', 'pie', 'Financeiro'],
];
/** A qual módulo cada tela pertence (para destacar a aba e aplicar a cor do módulo). */
const TAB_OF = {
  home: 'home', studies: 'studies', college: 'studies', subject: 'studies', agenda: 'agenda',
  workouts: 'workouts', body: 'workouts', food: 'workouts', recipe: 'workouts',
  contests: 'contests', contest: 'contests', contestSubject: 'contests', finance: 'finance',
};

// Ações disponíveis em qualquer tela.
const SHARED_ACTIONS = {
  ...topicActions, ...docActions,
  nav: (d) => { location.hash = '#/' + d.to; return false; },
  quickAdd: () => { quickAdd(); return false; },
  editEvent: agenda.actions.editEvent,
  toggleEvent: agenda.actions.toggleEvent,
  customizeHome: () => { home.actions.customize(); return false; },
  startPlan: (d) => { liveWorkout(d.id ? db.get('workoutPlans', d.id) : null); return false; },
};
const SHARED_CHANGES = { ...topicChanges };
const SHARED_SUBMITS = { ...topicSubmits };

const root = document.getElementById('app');
let current = { name: 'home', param: null };

// ---------- Tema ----------
document.documentElement.dataset.theme = localStorage.getItem('theme') || 'system';

// ---------- Rota ----------
function parseRoute() {
  const parts = location.hash.replace(/^#\/?/, '').split('/');
  const name = VIEWS[parts[0]] ? parts[0] : 'home';
  return { name, param: parts[1] || null };
}

function shell() {
  const tab = TAB_OF[current.name] || '';
  const navItem = ([id, ic, label]) => `<button class="nav-i mod-${id} ${tab === id ? 'on' : ''}" data-act="nav" data-to="${id}" aria-label="${label}" ${tab === id ? 'aria-current="page"' : ''}>${icon(ic)}<span>${label}</span></button>`;
  root.innerHTML = `<div class="shell">
    <nav class="nav" aria-label="Navegação principal">
      <div class="brand">✨ LifeOS</div>
      ${MODULES.map(navItem).join('')}
      <div class="nav-extra">
        <button class="nav-x" data-act="quickAdd">${icon('plus', 18)}<span>Adicionar</span></button>
        <button class="nav-x" data-act="nav" data-to="assistant">${icon('sparkle', 18)}<span>Assistente</span></button>
        <button class="nav-x" data-act="nav" data-to="profile">${icon('gear', 18)}<span>Perfil e ajustes</span></button>
        <button class="nav-x" data-act="lock">${icon('lock', 18)}<span>Bloquear</span></button>
      </div>
    </nav>
    <main id="main" class="view view-${current.name} ${tab ? 'mod-' + tab : ''}" tabindex="-1"></main></div>`;
}

function render() {
  if (!db.isUnlocked()) return;
  const r = parseRoute();
  const routeChanged = r.name !== current.name || r.param !== current.param;
  current = r;
  if (!document.getElementById('main') || routeChanged) shell();
  else updateNav();
  const main = document.getElementById('main');
  // Preserva texto/foco de campos marcados com data-keep durante a re-renderização.
  const active = document.activeElement;
  const keepId = active && active.dataset && 'keep' in active.dataset ? active.id : null;
  const keep = {};
  main.querySelectorAll('[data-keep]').forEach((el) => { keep[el.id] = { v: el.value, s: el.selectionStart, e: el.selectionEnd }; });
  try {
    main.innerHTML = VIEWS[current.name].render(current.param);
  } catch (e) {
    console.error(e);
    main.innerHTML = `<div class="card warn">Ocorreu um erro ao exibir esta tela. Seus dados não foram afetados.</div>`;
  }
  for (const [id, k] of Object.entries(keep)) {
    const el = document.getElementById(id);
    if (el) { el.value = k.v; if (id === keepId) { el.focus(); try { el.setSelectionRange(k.s, k.e); } catch { /* */ } } }
  }
  VIEWS[current.name].after?.();
  if (routeChanged) window.scrollTo(0, 0);
}

function updateNav() {
  const tab = TAB_OF[current.name] || '';
  root.querySelectorAll('.nav-i').forEach((b) => b.classList.toggle('on', b.dataset.to === tab));
}

const scheduleRender = (() => { let q = false; return () => { if (q) return; q = true; requestAnimationFrame(() => { q = false; render(); }); }; })();

// ---------- Delegação de eventos ----------
function findHandler(kind, name) {
  const v = VIEWS[current.name];
  const map = { act: [v.actions, SHARED_ACTIONS], change: [v.changes, SHARED_CHANGES], submit: [v.submit, SHARED_SUBMITS], input: [v.inputs, {}] }[kind];
  return map[0]?.[name] || map[1][name];
}

document.addEventListener('click', async (e) => {
  const el = e.target.closest('[data-act]');
  if (!el || el.closest('.modal-wrap')) return;
  if (el.dataset.act === 'lock') { e.preventDefault(); await db.lock(); return; }
  const fn = findHandler('act', el.dataset.act);
  if (!fn) return;
  e.preventDefault();
  const r = await fn(el.dataset, el, e);
  if (r !== false) scheduleRender();
});
document.addEventListener('change', (e) => {
  const el = e.target.closest('[data-change]');
  if (!el || el.closest('.modal-wrap')) return;
  const fn = findHandler('change', el.dataset.change);
  if (fn) { fn(el.dataset, el, e); scheduleRender(); }
});
document.addEventListener('input', U.debounce((e) => {
  const el = e.target.closest?.('[data-input]');
  if (!el) return;
  const fn = findHandler('input', el.dataset.input);
  if (fn) { fn(el.value, el); scheduleRender(); }
}, 200));
document.addEventListener('submit', (e) => {
  const f = e.target.closest('form[data-submit]');
  if (!f || f.closest('.modal-wrap')) return;
  e.preventDefault();
  const fn = findHandler('submit', f.dataset.submit);
  if (fn) { fn(f, e); scheduleRender(); }
});
document.addEventListener('lifeos:refresh', scheduleRender);
window.addEventListener('hashchange', render);

// ---------- Adição rápida ----------
function quickAdd() {
  const shortcuts = [
    ['💸', 'Despesa', () => transactionEditor(null, 'despesa')], ['💰', 'Receita', () => transactionEditor(null, 'receita')],
    ['📅', 'Evento', () => eventEditor()], ['⚖️', 'Peso', () => bodyEditor()], ['🏋️', 'Treino', () => sessionEditor()],
    ['🛒', 'Compras', () => scanGroceries()], ['🥚', 'Alimento', () => pantryEditor()], ['📄', 'Documento', () => importDocument()],
    ['🎯', 'Meta', () => goalEditor()], ['✅', 'Hábito', () => habitEditor()],
  ];
  modal({
    title: 'Adicionar',
    body: `<form class="composer inline" data-q><textarea rows="1" maxlength="500" placeholder="Ex.: gastei 35 reais no almoço" aria-label="Frase"></textarea><button class="send" aria-label="Enviar">${icon('send')}</button></form>
      <p class="muted small">Escreva naturalmente — o assistente prepara o registro — ou use um atalho:</p>
      <div class="qgrid">${shortcuts.map(([e, l], i) => `<button data-i="${i}"><span>${e}</span>${l}</button>`).join('')}</div>`,
    onMount: (el, close) => {
      const ta = el.querySelector('textarea');
      setTimeout(() => ta.focus(), 80);
      const go = (ev) => { ev?.preventDefault(); const t = ta.value.trim(); if (!t) return; close(); assistantSend(t); location.hash = '#/assistant'; };
      el.querySelector('form').addEventListener('submit', go);
      ta.addEventListener('keydown', (ev) => { if (ev.key === 'Enter' && !ev.shiftKey) go(ev); });
      el.querySelector('.qgrid').addEventListener('click', (ev) => {
        const b = ev.target.closest('button'); if (!b) return;
        close(); setTimeout(() => shortcuts[Number(b.dataset.i)][2](), 220);
      });
    },
  });
}

// ---------- Bloqueio e configuração inicial ----------
function lockScreen(message = '') {
  root.innerHTML = `<div class="lock"><div class="lock-card">
    <div class="lock-logo">✨</div><h1>LifeOS</h1><p class="muted">Seus dados estão cifrados neste aparelho.</p>
    <form id="unlock"><input type="password" id="pw" autocomplete="current-password" placeholder="Senha" aria-label="Senha" required>
      <button class="btn btn-primary wide">Desbloquear</button><p class="form-err" role="alert">${esc(message)}</p></form>
    <button class="link small" id="forgot">Esqueci a senha</button></div></div>`;
  const f = document.getElementById('unlock');
  setTimeout(() => document.getElementById('pw').focus(), 50);
  f.onsubmit = async (e) => {
    e.preventDefault();
    const btn = f.querySelector('button'); btn.disabled = true; btn.textContent = 'Verificando…';
    const r = await db.unlock(document.getElementById('pw').value);
    if (r.ok) { afterUnlock(); return; }
    btn.disabled = false; btn.textContent = 'Desbloquear';
    const err = f.querySelector('.form-err');
    if (r.lockUntil && r.lockUntil > Date.now()) err.textContent = `Muitas tentativas. Tente novamente às ${U.time(new Date(r.lockUntil))}.`;
    else err.textContent = `Senha incorreta.${r.remaining ? ` ${r.remaining} tentativa(s) antes do bloqueio temporário.` : ''}`;
    document.getElementById('pw').select();
  };
  document.getElementById('forgot').onclick = () => modal({ title: 'Esqueci a senha', body: '<p>Por segurança, não existe recuperação de senha: os dados são cifrados com ela.</p><p>Opção: apague os dados deste aparelho (configurações do navegador › dados do site) e restaure um backup do LifeOS usando a senha do backup.</p>' });
}

function setupScreen() {
  root.innerHTML = `<div class="lock"><div class="lock-card wide">
    <div class="lock-logo">✨</div><h1>Bem-vindo ao LifeOS</h1>
    <p class="muted">Agenda, estudos, finanças, treinos, alimentação e metas em um só lugar.</p>
    <ul class="plain feats"><li>📱 Use no computador e no celular, com os mesmos dados (opcional)</li><li>🔐 Dados cifrados com a sua senha</li><li>💬 Registre conversando: "gastei 35 reais no almoço"</li></ul>
    <form id="setup">
      <input id="name" placeholder="Como você quer ser chamado?" maxlength="40" aria-label="Nome" autocomplete="given-name">
      <input type="password" id="p1" placeholder="Crie uma senha (mín. 8 caracteres)" autocomplete="new-password" aria-label="Senha" required>
      <div class="strength"><span></span></div>
      <input type="password" id="p2" placeholder="Confirme a senha" autocomplete="new-password" aria-label="Confirmar senha" required>
      <label class="check small"><input type="checkbox" id="risk"><span>Entendo que, se eu esquecer a senha, meus dados não poderão ser recuperados (só por um backup).</span></label>
      <button class="btn btn-primary wide">Começar</button><p class="form-err" role="alert"></p></form>
    <button class="btn btn-ghost wide" id="join">☁️ Já uso o LifeOS em outro aparelho</button></div></div>`;
  document.getElementById('join').onclick = joinScreen;
  const p1 = document.getElementById('p1');
  p1.oninput = () => {
    const s = passwordStrength(p1.value);
    const bar = document.querySelector('.strength span');
    bar.style.width = `${(s / 4) * 100}%`;
    bar.style.background = ['#ef4444', '#f97316', '#eab308', '#22c55e', '#16a34a'][s];
  };
  document.getElementById('setup').onsubmit = async (e) => {
    e.preventDefault();
    const err = e.target.querySelector('.form-err');
    const a = p1.value, b = document.getElementById('p2').value;
    if (a.length < 8) { err.textContent = 'A senha precisa de pelo menos 8 caracteres.'; return; }
    if (passwordStrength(a) < 1) { err.textContent = 'Senha muito fraca. Use letras, números e símbolos.'; return; }
    if (a !== b) { err.textContent = 'As senhas não coincidem.'; return; }
    if (!document.getElementById('risk').checked) { err.textContent = 'Confirme que entendeu o aviso sobre a senha.'; return; }
    const btn = e.target.querySelector('button'); btn.disabled = true; btn.textContent = 'Preparando…';
    await db.setup(a);
    db.setProfile({ name: document.getElementById('name').value.trim().slice(0, 40) });
    db.requestPersistence().catch(() => {});
    afterUnlock();
  };
}

/** Aparelho novo: entra na conta, baixa o cofre e pede a senha do LifeOS do outro aparelho. */
async function joinScreen() {
  const cfg = await S.getConfig();
  const needCfg = !S.hasBuiltInConfig();
  root.innerHTML = `<div class="lock"><div class="lock-card wide">
    <div class="lock-logo">☁️</div><h1>Entrar na sua conta</h1>
    <p class="muted">Use a conta de sincronização que você ativou no outro aparelho (Perfil › Sincronização).</p>
    <form id="joinForm">
      ${needCfg ? `<input id="j_url" placeholder="Endereço do projeto (https://xxxx.supabase.co)" value="${esc(cfg.url)}" autocomplete="off" aria-label="Endereço do projeto">
      <input id="j_key" placeholder="Chave pública (anon key)" value="${esc(cfg.anonKey)}" autocomplete="off" aria-label="Chave pública">` : ''}
      <input id="j_email" type="email" placeholder="E-mail da conta" autocomplete="email" aria-label="E-mail" required>
      <input id="j_pw" type="password" placeholder="Senha da conta" autocomplete="current-password" aria-label="Senha da conta" required>
      <button class="btn btn-primary wide">Entrar</button><p class="form-err" role="alert"></p></form>
    <button class="btn btn-ghost wide" id="back">Voltar</button></div></div>`;
  document.getElementById('back').onclick = setupScreen;
  document.getElementById('joinForm').onsubmit = async (e) => {
    e.preventDefault();
    const err = e.target.querySelector('.form-err');
    const btn = e.target.querySelector('button');
    btn.disabled = true; btn.textContent = 'Conectando…';
    try {
      if (needCfg) await S.saveConfig(document.getElementById('j_url').value, document.getElementById('j_key').value);
      await S.signIn(document.getElementById('j_email').value.trim(), document.getElementById('j_pw').value);
      await S.joinFromAccount();
      lockScreen('Conta conectada. Agora digite a senha do LifeOS que você usa no outro aparelho.');
    } catch (ex) {
      err.textContent = ex.message || 'Não foi possível entrar.';
      btn.disabled = false; btn.textContent = 'Entrar';
    }
  };
}

S.onStatus(() => document.dispatchEvent(new Event('lifeos:refresh')));

function afterUnlock() {
  location.hash = location.hash || '#/home';
  current = { name: '', param: null };
  render();
  notify.rebuild();
  notify.start();
  S.start();
  lastActivity = Date.now();
}

// ---------- Bloqueio automático ----------
let lastActivity = Date.now();
let hiddenAt = null;
['pointerdown', 'keydown', 'scroll', 'touchstart'].forEach((ev) => window.addEventListener(ev, () => { lastActivity = Date.now(); }, { passive: true }));
setInterval(() => {
  if (!db.isUnlocked()) return;
  const limit = Math.max(120, (db.profile().autoLockSeconds || 120) * 2) * 1000;
  if (Date.now() - lastActivity > limit && !hasOpenModal()) db.lock();
}, 15000);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') {
    hiddenAt = Date.now();
    document.body.classList.add('privacy');
    db.flush().catch(() => {});
  } else {
    document.body.classList.remove('privacy');
    if (db.isUnlocked() && hiddenAt && Date.now() - hiddenAt > (db.profile().autoLockSeconds || 120) * 1000) db.lock();
    hiddenAt = null;
    notify.tick().catch(() => {});
  }
});
window.addEventListener('pagehide', () => { db.flush().catch(() => {}); });

// Ao mudar dados: atualiza a tela e os avisos; ao bloquear: volta para a tela de senha.
let wasUnlocked = false;
const rebuildNotifs = U.debounce(() => notify.rebuild(), 1000);
db.onChange(() => {
  const unlocked = db.isUnlocked();
  if (!unlocked) {
    if (wasUnlocked) { document.querySelectorAll('.modal-wrap').forEach((m) => m.remove()); lockScreen(); }
    wasUnlocked = false;
    return;
  }
  wasUnlocked = true;
  scheduleRender();
  rebuildNotifs();
});

// ---------- PWA ----------
window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); window.__installPrompt = e; });
if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  navigator.serviceWorker.register('sw.js').then((reg) => {
    reg.addEventListener('updatefound', () => {
      const w = reg.installing;
      w?.addEventListener('statechange', () => {
        if (w.state === 'installed' && navigator.serviceWorker.controller) toast('Nova versão disponível.', { action: 'Atualizar', onAction: () => location.reload(), ms: 15000 });
      });
    });
  }).catch(() => {});
}

// ---------- Início ----------
(async () => {
  if (!window.isSecureContext || !crypto.subtle || !window.indexedDB) {
    root.innerHTML = '<div class="lock"><div class="lock-card"><h1>LifeOS</h1><p>Este navegador não oferece os recursos de segurança necessários (contexto seguro, Web Crypto e IndexedDB). Abra pelo endereço https:// ou http://localhost.</p></div></div>';
    return;
  }
  try {
    if (await db.isSetUp()) lockScreen(); else setupScreen();
    notify.start();
  } catch {
    root.innerHTML = '<div class="lock"><div class="lock-card"><h1>LifeOS</h1><p>Não foi possível abrir o armazenamento local. Verifique se o navegador não está em modo privado/anônimo.</p></div></div>';
  }
})();
