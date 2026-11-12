// Cofre de documentos: cada arquivo é cifrado com a chave de dados antes de ir para o IndexedDB.
import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { form, empty, icon, confirmDialog, askPassword, toast, download, modal } from '../ui.js';

const MAX = 25 * 1024 * 1024;
const ui = { folder: null, search: '' };
const back = (to, label) => `<button class="back" data-act="nav" data-to="${to}">${icon('back', 18)} ${esc(label)}</button>`;

export function docRow(d) {
  return `<div class="card row"><span class="badge" style="--c:#14b8a6">${(D.DOC_CATS[d.category] || '📄').split(' ')[0]}</span>
    <div class="grow" data-act="openDoc" data-id="${d.id}"><b>${esc(d.title)} ${d.sensitive ? '🔒' : ''}</b><small>${esc(d.folder)} · ${U.bytes(d.size || 0)}</small></div>
    <button class="icon-btn" data-act="downloadDoc" data-id="${d.id}" aria-label="Exportar">${icon('download', 18)}</button>
    <button class="icon-btn" data-act="editDoc" data-id="${d.id}" aria-label="Editar">${icon('edit', 18)}</button></div>`;
}

export function importDocument(defaults = {}) {
  const folders = [...new Set(db.all('documents').map((d) => d.folder))];
  form({
    title: 'Guardar documento',
    values: { mode: 'arquivo', folder: defaults.folder || 'Geral', category: defaults.category || 'outro', sensitive: false },
    fields: [
      { name: 'mode', label: 'Tipo', type: 'select', options: { arquivo: 'Arquivo (PDF, imagem…)', nota: 'Anotação de texto' } },
      { name: 'file', label: 'Arquivo (máx. 25 MB)', type: 'file', accept: '.pdf,image/*,.txt,.doc,.docx,.xls,.xlsx', show: (v) => v.mode === 'arquivo' },
      { name: 'text', label: 'Texto', type: 'textarea', rows: 6, show: (v) => v.mode === 'nota' },
      { name: 'title', label: 'Título' },
      { name: 'folder', label: 'Pasta', list: folders },
      { name: 'category', label: 'Categoria', type: 'select', options: D.DOC_CATS },
      { name: 'sensitive', label: 'Sensível (pedir senha para abrir)', type: 'checkbox' },
      { name: 'notes', label: 'Observações' },
    ],
    submitLabel: 'Guardar',
    onSubmit: async (v) => {
      let bytes, name, mime;
      if (v.mode === 'arquivo') {
        if (!v.file) return 'Escolha um arquivo.';
        if (v.file.size > MAX) return 'Arquivo muito grande (máx. 25 MB).';
        bytes = new Uint8Array(await v.file.arrayBuffer());
        name = v.file.name; mime = v.file.type || 'application/octet-stream';
      } else {
        if (!v.text?.trim()) return 'Escreva o texto da anotação.';
        bytes = new TextEncoder().encode(v.text);
        name = (v.title || 'anotacao') + '.txt'; mime = 'text/plain;charset=utf-8';
      }
      const title = (v.title || name.replace(/\.[^.]+$/, '')).slice(0, 120);
      const doc = db.insert('documents', {
        title, folder: (v.folder || 'Geral').slice(0, 40), category: v.mode === 'nota' ? 'anotacao' : v.category,
        fileName: sanitize(name), mime, size: bytes.length, sensitive: v.sensitive, notes: v.notes || '',
        subjectId: defaults.subjectId || null, contestId: defaults.contestId || null,
      });
      try { await db.putFile(doc.id, bytes); } catch { db.remove('documents', doc.id); return 'Falha ao cifrar o arquivo.'; }
      toast('Documento guardado com criptografia.');
    },
  });
}

const sanitize = (n) => String(n).replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').replace(/\.\./g, '_').slice(0, 120) || 'arquivo';

async function withAccess(doc) {
  if (!doc.sensitive) return true;
  return askPassword('Este documento é sensível. Confirme sua senha para continuar.');
}

async function openDoc(id, asDownload) {
  const d = db.get('documents', id);
  if (!d || !(await withAccess(d))) return;
  const bytes = await db.getFile(d.id);
  if (!bytes) { toast('Arquivo não encontrado (não foi incluído no backup restaurado).'); return; }
  const blob = new Blob([bytes], { type: d.mime });
  if (asDownload) { download(d.fileName, blob); return; }
  if (d.mime.startsWith('text/')) {
    modal({ title: d.title, body: `<pre class="note">${esc(new TextDecoder().decode(bytes))}</pre>` });
  } else if (d.mime.startsWith('image/')) {
    const url = URL.createObjectURL(blob);
    modal({ title: d.title, wide: true, body: `<img class="doc-img" src="${url}" alt="${esc(d.title)}">`, onClose: () => URL.revokeObjectURL(url) });
  } else if (d.mime === 'application/pdf') {
    const url = URL.createObjectURL(blob);
    modal({ title: d.title, wide: true, body: `<iframe class="doc-pdf" src="${url}" title="${esc(d.title)}"></iframe><p class="muted small">Se o PDF não aparecer, use o botão de exportar.</p>`, onClose: () => URL.revokeObjectURL(url) });
  } else download(d.fileName, blob);
}

function editDoc(id) {
  const d = db.get('documents', id);
  form({
    title: 'Documento',
    values: { ...d, subjectId: d.subjectId || '', contestId: d.contestId || '' },
    fields: [
      { name: 'title', label: 'Título', required: true }, { name: 'folder', label: 'Pasta' },
      { name: 'category', label: 'Categoria', type: 'select', options: D.DOC_CATS },
      { name: 'sensitive', label: 'Sensível', type: 'checkbox' }, { name: 'notes', label: 'Observações' },
      { name: 'subjectId', label: 'Matéria', type: 'select', options: { '': 'Nenhuma', ...Object.fromEntries(db.all('subjects').map((s) => [s.id, s.name])) } },
      { name: 'contestId', label: 'Concurso', type: 'select', options: { '': 'Nenhum', ...Object.fromEntries(db.all('contests').map((c) => [c.id, c.organ])) } },
    ],
    onDelete: async () => { await db.deleteFile(d.id); db.remove('documents', d.id); },
    onSubmit: (v) => db.update('documents', d.id, { ...v, subjectId: v.subjectId || null, contestId: v.contestId || null }),
  });
}

export const docActions = {
  openDoc: (d) => { openDoc(d.id, false); return false; },
  downloadDoc: (d) => { openDoc(d.id, true); return false; },
  editDoc: (d) => { editDoc(d.id); return false; },
};

export const docs = {
  render() {
    const all = [...db.all('documents')].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    const folders = [...new Set(all.map((d) => d.folder))].sort();
    const q = U.fold(ui.search);
    const list = all.filter((d) => (!ui.folder || d.folder === ui.folder) && (!q || [d.title, d.notes, d.fileName, D.DOC_CATS[d.category]].some((x) => U.fold(x || '').includes(q))));
    return `${back('profile', 'Perfil')}<header class="top"><h1>Documentos</h1><div class="top-a"><button class="icon-btn accent" data-act="importDoc" aria-label="Adicionar">${icon('plus')}</button></div></header>
      <p class="muted small">🔐 Arquivos cifrados (AES-256) com a chave protegida pela sua senha.</p>
      <input class="search" data-keep id="docSearch" data-input="docSearch" placeholder="Buscar documentos" value="${esc(ui.search)}">
      <div class="chips"><button class="chip ${!ui.folder ? 'on' : ''}" data-act="folder" data-v="">Todos</button>${folders.map((f) => `<button class="chip ${ui.folder === f ? 'on' : ''}" data-act="folder" data-v="${esc(f)}">${esc(f)}</button>`).join('')}</div>
      ${list.map(docRow).join('') || empty('📂', 'Nenhum documento', 'Guarde editais, comprovantes, recibos e anotações com segurança.', 'importDoc', 'Adicionar')}`;
  },
  actions: {
    importDoc: () => { importDocument(); return false; },
    folder: (d) => { ui.folder = d.v || null; },
  },
  inputs: { docSearch: (v) => { ui.search = v; } },
};
