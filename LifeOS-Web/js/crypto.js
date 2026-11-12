// Criptografia com a Web Crypto API nativa do navegador (sem bibliotecas).
// AES-256-GCM para dados; PBKDF2-SHA256 para derivar chaves de senhas.

const subtle = crypto.subtle;
export const enc = new TextEncoder();
export const dec = new TextDecoder();

export const randomBytes = (n) => crypto.getRandomValues(new Uint8Array(n));

export function toB64(bytes) {
  const u = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = '';
  for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
  return btoa(s);
}
export function fromB64(b64) {
  const s = atob(b64);
  const u = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) u[i] = s.charCodeAt(i);
  return u;
}

export async function sha256Hex(bytes) {
  const h = new Uint8Array(await subtle.digest('SHA-256', bytes));
  return [...h].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Deriva bits com PBKDF2-HMAC-SHA256. */
export async function pbkdf2Bits(password, salt, iterations, bits = 256) {
  const base = await subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  return new Uint8Array(await subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, base, bits));
}

export async function aesKeyFromRaw(raw, extractable = false) {
  return subtle.importKey('raw', raw, { name: 'AES-GCM' }, extractable, ['encrypt', 'decrypt']);
}

export async function keyFromPassword(password, salt, iterations) {
  return aesKeyFromRaw(await pbkdf2Bits(password, salt, iterations));
}

/** Retorna iv(12) | ciphertext+tag. */
export async function encryptBytes(key, bytes, aad) {
  const iv = randomBytes(12);
  const params = { name: 'AES-GCM', iv };
  if (aad) params.additionalData = aad;
  const ct = new Uint8Array(await subtle.encrypt(params, key, bytes));
  const out = new Uint8Array(12 + ct.length);
  out.set(iv, 0);
  out.set(ct, 12);
  return out;
}

export async function decryptBytes(key, data, aad) {
  const u = data instanceof Uint8Array ? data : new Uint8Array(data);
  const params = { name: 'AES-GCM', iv: u.subarray(0, 12) };
  if (aad) params.additionalData = aad;
  return new Uint8Array(await subtle.decrypt(params, key, u.subarray(12)));
}

export const encryptJSON = async (key, obj) => encryptBytes(key, enc.encode(JSON.stringify(obj)));
export const decryptJSON = async (key, data) => JSON.parse(dec.decode(await decryptBytes(key, data)));

/** Comparação em tempo constante. */
export function equalBytes(a, b) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

/** Avaliação simples de força de senha (0–4). */
export function passwordStrength(p) {
  let s = 0;
  if (p.length >= 8) s++;
  if (p.length >= 12) s++;
  if (/[a-z]/.test(p) && /[A-Z]/.test(p)) s++;
  if (/\d/.test(p) && /[^A-Za-z0-9]/.test(p)) s++;
  if (/^(.)\1+$/.test(p) || /^(12345678|password|senha123|qwerty)/i.test(p)) s = 0;
  return Math.min(4, s);
}
