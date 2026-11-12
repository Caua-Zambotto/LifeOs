// Sincronização entre aparelhos via Supabase (plano gratuito), usando só a API REST (sem SDK).
// Tudo sai do aparelho JÁ CIFRADO com a chave de dados (AES-256-GCM). A nuvem guarda apenas
// blocos ilegíveis: uma linha por coleção + os arquivos dos documentos.
// Mesclagem registro a registro: vale a última edição; exclusões são respeitadas.
import * as db from './store.js';
import { SYNC_DEFAULTS } from './config.js';
import { uid } from './util.js';

const META_CFG = 'syncConfig';
const META_AUTH = 'syncAuth';
const META_STATE = 'syncState';
const BUCKET = 'lifeos';
const TABLE = 'lifeos_blobs';
const VAULT_KEY = 'meta:vault';

export class SyncError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

// ---------- Status (para a interface) ----------
let status = { state: 'off', message: '', lastSync: null };
const statusListeners = new Set();
export const getStatus = () => status;
export function onStatus(fn) { statusListeners.add(fn); return () => statusListeners.delete(fn); }
function setStatus(patch) {
  status = { ...status, ...patch };
  statusListeners.forEach((fn) => { try { fn(status); } catch { /* */ } });
}

// ---------- Configuração e sessão ----------
export async function getConfig() {
  const c = (await db.getMeta(META_CFG)) || {};
  return { url: String(c.url || SYNC_DEFAULTS.url || '').trim().replace(/\/+$/, ''), anonKey: String(c.anonKey || SYNC_DEFAULTS.anonKey || '').trim() };
}
export const hasBuiltInConfig = () => !!(SYNC_DEFAULTS.url && SYNC_DEFAULTS.anonKey);

export async function saveConfig(url, anonKey) {
  const u = String(url || '').trim().replace(/\/+$/, '');
  let parsed;
  try { parsed = new URL(u); } catch { throw new SyncError(0, 'Endereço do projeto inválido.'); }
  const local = ['localhost', '127.0.0.1'].includes(parsed.hostname);
  if (parsed.protocol !== 'https:' && !local) throw new SyncError(0, 'O endereço precisa começar com https://');
  if (!anonKey || anonKey.trim().length < 20) throw new SyncError(0, 'Chave pública (anon key) inválida.');
  await db.putMeta(META_CFG, { url: u, anonKey: anonKey.trim() });
}

const getAuth = () => db.getMeta(META_AUTH);
export async function account() { const a = await getAuth(); return a?.user || null; }
export async function isConnected() { return !!(await getAuth())?.refresh_token; }

async function getState() { return (await db.getMeta(META_STATE)) || { lastPull: null, pushed: {}, files: [] }; }
const saveState = (s) => db.putMeta(META_STATE, s);
export const resetState = () => db.putMeta(META_STATE, { lastPull: null, pushed: {}, files: [] });

async function saveSession(j) {
  await db.putMeta(META_AUTH, {
    access_token: j.access_token, refresh_token: j.refresh_token,
    expires_at: Date.now() + Math.max(60, (j.expires_in || 3600) - 120) * 1000,
    user: { id: j.user?.id, email: j.user?.email },
  });
}

async function accessToken() {
  const a = await getAuth();
  if (!a?.refresh_token) throw new SyncError(401, 'Não conectado.');
  if (a.access_token && a.expires_at > Date.now()) return a.access_token;
  const res = await request('/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: { refresh_token: a.refresh_token }, auth: false });
  await saveSession(await res.json());
  return (await getAuth()).access_token;
}

async function request(path, { method = 'GET', body, headers = {}, auth = true } = {}) {
  const cfg = await getConfig();
  if (!cfg.url || !cfg.anonKey) throw new SyncError(0, 'Sincronização não configurada.');
  const h = { apikey: cfg.anonKey, ...headers };
  if (auth) h.Authorization = `Bearer ${await accessToken()}`;
  let payload = body;
  if (body !== undefined && !(body instanceof Uint8Array) && !(body instanceof Blob)) {
    h['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  let res;
  try { res = await fetch(cfg.url + path, { method, headers: h, body: payload, cache: 'no-store' }); }
  catch { throw new SyncError(-1, 'Sem conexão com a internet.'); }
  if (!res.ok) {
    let msg = '';
    try { const j = await res.json(); msg = j.msg || j.message || j.error_description || j.error || ''; } catch { /* */ }
    throw new SyncError(res.status, translate(res.status, msg));
  }
  return res;
}

function translate(code, msg) {
  const m = String(msg || '').toLowerCase();
  if (m.includes('invalid login')) return 'E-mail ou senha da conta incorretos.';
  if (m.includes('already registered') || m.includes('already been registered')) return 'Este e-mail já tem conta. Use "Entrar".';
  if (m.includes('email not confirmed')) return 'Confirme o e-mail (veja sua caixa de entrada) e depois toque em "Entrar".';
  if (m.includes('password should be')) return 'A senha da conta precisa ter pelo menos 6 caracteres.';
  if (code === 404 || m.includes('relation') || m.includes('does not exist')) return 'Tabela não encontrada: rode o script supabase/setup.sql no seu projeto.';
  if (code === 401 || code === 403) return 'Sessão expirada ou sem permissão. Entre novamente.';
  return msg || `Erro ${code}`;
}

// ---------- Conta ----------
export async function signUp(email, password) {
  const res = await request('/auth/v1/signup', { method: 'POST', body: { email, password }, auth: false });
  const j = await res.json();
  if (!j.access_token) return { needsConfirm: true };
  await saveSession(j);
  return { ok: true };
}

export async function signIn(email, password) {
  const res = await request('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password }, auth: false });
  await saveSession(await res.json());
  return { ok: true };
}

export async function signOut() {
  try { await request('/auth/v1/logout', { method: 'POST' }); } catch { /* sai localmente mesmo sem rede */ }
  await db.putMeta(META_AUTH, null);
  await resetState();
  setStatus({ state: 'off', message: '', lastSync: null });
}

// ---------- Tabela ----------
async function userId() { return (await getAuth())?.user?.id; }

async function upsertRows(rows) {
  const uidv = await userId();
  await request(`/rest/v1/${TABLE}?on_conflict=user_id,key`, {
    method: 'POST', body: rows.map((r) => ({ ...r, user_id: uidv })),
    headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
  });
}

export async function fetchRemoteVault() {
  const res = await request(`/rest/v1/${TABLE}?select=data&key=eq.${encodeURIComponent(VAULT_KEY)}`);
  const rows = await res.json();
  return rows[0] ? JSON.parse(rows[0].data) : null;
}

async function pushVault(meta) { await upsertRows([{ key: VAULT_KEY, data: JSON.stringify(meta), device: deviceName() }]); }

function deviceName() {
  const ua = navigator.userAgent;
  return /iPhone|iPad/.test(ua) ? 'iPhone/iPad' : /Android/.test(ua) ? 'Android' : /Windows/.test(ua) ? 'Windows' : 'Navegador';
}

/** Garante que o cofre local tenha um identificador (para reconhecer o mesmo cofre em outros aparelhos). */
async function localVault() {
  const v = await db.getVaultMeta();
  if (v && !v.id) { v.id = uid(); await db.putMeta('vault', v); }
  return v;
}

/**
 * Conecta ESTE aparelho (que já tem dados) à conta.
 * Retorna { ok } ou { conflict: true, remoteVault } quando a conta já tem dados de outro cofre.
 */
export async function connectExisting() {
  const local = await localVault();
  const remote = await fetchRemoteVault();
  if (!remote) {
    await pushVault(local);
    await resetState();
    await syncNow();
    return { ok: true };
  }
  if (remote.id && remote.id === local.id) {
    await resetState();
    await syncNow();
    return { ok: true };
  }
  return { conflict: true, remoteVault: remote };
}

/** Une os dados deste aparelho aos da conta, passando a usar o cofre (senha) da conta. */
export async function mergeIntoRemoteVault(remoteVault, password) {
  const ok = await db.adoptVault(remoteVault, password);
  if (!ok) return false;
  await resetState();
  await syncNow();
  return true;
}

/** Aparelho novo: baixa o cofre da conta. Depois, o usuário desbloqueia com a senha do LifeOS. */
export async function joinFromAccount() {
  const remote = await fetchRemoteVault();
  if (!remote) throw new SyncError(0, 'Esta conta ainda não tem dados. Ative a sincronização primeiro no aparelho onde você já usa o LifeOS.');
  await db.putMeta('vault', remote);
  await db.putMeta('auth', { fails: 0, lockUntil: 0 });
  await resetState();
}

/** Depois de trocar a senha do app: envia o novo "embrulho" da chave para os outros aparelhos. */
export async function pushVaultIfConnected() {
  if (await isConnected()) await pushVault(await localVault());
}

// ---------- Sincronização ----------
let running = false;
let again = false;

async function sha(text) {
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)));
  return [...h].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function syncNow() {
  if (!db.isUnlocked() || !(await isConnected())) return;
  if (running) { again = true; return; }
  running = true;
  setStatus({ state: 'syncing', message: '' });
  try {
    const st = await getState();
    const uidv = await userId();

    // 1) Baixa o que mudou desde a última vez e mescla.
    const since = st.lastPull || '1970-01-01T00:00:00Z';
    const res = await request(`/rest/v1/${TABLE}?select=key,data,updated_at&updated_at=gt.${encodeURIComponent(since)}&order=updated_at.asc`);
    const rows = await res.json();
    rows.sort((a, b) => (a.key === 'tombstones' ? -1 : b.key === 'tombstones' ? 1 : 0));
    let maxTs = st.lastPull;
    let unreadable = 0;
    for (const row of rows) {
      if (!maxTs || row.updated_at > maxTs) maxTs = row.updated_at;
      if (row.key === VAULT_KEY) {
        // Senha trocada em outro aparelho (mesmo cofre): guarda o novo "embrulho" da chave.
        try {
          const remote = JSON.parse(row.data);
          const local = await db.getVaultMeta();
          if (remote.id && local?.id === remote.id && remote.createdAt > (local.createdAt || '')) await db.putMeta('vault', remote);
        } catch { /* */ }
        continue;
      }
      if (!db.ALL_KEYS.includes(row.key)) continue;
      try { db.mergeRemote(row.key, await db.openValue(row.data)); } catch { unreadable++; }
    }
    if (unreadable) throw new SyncError(0, 'Os dados da nuvem usam outra chave. Desconecte e entre de novo neste aparelho.');
    st.lastPull = maxTs;
    await db.flush();

    // 2) Envia o que mudou aqui.
    const out = [];
    const hashes = {};
    for (const key of db.ALL_KEYS) {
      const text = JSON.stringify(db.getValue(key) ?? null);
      const h = await sha(text);
      if (st.pushed[key] !== h) { out.push({ key, data: await db.sealValue(db.getValue(key) ?? null), device: deviceName() }); hashes[key] = h; }
    }
    if (out.length) {
      await upsertRows(out);
      Object.assign(st.pushed, hashes);
    }

    // 3) Arquivos dos documentos (cifrados).
    const uploaded = new Set(st.files || []);
    for (const d of db.all('documents')) {
      if (uploaded.has(d.id)) continue;
      const sealed = await db.getSealedFile(d.id);
      if (!sealed) continue; // ainda não baixado neste aparelho
      await request(`/storage/v1/object/${BUCKET}/${uidv}/${d.id}`, {
        method: 'POST', body: sealed, headers: { 'Content-Type': 'application/octet-stream', 'x-upsert': 'true' },
      });
      uploaded.add(d.id);
    }
    const deleted = (db.getValue('tombstones') || {}).documents || {};
    for (const id of [...uploaded]) {
      if (deleted[id] && !db.get('documents', id)) {
        try { await request(`/storage/v1/object/${BUCKET}/${uidv}/${id}`, { method: 'DELETE' }); } catch { /* já removido */ }
        uploaded.delete(id);
      }
    }
    st.files = [...uploaded];
    await saveState(st);
    setStatus({ state: 'ok', message: '', lastSync: new Date().toISOString() });
  } catch (e) {
    setStatus({ state: e.status === -1 ? 'offline' : 'error', message: e.message || 'Falha na sincronização.' });
  } finally {
    running = false;
    if (again) { again = false; setTimeout(() => syncNow(), 500); }
  }
}

/** Baixa um arquivo de documento (cifrado) que ainda não está neste aparelho. */
async function fetchFile(id) {
  if (!(await isConnected())) return null;
  const res = await request(`/storage/v1/object/authenticated/${BUCKET}/${await userId()}/${id}`);
  const st = await getState();
  if (!(st.files || []).includes(id)) { st.files = [...(st.files || []), id]; await saveState(st); }
  return new Uint8Array(await res.arrayBuffer());
}

// ---------- Gatilhos automáticos ----------
let timer = null;
let debounce = null;
const soon = (ms = 2500) => { clearTimeout(debounce); debounce = setTimeout(() => syncNow(), ms); };

export async function start() {
  db.setFileFetcher(fetchFile);
  if (!(await isConnected())) { setStatus({ state: 'off' }); return; }
  clearInterval(timer);
  timer = setInterval(() => syncNow(), 60000);
  syncNow();
}

db.onFlushed(() => { if (!running) soon(); });
window.addEventListener('online', () => soon(500));
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') soon(500); });
