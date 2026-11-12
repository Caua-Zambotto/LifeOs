// Banco local: IndexedDB do navegador, com TODO o conteúdo cifrado (AES-256-GCM).
// Uma chave de dados aleatória (DEK) cifra as coleções; ela fica guardada "embrulhada"
// por uma chave derivada da senha do usuário (PBKDF2, 310 mil iterações).
// Ao bloquear, a DEK e os dados descriptografados são descartados da memória.

import * as C from './crypto.js';
import { uid } from './util.js';

export const COLLECTIONS = [
  'events', 'subjects', 'topics', 'grades', 'studySessions', 'contests', 'contestSubjects', 'questionLogs',
  'mockExams', 'transactions', 'cards', 'recurring', 'debts', 'savingsGoals', 'workoutPlans', 'workoutSessions',
  'body', 'pantry', 'recipes', 'cookLogs', 'goals', 'habits', 'documents', 'chat',
];

const DEFAULT_PROFILE = () => ({
  name: '', course: '', institution: '', semester: '', heightCm: null, targetWeight: null,
  initialBalance: 0, balanceDate: new Date().toISOString(), monthlySavingsTarget: 0,
  dashboard: null, favorites: [], autoLockSeconds: 120,
  notif: {}, notifDefaultHour: 8,
  weeklyStudyGoalMinutes: 600, weeklyWorkoutGoal: 4, homeSections: null,
});

/** Tudo o que é salvo/sincronizado: perfil, registros de exclusão e as coleções. */
export const ALL_KEYS = ['profile', 'tombstones', ...COLLECTIONS];

const ITERATIONS = 310000;
const DEK_AAD = C.enc.encode('lifeos-dek-v1');

let db = null;
let dek = null;
let state = null;
const dirty = new Set();
let saveTimer = null;
const listeners = new Set();

// ---------- IndexedDB ----------
function openDB() {
  if (db) return Promise.resolve(db);
  return new Promise((resolve, reject) => {
    const req = indexedDB.open('lifeos', 1);
    req.onupgradeneeded = () => {
      const d = req.result;
      for (const s of ['meta', 'data', 'files']) if (!d.objectStoreNames.contains(s)) d.createObjectStore(s);
    };
    req.onsuccess = () => { db = req.result; resolve(db); };
    req.onerror = () => reject(req.error);
  });
}

function tx(store, mode, fn) {
  return openDB().then((d) => new Promise((resolve, reject) => {
    const t = d.transaction(store, mode);
    const req = fn(t.objectStore(store)); // IDBRequest (leitura) ou undefined (escrita)
    t.oncomplete = () => resolve(req ? req.result : undefined);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  }));
}

const idbGet = (store, key) => tx(store, 'readonly', (s) => s.get(key));
const idbPut = (store, key, val) => tx(store, 'readwrite', (s) => { s.put(val, key); });
const idbDel = (store, key) => tx(store, 'readwrite', (s) => { s.delete(key); });
const idbClear = (store) => tx(store, 'readwrite', (s) => { s.clear(); });
const idbKeys = (store) => tx(store, 'readonly', (s) => s.getAllKeys());

export const getMeta = (k) => idbGet('meta', k);
export const putMeta = (k, v) => idbPut('meta', k, v);

// ---------- Cofre (senha) ----------
export async function isSetUp() { return !!(await getMeta('vault')); }
export const isUnlocked = () => !!dek && !!state;

function emptyState() {
  const s = { profile: DEFAULT_PROFILE(), tombstones: {} };
  for (const c of COLLECTIONS) s[c] = [];
  return s;
}

/** Somente para testes: estado em memória, sem gravar no disco. */
export function initMemory() { dek = null; state = emptyState(); }

export async function setup(password) {
  const salt = C.randomBytes(16);
  const raw = C.randomBytes(32);
  const kek = await C.keyFromPassword(password, salt, ITERATIONS);
  const wrapped = await C.encryptBytes(kek, raw, DEK_AAD);
  await putMeta('vault', { id: uid(), salt: C.toB64(salt), iterations: ITERATIONS, wrapped: C.toB64(wrapped), createdAt: new Date().toISOString() });
  await putMeta('auth', { fails: 0, lockUntil: 0 });
  dek = await C.aesKeyFromRaw(raw);
  state = emptyState();
  for (const k of ALL_KEYS) dirty.add(k);
  await flush();
  emit();
}

async function unwrapRaw(password) {
  const v = await getMeta('vault');
  if (!v) throw new Error('Nenhum cofre configurado.');
  const kek = await C.keyFromPassword(password, C.fromB64(v.salt), v.iterations);
  return C.decryptBytes(kek, C.fromB64(v.wrapped), DEK_AAD); // lança erro se a senha estiver errada
}

/** Retorna { ok } ou { ok:false, remaining, lockUntil }. */
export async function unlock(password) {
  const auth = (await getMeta('auth')) || { fails: 0, lockUntil: 0 };
  if (auth.lockUntil > Date.now()) return { ok: false, lockUntil: auth.lockUntil };
  let raw;
  try {
    raw = await unwrapRaw(password);
  } catch {
    auth.fails += 1;
    if (auth.fails >= 5) auth.lockUntil = Date.now() + Math.min(3600, 30 * 2 ** (auth.fails - 5)) * 1000;
    await putMeta('auth', auth);
    return { ok: false, remaining: Math.max(0, 5 - auth.fails), lockUntil: auth.lockUntil };
  }
  await putMeta('auth', { fails: 0, lockUntil: 0 });
  dek = await C.aesKeyFromRaw(raw);
  raw.fill(0);
  await loadAll();
  emit();
  return { ok: true };
}

/** Confirma a senha sem alterar o estado (para ações sensíveis). */
export async function verifyPassword(password) {
  try { (await unwrapRaw(password)).fill(0); return true; } catch { return false; }
}

export async function changePassword(oldPwd, newPwd) {
  const raw = await unwrapRaw(oldPwd);
  const salt = C.randomBytes(16);
  const kek = await C.keyFromPassword(newPwd, salt, ITERATIONS);
  const wrapped = await C.encryptBytes(kek, raw, DEK_AAD);
  raw.fill(0);
  const prev = (await getMeta('vault')) || {};
  // Mantém o identificador do cofre: a mesma chave de dados, só "embrulhada" com a nova senha.
  await putMeta('vault', { id: prev.id || uid(), salt: C.toB64(salt), iterations: ITERATIONS, wrapped: C.toB64(wrapped), createdAt: new Date().toISOString() });
}

export async function lock() {
  if (dek) await flush();
  dek = null;
  state = null;
  emit();
}

async function loadAll() {
  const s = emptyState();
  for (const k of ALL_KEYS) {
    const blob = await idbGet('data', k);
    if (blob) {
      const v = await C.decryptJSON(dek, blob);
      s[k] = k === 'profile' ? { ...DEFAULT_PROFILE(), ...v } : v;
    }
  }
  state = s;
}

// ---------- Persistência ----------
const flushListeners = new Set();
/** Avisado depois que chaves são gravadas (usado pela sincronização). */
export function onFlushed(fn) { flushListeners.add(fn); return () => flushListeners.delete(fn); }

export async function flush() {
  clearTimeout(saveTimer);
  if (!dek || !state) return;
  const keys = [...dirty];
  dirty.clear();
  for (const k of keys) {
    const blob = await C.encryptJSON(dek, state[k]);
    await idbPut('data', k, blob);
  }
  if (keys.length) flushListeners.forEach((fn) => { try { fn(keys); } catch { /* */ } });
}

function touch(col) {
  dirty.add(col);
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => flush().catch(() => {}), 250);
  emit();
}

export function onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); }
let emitQueued = false;
function emit() {
  if (emitQueued) return;
  emitQueued = true;
  queueMicrotask(() => { emitQueued = false; listeners.forEach((fn) => fn()); });
}

// ---------- API de dados ----------
export const profile = () => state.profile;
const nowISO = () => new Date().toISOString();

export function setProfile(patch) { Object.assign(state.profile, patch, { updatedAt: nowISO() }); touch('profile'); }

export const all = (col) => (state ? state[col] : []);
export const get = (col, id) => state[col].find((x) => x.id === id) || null;

// Cada registro guarda createdAt/updatedAt e cada exclusão deixa um "registro de exclusão"
// (tombstone). Assim dois aparelhos podem ser mesclados registro a registro.
export function insert(col, obj) {
  const t = nowISO();
  const o = { id: uid(), createdAt: t, ...obj, updatedAt: t };
  state[col].push(o);
  touch(col);
  return o;
}

export function update(col, id, patch) {
  const o = get(col, id);
  if (!o) return null;
  Object.assign(o, patch, { updatedAt: nowISO() });
  touch(col);
  return o;
}

function tombstone(col, ids) {
  if (!ids.length) return;
  const t = nowISO();
  const tb = (state.tombstones[col] ||= {});
  for (const id of ids) tb[id] = t;
  touch('tombstones');
}

export function remove(col, id) {
  const before = state[col].length;
  state[col] = state[col].filter((x) => x.id !== id);
  if (state[col].length !== before) { tombstone(col, [id]); touch(col); }
}

export function removeWhere(col, pred) {
  const gone = state[col].filter(pred).map((x) => x.id);
  if (!gone.length) return;
  state[col] = state[col].filter((x) => !pred(x));
  tombstone(col, gone);
  touch(col);
}

/** Marca uma coleção como alterada após mutação direta de objetos. */
export const changed = (col) => touch(col);

// ---------- Mesclagem (sincronização) ----------
const stamp = (r) => r?.updatedAt || r?.createdAt || '';

/** Junta registros de exclusão: vale a data mais recente. */
export function mergeTombstones(a = {}, b = {}) {
  const out = {};
  for (const src of [a, b]) {
    for (const [col, ids] of Object.entries(src || {})) {
      const t = (out[col] ||= {});
      for (const [id, ts] of Object.entries(ids || {})) if (!t[id] || ts > t[id]) t[id] = ts;
    }
  }
  return out;
}

/** Mescla duas versões de uma coleção: o registro editado por último vence; exclusões são respeitadas. */
export function mergeRecords(local = [], remote = [], tombs = {}) {
  const byId = new Map();
  for (const r of [...local, ...remote]) {
    if (!r || !r.id) continue;
    const cur = byId.get(r.id);
    if (!cur || stamp(r) > stamp(cur)) byId.set(r.id, r);
  }
  return [...byId.values()].filter((r) => !(tombs[r.id] && tombs[r.id] >= stamp(r)));
}

export const getValue = (key) => (state ? state[key] : undefined);

/** Aplica uma versão vinda da nuvem. Retorna true se o conteúdo local mudou. */
export function mergeRemote(key, remote) {
  if (!state) return false;
  const before = JSON.stringify(state[key]);
  if (key === 'tombstones') {
    state.tombstones = mergeTombstones(state.tombstones, remote);
    // aplica as exclusões recebidas em todas as coleções
    for (const col of COLLECTIONS) {
      const tb = state.tombstones[col] || {};
      const kept = state[col].filter((r) => !(tb[r.id] && tb[r.id] >= stamp(r)));
      if (kept.length !== state[col].length) { state[col] = kept; dirty.add(col); }
    }
  } else if (key === 'profile') {
    if (remote && stamp(remote) > stamp(state.profile)) state.profile = { ...DEFAULT_PROFILE(), ...remote };
  } else if (COLLECTIONS.includes(key)) {
    state[key] = mergeRecords(state[key], Array.isArray(remote) ? remote : [], state.tombstones[key] || {});
  } else return false;
  const changedNow = JSON.stringify(state[key]) !== before;
  if (changedNow) dirty.add(key);
  if (dirty.size) { clearTimeout(saveTimer); saveTimer = setTimeout(() => flush().catch(() => {}), 250); }
  if (changedNow) emit();
  return changedNow;
}

/** Cifra/decifra um valor com a chave de dados (para enviar à nuvem já cifrado). */
export async function sealValue(value) { return C.toB64(await C.encryptJSON(dek, value)); }
export async function openValue(b64) { return C.decryptJSON(dek, C.fromB64(b64)); }

export const getVaultMeta = () => getMeta('vault');

/** Arquivo cifrado "como está" (para enviar à nuvem sem decifrar). */
export const getSealedFile = (id) => idbGet('files', id);
export const putSealedFile = (id, sealed) => idbPut('files', id, sealed);

/**
 * Passa a usar o cofre de outro aparelho (mesma conta na nuvem).
 * Os dados locais são re-cifrados com a chave desse cofre e depois mesclados pela sincronização.
 */
export async function adoptVault(remoteMeta, password) {
  const kek = await C.keyFromPassword(password, C.fromB64(remoteMeta.salt), remoteMeta.iterations);
  let raw;
  try { raw = await C.decryptBytes(kek, C.fromB64(remoteMeta.wrapped), DEK_AAD); } catch { return false; }
  const newDek = await C.aesKeyFromRaw(raw);
  raw.fill(0);
  if (dek && state) {
    for (const id of await idbKeys('files')) {
      const sealed = await idbGet('files', id);
      try { await idbPut('files', id, await C.encryptBytes(newDek, await C.decryptBytes(dek, sealed))); } catch { /* arquivo ilegível */ }
    }
  } else {
    await idbClear('files');
  }
  dek = newDek;
  if (!state) state = emptyState();
  await putMeta('vault', remoteMeta);
  await putMeta('auth', { fails: 0, lockUntil: 0 });
  for (const k of ALL_KEYS) dirty.add(k);
  await flush();
  emit();
  return true;
}

// ---------- Arquivos (cofre de documentos) ----------
export async function putFile(id, bytes) { await idbPut('files', id, await C.encryptBytes(dek, bytes)); }
let fileFetcher = null;
/** Busca um arquivo cifrado na nuvem quando ele ainda não está neste aparelho. */
export function setFileFetcher(fn) { fileFetcher = fn; }

export async function getFile(id) {
  let blob = await idbGet('files', id);
  if (!blob && fileFetcher) {
    try {
      blob = await fileFetcher(id);
      if (blob) await idbPut('files', id, blob);
    } catch { blob = null; }
  }
  return blob ? C.decryptBytes(dek, blob) : null;
}
export const deleteFile = (id) => idbDel('files', id);
export const fileKeys = () => idbKeys('files');

// ---------- Snapshot / restauração / exclusão ----------
export async function snapshot(includeFiles) {
  const data = JSON.parse(JSON.stringify(state));
  let files = null;
  if (includeFiles) {
    files = {};
    for (const d of state.documents) {
      const b = await getFile(d.id);
      if (b) files[d.id] = C.toB64(b);
    }
  }
  return { data, files };
}

export async function replaceAll(data, files) {
  await idbClear('files');
  const s = emptyState();
  s.profile = { ...DEFAULT_PROFILE(), ...(data.profile || {}) };
  for (const c of COLLECTIONS) s[c] = Array.isArray(data[c]) ? data[c] : [];
  s.tombstones = data.tombstones && typeof data.tombstones === 'object' ? data.tombstones : {};
  // Marca tudo como atualizado agora, para que a restauração prevaleça na sincronização.
  const t = new Date().toISOString();
  for (const c of COLLECTIONS) for (const r of s[c]) r.updatedAt = t;
  s.profile.updatedAt = t;
  state = s;
  if (files) for (const [id, b64] of Object.entries(files)) await putFile(id, C.fromB64(b64));
  for (const k of ALL_KEYS) dirty.add(k);
  await flush();
  emit();
}

export async function wipeEverything() {
  dek = null;
  state = null;
  for (const s of ['meta', 'data', 'files']) await idbClear(s);
  try { localStorage.clear(); } catch { /* ignore */ }
  emit();
}

/** Uso de armazenamento estimado pelo navegador. */
export async function storageInfo() {
  const est = navigator.storage?.estimate ? await navigator.storage.estimate() : {};
  const persisted = navigator.storage?.persisted ? await navigator.storage.persisted() : false;
  return { usage: est.usage || 0, quota: est.quota || 0, persisted };
}

export async function requestPersistence() {
  return navigator.storage?.persist ? navigator.storage.persist() : false;
}
