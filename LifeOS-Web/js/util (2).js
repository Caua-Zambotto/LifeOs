// Utilitários gerais: escape de HTML, formatação pt-BR e datas.

export const uid = () => (crypto.randomUUID ? crypto.randomUUID() : 'id-' + Date.now().toString(36) + Math.random().toString(36).slice(2));

/** Escapa texto para HTML. TODO texto do usuário passa por aqui antes de ir para a tela. */
/** Aceita só links http(s) (ex.: vídeo do YouTube/Instagram); devolve '' para qualquer outra coisa. */
export function safeUrl(s) {
  const t = String(s || '').trim().slice(0, 500);
  if (!t) return '';
  try { const u = new URL(/^[a-z]+:\/\//i.test(t) ? t : 'https://' + t); return ['http:', 'https:'].includes(u.protocol) && u.hostname.includes('.') ? u.href : ''; } catch { return ''; }
}
/** Botão ▶ que abre o vídeo de execução fora do app. */
export const videoLink = (url, label = 'Ver vídeo da execução') => (safeUrl(url)
  ? `<a class="vid" href="${esc(safeUrl(url))}" target="_blank" rel="noopener noreferrer" aria-label="${esc(label)}" title="${esc(label)}">▶</a>` : '');
export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const currencyFmt = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
export const money = (v) => currencyFmt.format(Number(v) || 0);
export const signedMoney = (v) => (v >= 0 ? '+ ' : '− ') + money(Math.abs(v));
export const num = (v, d = 1) => new Intl.NumberFormat('pt-BR', { maximumFractionDigits: d, useGrouping: false }).format(Number(v) || 0);
export const pct = (v) => `${Math.round((Number(v) || 0) * 100)}%`;

/** "1.234,56" / "35" / "77.5" / "R$ 10,90" -> número */
export function parseDecimal(text) {
  if (text === null || text === undefined) return null;
  let t = String(text).replace(/R\$/gi, '').trim();
  if (!t) return null;
  if (t.includes(',')) t = t.replace(/\./g, '').replace(',', '.');
  const v = Number(t);
  return Number.isFinite(v) ? v : null;
}

/** Minúsculas sem acento, mantendo o MESMO comprimento do texto (alinhamento de posições). */
export function fold(s) {
  const src = String(s ?? '').normalize('NFC');
  let out = '';
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    const base = ch.normalize('NFD')[0] || ch;
    let low = base.toLowerCase();
    if (low.length !== 1) low = base.length === 1 ? base : ch;
    out += low;
  }
  return out;
}

export const capFirst = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

// ---------- Datas ----------
export const startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
export const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
export function addMonths(d, n) {
  const x = new Date(d);
  const day = x.getDate();
  x.setDate(1);
  x.setMonth(x.getMonth() + n);
  const last = new Date(x.getFullYear(), x.getMonth() + 1, 0).getDate();
  x.setDate(Math.min(day, last));
  return x;
}
export const startOfWeek = (d) => addDays(startOfDay(d), -new Date(d).getDay()); // domingo
export const startOfMonth = (d) => new Date(new Date(d).getFullYear(), new Date(d).getMonth(), 1);
export const endOfMonth = (d) => new Date(new Date(d).getFullYear(), new Date(d).getMonth() + 1, 0, 23, 59, 59, 999);
export const sameDay = (a, b) => a && b && startOfDay(a).getTime() === startOfDay(b).getTime();
export const daysUntil = (d, now = new Date()) => Math.round((startOfDay(d) - startOfDay(now)) / 86400000);
export const toDate = (v) => (v instanceof Date ? v : v ? new Date(v) : null);

const pad = (n) => String(n).padStart(2, '0');
/** "AAAA-MM-DD" local (para inputs type=date) */
export const dateKey = (d) => { const x = toDate(d); return `${x.getFullYear()}-${pad(x.getMonth() + 1)}-${pad(x.getDate())}`; };
/** "AAAA-MM-DDTHH:MM" local (para inputs datetime-local) */
export const dateTimeKey = (d) => { const x = toDate(d); return `${dateKey(x)}T${pad(x.getHours())}:${pad(x.getMinutes())}`; };
export const fromDateKey = (k) => { if (!k) return null; const [y, m, d] = k.split('-').map(Number); return new Date(y, m - 1, d); };
export const fromDateTimeKey = (k) => { if (!k) return null; const [a, b = '00:00'] = k.split('T'); const d = fromDateKey(a); const [h, mi] = b.split(':').map(Number); d.setHours(h || 0, mi || 0, 0, 0); return d; };

const fmt = (opts) => new Intl.DateTimeFormat('pt-BR', opts);
const fDayMonth = fmt({ day: 'numeric', month: 'short' });
const fFull = fmt({ weekday: 'long', day: 'numeric', month: 'long' });
const fTime = fmt({ hour: '2-digit', minute: '2-digit' });
const fMonthYear = fmt({ month: 'long', year: 'numeric' });
const fShort = fmt({ day: '2-digit', month: '2-digit', year: '2-digit' });
const fWeekday = fmt({ weekday: 'short' });
const fMonth = fmt({ month: 'short' });

export const dayMonth = (d) => fDayMonth.format(toDate(d)).replace('.', '');
export const fullDate = (d) => capFirst(fFull.format(toDate(d)));
export const time = (d) => fTime.format(toDate(d));
export const dateTime = (d) => `${dayMonth(d)} ${time(d)}`;
export const monthYear = (d) => capFirst(fMonthYear.format(toDate(d)));
export const shortDate = (d) => fShort.format(toDate(d));
export const weekdayShort = (d) => capFirst(fWeekday.format(toDate(d)).replace('.', ''));
export const monthShort = (d) => capFirst(fMonth.format(toDate(d)).replace('.', ''));

export function relDay(d, now = new Date()) {
  const n = daysUntil(d, now);
  if (n === 0) return 'hoje';
  if (n === 1) return 'amanhã';
  if (n === -1) return 'ontem';
  if (n > 1 && n < 7) return `em ${n} dias`;
  if (n < -1) return `há ${-n} dias`;
  return dayMonth(d);
}

export function duration(min) {
  const h = Math.floor(min / 60), m = Math.round(min % 60);
  if (!h) return `${m} min`;
  return m ? `${h}h${pad(m)}` : `${h}h`;
}

export function greeting(d = new Date()) {
  const h = d.getHours();
  return h >= 5 && h < 12 ? 'Bom dia' : h >= 12 && h < 18 ? 'Boa tarde' : 'Boa noite';
}

export function bytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${num(n / 1024)} KB`;
  return `${num(n / 1048576)} MB`;
}

/** Períodos de relatório. */
export const PERIODS = { semana: 'Semana', mes: 'Mês', trimestre: 'Trimestre', ano: 'Ano' };
export function periodInterval(p, now = new Date()) {
  let start;
  if (p === 'semana') start = startOfWeek(now);
  else if (p === 'mes') start = startOfMonth(now);
  else if (p === 'trimestre') start = addMonths(startOfMonth(now), -2);
  else start = addMonths(startOfMonth(now), -11);
  return { start, end: now };
}
export const inInterval = (d, i) => { const t = toDate(d).getTime(); return t >= i.start.getTime() && t <= i.end.getTime(); };

export function debounce(fn, ms) {
  let t;
  return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
}
