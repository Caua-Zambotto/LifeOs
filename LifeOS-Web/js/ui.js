// Componentes de interface: modais, formulários, confirmações, avisos e ícones.
import { esc, dateKey, dateTimeKey, fromDateKey, fromDateTimeKey, parseDecimal, num } from './util.js';
import { WEEKDAY_NAMES } from './domain.js';
import * as db from './store.js';

// ---------- Ícones (SVG próprios) ----------
const P = {
  home: 'M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-6H9v6H4a1 1 0 01-1-1z',
  calendar: 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',
  sparkle: 'M12 3l2 5.5L19.5 10 14 12l-2 6-2-6-5.5-2L10 8.5z',
  wallet: 'M3 7h16a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2zM3 7V6a2 2 0 012-2h11M16 13h2',
  user: 'M12 12a4 4 0 100-8 4 4 0 000 8zM4 21a8 8 0 0116 0',
  plus: 'M12 5v14M5 12h14',
  back: 'M15 18l-6-6 6-6',
  chevron: 'M9 6l6 6-6 6',
  lock: 'M6 11h12v9H6zM8 11V8a4 4 0 018 0v3',
  send: 'M5 12h14M13 6l6 6-6 6',
  close: 'M6 6l12 12M18 6L6 18',
  check: 'M5 12l5 5L20 7',
  trash: 'M5 7h14M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3',
  edit: 'M4 20h4L19 9l-4-4L4 16zM14 6l4 4',
  more: 'M5 12h.01M12 12h.01M19 12h.01',
  search: 'M11 18a7 7 0 100-14 7 7 0 000 14zM20 20l-4-4',
  download: 'M12 4v11M7 10l5 5 5-5M5 20h14',
  upload: 'M12 20V9M7 14l5-5 5 5M5 4h14',
  camera: 'M4 8h4l2-3h4l2 3h4v11H4zM12 17a4 4 0 100-8 4 4 0 000 8z',
  undo: 'M9 14L4 9l5-5M4 9h11a5 5 0 010 10h-3',
  book: 'M4 5a2 2 0 012-2h13v16H6a2 2 0 00-2 2zM4 5v16M8 7h7',
  dumbbell: 'M6 7v10M3 9v6M18 7v10M21 9v6M6 12h12',
  columns: 'M3 10l9-6 9 6M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18',
  pie: 'M12 3v9h9M12 3a9 9 0 109 9',
  gear: 'M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 01-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 010-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 014 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 010 4h-.1a1.7 1.7 0 00-1.5 1z',
  play: 'M7 4l13 8-13 8z',
  timer: 'M12 21a8 8 0 100-16 8 8 0 000 16zM12 9v4l2 2M9 2h6',
};
export const icon = (name, size = 22) => `<svg class="ic" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${P[name] || ''}"/></svg>`;

// ---------- Pequenos componentes ----------
export const badge = (emoji, color = 'var(--accent)') => `<span class="badge" style="--c:${color}">${esc(emoji)}</span>`;
export const empty = (emoji, title, msg, act = '', actLabel = '') =>
  `<div class="empty"><div class="empty-i">${emoji}</div><b>${esc(title)}</b><p>${esc(msg)}</p>${act ? `<button class="btn btn-primary" data-act="${act}">${esc(actLabel)}</button>` : ''}</div>`;
export const section = (title, act = '', actLabel = '', data = '') =>
  `<div class="sec"><h3>${esc(title)}</h3>${act ? `<button class="link" data-act="${act}" ${data}>${esc(actLabel)}</button>` : ''}</div>`;
export const seg = (act, options, current, extra = '') =>
  `<div class="seg" role="tablist">${Object.entries(options).map(([k, v]) => `<button role="tab" class="${k === current ? 'on' : ''}" data-act="${act}" data-v="${esc(k)}" ${extra}>${esc(v)}</button>`).join('')}</div>`;
export const stat = (label, value, emoji, color) =>
  `<div class="card stat">${badge(emoji, color)}<b>${esc(value)}</b><span>${esc(label)}</span></div>`;

// ---------- Avisos ----------
export function toast(msg, { action, onAction, ms = 3500 } = {}) {
  const el = document.createElement('div');
  el.className = 'toast';
  el.innerHTML = `<span>${esc(msg)}</span>${action ? `<button>${esc(action)}</button>` : ''}`;
  document.body.appendChild(el);
  requestAnimationFrame(() => el.classList.add('show'));
  const close = () => { el.classList.remove('show'); setTimeout(() => el.remove(), 250); };
  if (action) el.querySelector('button').onclick = () => { onAction?.(); close(); };
  setTimeout(close, ms);
}

// ---------- Modal ----------
let openModals = 0;
export const hasOpenModal = () => openModals > 0;

export function modal({ title, body, footer = '', onMount, wide = false, onClose, persistent = false }) {
  const wrap = document.createElement('div');
  wrap.className = 'modal-wrap';
  wrap.innerHTML = `<div class="modal ${wide ? 'wide' : ''}" role="dialog" aria-modal="true" aria-label="${esc(title)}">
    <header><h2>${esc(title)}</h2><button class="icon-btn" data-close aria-label="Fechar">${icon('close')}</button></header>
    <div class="modal-body">${body}</div>${footer ? `<footer>${footer}</footer>` : ''}</div>`;
  document.body.appendChild(wrap);
  openModals++;
  requestAnimationFrame(() => wrap.classList.add('show'));
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    openModals--;
    wrap.classList.remove('show');
    setTimeout(() => wrap.remove(), 200);
    document.removeEventListener('keydown', onKey);
    onClose?.();
    document.dispatchEvent(new Event('lifeos:refresh')); // a tela atrás do modal é atualizada
  };
  // "persistent": não fecha ao tocar fora nem com Esc (evita perder um treino em andamento).
  const onKey = (e) => { if (e.key === 'Escape' && !persistent) close(); };
  document.addEventListener('keydown', onKey);
  wrap.addEventListener('click', (e) => { if ((e.target === wrap && !persistent) || e.target.closest('[data-close]')) close(); });
  if (persistent) wrap.classList.add('persistent');
  onMount?.(wrap.querySelector('.modal'), close);
  return { el: wrap.querySelector('.modal'), close };
}

// ---------- Formulários ----------
function fieldHtml(f, v) {
  const id = 'f_' + f.name;
  const req = f.required ? 'required' : '';
  const ph = f.placeholder ? `placeholder="${esc(f.placeholder)}"` : '';
  let input;
  switch (f.type) {
    case 'select':
      input = `<select id="${id}" name="${f.name}">${Object.entries(f.options).map(([k, l]) => `<option value="${esc(k)}" ${String(v ?? '') === String(k) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
      break;
    case 'textarea':
      input = `<textarea id="${id}" name="${f.name}" rows="${f.rows || 3}" ${ph} maxlength="${f.max || 5000}">${esc(v ?? '')}</textarea>`;
      break;
    case 'checkbox':
      return `<label class="check" data-field="${f.name}"><input type="checkbox" name="${f.name}" ${v ? 'checked' : ''}><span>${esc(f.label)}</span></label>`;
    case 'money': case 'decimal':
      input = `<input id="${id}" name="${f.name}" inputmode="decimal" autocomplete="off" ${ph} ${req} value="${v === null || v === undefined || v === '' ? '' : esc(num(v, 2))}">`;
      break;
    case 'int':
      input = `<input id="${id}" name="${f.name}" type="number" inputmode="numeric" ${f.min !== undefined ? `min="${f.min}"` : ''} ${f.maxv !== undefined ? `max="${f.maxv}"` : ''} ${req} value="${v ?? ''}">`;
      break;
    case 'date':
      input = `<input id="${id}" name="${f.name}" type="date" ${req} value="${v ? dateKey(v) : ''}">`;
      break;
    case 'datetime':
      input = `<input id="${id}" name="${f.name}" type="datetime-local" ${req} value="${v ? dateTimeKey(v) : ''}">`;
      break;
    case 'time':
      input = `<input id="${id}" name="${f.name}" type="time" value="${esc(v || '')}">`;
      break;
    case 'weekdays':
      return `<div class="field" data-field="${f.name}"><span class="lbl">${esc(f.label)}</span><div class="wd">${WEEKDAY_NAMES.map((n, i) =>
        `<label><input type="checkbox" name="${f.name}" value="${i}" ${(v || []).includes(i) ? 'checked' : ''}><span>${n}</span></label>`).join('')}</div>${f.help ? `<small>${esc(f.help)}</small>` : ''}</div>`;
    case 'color':
      return `<div class="field" data-field="${f.name}"><span class="lbl">${esc(f.label)}</span><div class="colors">${f.options.map((c) =>
        `<label><input type="radio" name="${f.name}" value="${c}" ${v === c ? 'checked' : ''}><span style="background:${c}"></span></label>`).join('')}</div></div>`;
    case 'password':
      input = `<input id="${id}" name="${f.name}" type="password" autocomplete="${f.autocomplete || 'current-password'}" ${ph} ${req}>`;
      break;
    case 'file':
      input = `<input id="${id}" name="${f.name}" type="file" ${f.accept ? `accept="${f.accept}"` : ''} ${f.capture ? 'capture="environment"' : ''}>`;
      break;
    default:
      input = `<input id="${id}" name="${f.name}" type="text" maxlength="${f.max || 200}" ${ph} ${req} value="${esc(v ?? '')}" ${f.list ? `list="${id}_l"` : ''}>${f.list ? `<datalist id="${id}_l">${f.list.map((x) => `<option value="${esc(x)}">`).join('')}</datalist>` : ''}`;
  }
  return `<div class="field" data-field="${f.name}"><label class="lbl" for="${id}">${esc(f.label)}</label>${input}${f.help ? `<small>${esc(f.help)}</small>` : ''}</div>`;
}

function readForm(formEl, fields) {
  const out = {};
  for (const f of fields) {
    if (f.type === 'html') continue;
    const els = formEl.querySelectorAll(`[name="${f.name}"]`);
    const el = els[0];
    if (!el) continue;
    switch (f.type) {
      case 'checkbox': out[f.name] = el.checked; break;
      case 'money': case 'decimal': out[f.name] = parseDecimal(el.value); break;
      case 'int': out[f.name] = el.value === '' ? null : parseInt(el.value, 10); break;
      case 'date': out[f.name] = fromDateKey(el.value); break;
      case 'datetime': out[f.name] = fromDateTimeKey(el.value); break;
      case 'weekdays': out[f.name] = [...els].filter((x) => x.checked).map((x) => Number(x.value)); break;
      case 'color': out[f.name] = [...els].find((x) => x.checked)?.value || f.options[0]; break;
      case 'file': out[f.name] = el.files?.[0] || null; break;
      case 'text': case undefined: out[f.name] = el.value.trim(); break;
      default: out[f.name] = el.value;
    }
  }
  return out;
}

/**
 * Formulário em modal.
 * onSubmit(values) pode retornar uma string de erro para manter o modal aberto.
 */
export function form({ title, fields, values = {}, submitLabel = 'Salvar', onSubmit, onDelete, deleteLabel = 'Excluir', intro = '' }) {
  const body = `<form class="form" novalidate>${intro}${fields.map((f) => (f.type === 'html' ? f.html : fieldHtml(f, values[f.name]))).join('')}<p class="form-err" role="alert"></p></form>`;
  const footer = `${onDelete ? `<button class="btn btn-danger-ghost" data-del>${esc(deleteLabel)}</button>` : '<span></span>'}<button class="btn btn-primary" data-save>${esc(submitLabel)}</button>`;
  return modal({
    title, body, footer,
    onMount: (el, close) => {
      const formEl = el.querySelector('form');
      const err = el.querySelector('.form-err');
      const refresh = () => {
        const v = readForm(formEl, fields);
        for (const f of fields) if (f.show) el.querySelector(`[data-field="${f.name}"]`)?.classList.toggle('hidden', !f.show(v));
      };
      formEl.addEventListener('change', refresh);
      refresh();
      const submit = async (e) => {
        e?.preventDefault();
        const v = readForm(formEl, fields);
        for (const f of fields) {
          if (f.required && (v[f.name] === null || v[f.name] === '' || v[f.name] === undefined) && (!f.show || f.show(v))) {
            err.textContent = `Preencha: ${f.label}`;
            return;
          }
        }
        const r = await onSubmit(v);
        if (typeof r === 'string') { err.textContent = r; return; }
        close();
      };
      formEl.addEventListener('submit', submit);
      el.querySelector('[data-save]').addEventListener('click', submit);
      el.querySelector('[data-del]')?.addEventListener('click', async () => {
        if (await confirmDialog('Excluir este item? Esta ação não pode ser desfeita.', { danger: true, confirmLabel: 'Excluir' })) { onDelete(); close(); }
      });
      setTimeout(() => el.querySelector('input:not([type=checkbox]):not([type=radio]),textarea,select')?.focus(), 60);
    },
  });
}

export function confirmDialog(message, { danger = false, confirmLabel = 'Confirmar', requireText = null } = {}) {
  return new Promise((resolve) => {
    let done = false;
    modal({
      title: 'Confirmação',
      body: `<p>${esc(message)}</p>${requireText ? `<div class="field"><label class="lbl">Digite ${esc(requireText)} para confirmar</label><input data-req autocomplete="off"></div>` : ''}`,
      footer: `<button class="btn" data-close>Cancelar</button><button class="btn ${danger ? 'btn-danger' : 'btn-primary'}" data-ok>${esc(confirmLabel)}</button>`,
      onMount: (el, close) => {
        el.querySelector('[data-ok]').addEventListener('click', () => {
          if (requireText && el.querySelector('[data-req]').value.trim().toUpperCase() !== requireText) return;
          done = true; resolve(true); close();
        });
      },
      onClose: () => { if (!done) resolve(false); },
    });
  });
}

/** Pede a senha do app antes de ações sensíveis. */
export function askPassword(reason) {
  return new Promise((resolve) => {
    let done = false;
    modal({
      title: 'Confirme sua senha',
      body: `<p>${esc(reason)}</p><form class="form"><div class="field"><input type="password" data-pw autocomplete="current-password" placeholder="Senha do LifeOS"></div><p class="form-err"></p></form>`,
      footer: '<button class="btn" data-close>Cancelar</button><button class="btn btn-primary" data-ok>Confirmar</button>',
      onMount: (el, close) => {
        const go = async (e) => {
          e?.preventDefault();
          if (await db.verifyPassword(el.querySelector('[data-pw]').value)) { done = true; resolve(true); close(); }
          else el.querySelector('.form-err').textContent = 'Senha incorreta.';
        };
        el.querySelector('form').addEventListener('submit', go);
        el.querySelector('[data-ok]').addEventListener('click', go);
        setTimeout(() => el.querySelector('[data-pw]').focus(), 60);
      },
      onClose: () => { if (!done) resolve(false); },
    });
  });
}

export function download(name, content, type = 'application/octet-stream') {
  const blob = content instanceof Blob ? content : new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = name; a.rel = 'noopener';
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);
}

export function pickFile(accept = '') {
  return new Promise((resolve) => {
    const i = document.createElement('input');
    i.type = 'file'; i.accept = accept;
    i.onchange = () => resolve(i.files?.[0] || null);
    i.click();
  });
}
