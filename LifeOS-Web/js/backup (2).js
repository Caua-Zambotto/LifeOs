// Backup criptografado (.lifeosbackup), exportação JSON aberta e CSV.
// Formato: { header: "<json>", data: "<base64>" }
//   data = AES-256-GCM( gzip( JSON do conteúdo ) ), chave = PBKDF2(senha do backup, salt, 310 mil)
//   o cabeçalho é autenticado (AAD) e o SHA-256 do conteúdo é conferido ao abrir.

import * as C from './crypto.js';
import * as db from './store.js';
import { shortDate, dateTime } from './util.js';

const ITER = 310000;

async function gzip(bytes) {
  if (typeof CompressionStream === 'undefined') return { bytes, compression: 'none' };
  const s = new Blob([bytes]).stream().pipeThrough(new CompressionStream('gzip'));
  return { bytes: new Uint8Array(await new Response(s).arrayBuffer()), compression: 'gzip' };
}
async function gunzip(bytes, compression) {
  if (compression !== 'gzip') return bytes;
  const s = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(s).arrayBuffer());
}

export class BackupError extends Error {}

export async function encryptPayload(payload, password) {
  if (!password || password.length < 8) throw new BackupError('Use uma senha de backup com pelo menos 8 caracteres.');
  const json = C.enc.encode(JSON.stringify(payload));
  const sha = await C.sha256Hex(json);
  const { bytes, compression } = await gzip(json);
  const salt = C.randomBytes(16);
  const header = JSON.stringify({
    format: 'lifeos-backup', version: 1, createdAt: payload.createdAt, kdf: 'PBKDF2-SHA256',
    iterations: ITER, salt: C.toB64(salt), sha256: sha, compression, includesFiles: !!payload.files,
  });
  const key = await C.keyFromPassword(password, salt, ITER);
  const ct = await C.encryptBytes(key, bytes, C.enc.encode(header));
  return JSON.stringify({ header, data: C.toB64(ct) });
}

export async function decryptPayload(text, password) {
  let outer, header;
  try { outer = JSON.parse(text); header = JSON.parse(outer.header); } catch { throw new BackupError('Este arquivo não é um backup do LifeOS.'); }
  if (header.format !== 'lifeos-backup') throw new BackupError('Este arquivo não é um backup do LifeOS.');
  if (header.version > 1) throw new BackupError('Backup criado por uma versão mais nova do LifeOS.');
  if (!password) throw new BackupError('Informe a senha do backup.');
  const key = await C.keyFromPassword(password, C.fromB64(header.salt), header.iterations);
  let bytes;
  try { bytes = await C.decryptBytes(key, C.fromB64(outer.data), C.enc.encode(outer.header)); }
  catch { throw new BackupError('Senha incorreta ou arquivo corrompido.'); }
  const json = await gunzip(bytes, header.compression);
  if ((await C.sha256Hex(json)) !== header.sha256) throw new BackupError('A verificação de integridade falhou: arquivo corrompido.');
  return JSON.parse(C.dec.decode(json));
}

export async function createBackup(password, includeFiles) {
  const { data, files } = await db.snapshot(includeFiles);
  return encryptPayload({ app: 'LifeOS', createdAt: new Date().toISOString(), data, files }, password);
}

export const isPlainExport = (text) => { try { return JSON.parse(text).format === 'lifeos-export'; } catch { return false; } };

export async function plainExport() {
  const { data } = await db.snapshot(false);
  return JSON.stringify({ format: 'lifeos-export', version: 1, createdAt: new Date().toISOString(), data }, null, 2);
}

export async function restore(payload) {
  await db.replaceAll(payload.data, payload.files || null);
}

export function summarize(payload) {
  const d = payload.data || {};
  const n = (k) => (d[k] || []).length;
  return [['Eventos', n('events')], ['Matérias', n('subjects')], ['Concursos', n('contests')], ['Transações', n('transactions')],
    ['Contas', n('recurring')], ['Treinos', n('workoutSessions')], ['Medidas', n('body')], ['Estoque', n('pantry')],
    ['Metas', n('goals')], ['Hábitos', n('habits')], ['Documentos', n('documents')]].filter(([, v]) => v > 0);
}

export const lastBackupDate = () => db.profile().lastBackup || null;
export const lastBackupLabel = () => { const d = lastBackupDate(); return d ? `${dateTime(d)}` : ''; };
export const markBackup = () => db.setProfile({ lastBackup: new Date().toISOString() });

export const backupFileName = () => `LifeOS-backup-${new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-')}.lifeosbackup`;

// ---------- CSV ----------
export function csvEscape(s) {
  let v = String(s ?? '');
  if (/^[=+\-@]/.test(v)) v = "'" + v; // evita injeção de fórmulas em planilhas
  if (/[;"\n]/.test(v)) v = '"' + v.replace(/"/g, '""') + '"';
  return v;
}
export function csv(header, rows) {
  return '﻿' + [header, ...rows].map((r) => r.map(csvEscape).join(';')).join('\n');
}
const n2 = (v) => (v === null || v === undefined || v === '' ? '' : Number(v).toFixed(2).replace('.', ','));

export const csvTransactions = (txs) => csv(['Data', 'Tipo', 'Categoria', 'Descrição', 'Valor', 'Parcela'],
  [...txs].sort((a, b) => new Date(a.date) - new Date(b.date)).map((t) => [shortDate(t.date), t.kind, t.category, t.title, n2(t.amount), t.installmentCount ? `${t.installmentNumber}/${t.installmentCount}` : '']));
export const csvBody = (items) => csv(['Data', 'Peso', 'Cintura', 'Braço', 'Peito', 'Perna', 'Quadril', 'Gordura %'],
  [...items].sort((a, b) => new Date(a.date) - new Date(b.date)).map((m) => [shortDate(m.date), n2(m.weight), n2(m.waist), n2(m.arm), n2(m.chest), n2(m.leg), n2(m.hip), n2(m.bodyFat)]));
export const csvWorkouts = (items) => csv(['Data', 'Treino', 'Exercício', 'Séries', 'Repetições', 'Carga (kg)'],
  [...items].sort((a, b) => new Date(a.date) - new Date(b.date)).flatMap((s) => (s.entries?.length ? s.entries : [{}]).map((e) => [shortDate(s.date), s.title, e.name || '', e.sets ?? '', e.reps ?? '', n2(e.load)])));
export const csvStudy = (items) => csv(['Data', 'Minutos', 'Observação'], items.map((s) => [shortDate(s.date), s.minutes, s.note || '']));
export const csvHabits = (habits) => csv(['Data', 'Hábito'], habits.flatMap((h) => (h.checkins || []).map((c) => [shortDate(c), h.name])));
