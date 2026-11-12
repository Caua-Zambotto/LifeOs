// Gráficos SVG leves, sem bibliotecas.
import { esc, money, num } from './util.js';

const W = 320;

export function bars(data, { height = 140, color = '#7c5cff', format = (v) => num(v), showValues = false } = {}) {
  if (!data.length) return '';
  const max = Math.max(1, ...data.map((d) => d.value));
  const gap = 6, bw = (W - gap * (data.length - 1)) / data.length, chartH = height - 22;
  const rects = data.map((d, i) => {
    const h = Math.max(d.value > 0 ? 3 : 0, (d.value / max) * (chartH - (showValues ? 14 : 4)));
    const x = i * (bw + gap), y = chartH - h;
    return `<g><title>${esc(d.label)}: ${esc(format(d.value))}</title>
      <rect x="${x}" y="${y}" width="${bw}" height="${h}" rx="${Math.min(6, bw / 3)}" fill="${d.color || color}"/>
      ${showValues && d.value > 0 ? `<text x="${x + bw / 2}" y="${y - 4}" text-anchor="middle" class="ch-val">${esc(format(d.value))}</text>` : ''}
      <text x="${x + bw / 2}" y="${height - 6}" text-anchor="middle" class="ch-lbl">${esc(d.label)}</text></g>`;
  }).join('');
  return `<svg class="chart" viewBox="0 0 ${W} ${height}" preserveAspectRatio="none" role="img">${rects}</svg>`;
}

export function hbars(data, { format = (v) => money(v) } = {}) {
  if (!data.length) return '';
  const max = Math.max(1, ...data.map((d) => d.value));
  return `<div class="hbars">${data.map((d) => `
    <div class="hbar"><span class="hbar-l">${esc(d.label)}</span>
      <span class="hbar-t"><span style="width:${(d.value / max) * 100}%;background:${d.color || 'var(--accent)'}"></span></span>
      <span class="hbar-v">${esc(format(d.value))}</span></div>`).join('')}</div>`;
}

export function line(points, { height = 140, color = '#7c5cff', target = null, format = (v) => num(v), area = true } = {}) {
  if (points.length < 2) return '';
  const xs = points.map((p) => +new Date(p.x)), ys = points.map((p) => p.y);
  if (target !== null) ys.push(target);
  let minY = Math.min(...ys), maxY = Math.max(...ys);
  if (minY === maxY) { minY -= 1; maxY += 1; }
  const pad = (maxY - minY) * 0.12; minY -= pad; maxY += pad;
  const minX = Math.min(...xs), maxX = Math.max(...xs) || minX + 1;
  const H = height - 18;
  const X = (x) => 8 + ((x - minX) / (maxX - minX || 1)) * (W - 16);
  const Y = (y) => 6 + (1 - (y - minY) / (maxY - minY)) * (H - 12);
  const pts = points.map((p) => [X(+new Date(p.x)), Y(p.y)]);
  const d = pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ');
  const areaD = `${d} L${pts[pts.length - 1][0].toFixed(1)},${H} L${pts[0][0].toFixed(1)},${H} Z`;
  const id = 'g' + Math.random().toString(36).slice(2, 8);
  return `<svg class="chart" viewBox="0 0 ${W} ${height}" preserveAspectRatio="none" role="img">
    <defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity=".28"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></linearGradient></defs>
    ${area ? `<path d="${areaD}" fill="url(#${id})"/>` : ''}
    ${target !== null ? `<line x1="0" x2="${W}" y1="${Y(target)}" y2="${Y(target)}" stroke="#22c55e" stroke-dasharray="5 4" stroke-width="1.5"/>` : ''}
    <path d="${d}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke"/>
    ${pts.map((p, i) => `<circle cx="${p[0]}" cy="${p[1]}" r="3" fill="${color}"><title>${esc(format(points[i].y))}</title></circle>`).join('')}
    <text x="4" y="${height - 4}" class="ch-lbl" text-anchor="start">${esc(format(points[0].y))}</text>
    <text x="${W - 4}" y="${height - 4}" class="ch-lbl" text-anchor="end">${esc(format(points[points.length - 1].y))}</text>
  </svg>`;
}

export function donut(data, { size = 132, center = '', sub = '' } = {}) {
  const total = data.reduce((a, d) => a + d.value, 0);
  if (!total) return '';
  const r = 52, c = 2 * Math.PI * r;
  let off = 0;
  const arcs = data.map((d) => {
    const len = (d.value / total) * c;
    const s = `<circle r="${r}" cx="66" cy="66" fill="none" stroke="${d.color}" stroke-width="16" stroke-dasharray="${Math.max(0, len - 2)} ${c}" stroke-dashoffset="${-off}" transform="rotate(-90 66 66)"><title>${esc(d.label)}</title></circle>`;
    off += len;
    return s;
  }).join('');
  return `<svg width="${size}" height="${size}" viewBox="0 0 132 132" class="donut">${arcs}
    <text x="66" y="62" text-anchor="middle" class="ch-sub">${esc(sub)}</text>
    <text x="66" y="80" text-anchor="middle" class="ch-center">${esc(center)}</text></svg>`;
}

export function ring(value, { size = 64, color = 'currentColor', label = '' } = {}) {
  const r = 26, c = 2 * Math.PI * r, v = Math.max(0, Math.min(1, value || 0));
  return `<svg width="${size}" height="${size}" viewBox="0 0 64 64" class="ring">
    <circle r="${r}" cx="32" cy="32" fill="none" stroke="${color}" stroke-opacity=".2" stroke-width="7"/>
    <circle r="${r}" cx="32" cy="32" fill="none" stroke="${color}" stroke-width="7" stroke-linecap="round" stroke-dasharray="${c * v} ${c}" transform="rotate(-90 32 32)"/>
    <text x="32" y="37" text-anchor="middle" class="ring-t">${esc(label)}</text></svg>`;
}

export const progress = (v, color = '#7c5cff') => `<div class="progress"><span style="width:${Math.max(0, Math.min(1, v || 0)) * 100}%;background:${color}"></span></div>`;
