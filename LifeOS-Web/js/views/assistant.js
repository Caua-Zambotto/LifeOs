import * as db from '../store.js';
import * as D from '../domain.js';
import * as N from '../nlp.js';
import * as U from '../util.js';
import { esc } from '../util.js';
import { icon, form, confirmDialog, toast } from '../ui.js';

// Estado da conversa em andamento (não persistido): rascunho e campo que falta.
const conv = { draft: null, field: null };
const SUGGESTIONS = ['Gastei 25 reais no almoço', 'Tenho prova amanhã às 19h', 'Meu peso é 78 kg', 'Hoje treinei pernas',
  'Preciso revisar redes amanhã', 'Conta de luz vence dia 10 e custa 150 reais'];

const reply = (text, refs = []) => db.insert('chat', { role: 'assistant', text, date: new Date().toISOString(), refs, undone: false });

export function send(text) {
  const t = String(text || '').trim().slice(0, 500);
  if (!t) return;
  db.insert('chat', { role: 'user', text: t, date: new Date().toISOString(), refs: [] });
  if (conv.draft && /^(cancelar|cancela|esquece|deixa pra la|deixa pra lá|nao|não)$/i.test(t)) {
    conv.draft = null; conv.field = null; reply('Tudo bem, cancelei.'); return;
  }
  const ctx = D.interpreterContext();
  const r = conv.draft && conv.field ? N.complete(conv.draft, conv.field, t, ctx) : N.interpret(t, ctx);
  if (r.type === 'draft') { conv.draft = r.draft; conv.field = null; }
  else if (r.type === 'needsInfo') { conv.draft = r.draft; conv.field = r.field; reply(r.question); }
  else { conv.draft = null; conv.field = null; reply(r.help); }
}

function confirmDraft() {
  if (!conv.draft) return;
  const { refs, message } = D.saveDraft(conv.draft);
  reply(message, refs);
  conv.draft = null;
}

function editDraft() {
  const d = conv.draft;
  if (!d) return;
  const fin = ['expense', 'income', 'bill'].includes(d.kind);
  const fields = [{ name: 'title', label: 'Título', max: 200 }];
  if (fin || d.kind === 'groceries') fields.push({ name: 'amount', label: 'Valor (R$)', type: 'money' });
  if (fin) fields.push({ name: 'financeCategory', label: 'Categoria', type: 'select', options: Object.fromEntries(D.finCatsFor(d.kind === 'income' ? 'receita' : 'despesa').map((k) => [k, `${D.FIN_CATS[k].icon} ${D.FIN_CATS[k].label}`])) });
  if (d.kind === 'bill') fields.push({ name: 'recurrence', label: 'Repetição', type: 'select', options: D.RECURRENCES });
  if (d.kind === 'expense' && db.all('cards').length) {
    fields.push({ name: 'cardName', label: 'Cartão', type: 'select', options: Object.fromEntries([['', 'Nenhum (débito/dinheiro/Pix)'], ...db.all('cards').map((c) => [c.name, c.name])]) });
    fields.push({ name: 'installments', label: 'Parcelas', type: 'int', min: 1, maxv: 48, show: (v) => !!v.cardName });
  }
  if (d.kind === 'event') {
    fields.push({ name: 'eventCategory', label: 'Tipo', type: 'select', options: Object.fromEntries(Object.entries(D.EVENT_CATS).map(([k, v]) => [k, `${v.icon} ${v.label}`])) });
    fields.push({ name: 'hasTime', label: 'Definir horário', type: 'checkbox' });
    fields.push({ name: 'dateTime', label: 'Quando', type: 'datetime', show: (v) => v.hasTime });
    fields.push({ name: 'dateOnly', label: 'Quando', type: 'date', show: (v) => !v.hasTime });
    fields.push({ name: 'priority', label: 'Prioridade', type: 'select', options: D.PRIORITIES });
  } else if (d.kind !== 'groceries') fields.push({ name: 'dateOnly', label: 'Data', type: 'date' });
  if (d.kind === 'body') fields.push({ name: 'weight', label: 'Peso (kg)', type: 'decimal' });
  if (['studySession', 'workout'].includes(d.kind)) fields.push({ name: 'minutes', label: 'Duração (min)', type: 'int', min: 0 });
  if (d.kind === 'groceries') fields.push({ name: 'items', label: 'Itens (separados por vírgula)', type: 'textarea' });
  form({
    title: 'Editar registro', submitLabel: 'Aplicar', fields,
    values: { ...d, priority: String(d.priority), dateTime: d.date, dateOnly: d.date, cardName: d.cardName || '',
      items: d.items.map((i) => (i.quantity === 1 && i.unit === 'un' ? i.name : `${U.num(i.quantity)} ${i.unit} ${i.name}`)).join(', ') },
    onSubmit: (v) => {
      const n = { ...d, title: v.title || d.title };
      if ('amount' in v) n.amount = v.amount;
      if (v.financeCategory) n.financeCategory = v.financeCategory;
      if (v.recurrence) n.recurrence = v.recurrence;
      if ('cardName' in v) { n.cardName = v.cardName || null; n.installments = n.cardName ? Math.max(1, v.installments || 1) : 1; }
      if (d.kind === 'event') {
        n.eventCategory = v.eventCategory; n.hasTime = v.hasTime; n.priority = Number(v.priority);
        n.date = v.hasTime ? v.dateTime : v.dateOnly;
      } else if (v.dateOnly) n.date = v.dateOnly;
      if ('weight' in v) n.weight = v.weight;
      if ('minutes' in v) n.minutes = v.minutes;
      if ('items' in v) n.items = N.splitItems(v.items);
      const r = N.validate(n);
      if (r.type !== 'draft') return r.question;
      conv.draft = n;
    },
  });
}

function draftCard() {
  const d = conv.draft;
  if (!d || conv.field) return '';
  const cat = d.kind === 'event' ? D.EVENT_CATS[d.eventCategory] : null;
  const head = d.kind === 'event' ? 'Preparei este item para a agenda:' : d.kind === 'groceries' ? 'Vou adicionar ao seu estoque:' : `Preparei este registro de ${D.DRAFT_LABEL[d.kind]}:`;
  return `<div class="card draft"><div class="draft-h"><span class="badge" style="--c:${cat?.color || 'var(--accent)'}">${cat?.icon || '✨'}</span><b>${head}</b></div>
    <dl>${D.draftSummary(d).map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('')}</dl>
    <div class="draft-a"><button class="btn btn-primary grow" data-act="confirmDraft">${icon('check', 18)} Confirmar</button><button class="btn" data-act="editDraft">${icon('edit', 18)} Editar</button><button class="btn" data-act="cancelDraft" aria-label="Cancelar">${icon('close', 18)}</button></div></div>`;
}

export default {
  render() {
    const msgs = [...db.all('chat')].sort((a, b) => new Date(a.date) - new Date(b.date)).slice(-200);
    return `<header class="top"><h1>Assistente</h1><div class="top-a"><button class="icon-btn" data-act="clearChat" aria-label="Limpar conversa">${icon('trash')}</button></div></header>
    <div class="chat" id="chat">
      ${!msgs.length ? `<div class="card intro"><div class="row"><span class="avatar">✨</span><div><b>Seu assistente pessoal</b><small class="muted">Funciona offline. Nada sai do seu aparelho.</small></div></div>
        <p>Escreva naturalmente. Eu preparo o registro e você confirma antes de salvar.</p>
        <div class="chips">${SUGGESTIONS.map((s) => `<button class="chip" data-act="suggest" data-t="${esc(s)}">${esc(s)}</button>`).join('')}</div></div>` : ''}
      ${msgs.map((m) => `<div class="msg ${m.role}"><div class="bubble ${m.undone ? 'strike' : ''}">${esc(m.text).replace(/\n/g, '<br>')}</div>
        <small>${U.time(m.date)}${m.refs?.length && !m.undone ? ` · <button class="link" data-act="undo" data-id="${m.id}">${icon('undo', 14)} Desfazer</button>` : ''}${m.undone ? ' · desfeito' : ''}</small></div>`).join('')}
      ${draftCard()}
    </div>
    <form class="composer" data-submit="send"><textarea name="msg" id="composer" data-keep rows="1" maxlength="500" placeholder="${conv.field ? 'Responda aqui…' : 'Escreva o que aconteceu…'}" aria-label="Mensagem"></textarea>
      <button class="send" aria-label="Enviar">${icon('send')}</button></form>`;
  },
  after() {
    const c = document.getElementById('chat');
    if (c) c.scrollTop = c.scrollHeight;
    const ta = document.getElementById('composer');
    if (ta) {
      ta.onkeydown = (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); ta.form.requestSubmit(); } };
      ta.oninput = () => { ta.style.height = 'auto'; ta.style.height = Math.min(120, ta.scrollHeight) + 'px'; };
    }
  },
  submit: {
    send: (f) => { const v = f.msg.value; f.msg.value = ''; send(v); setTimeout(() => document.getElementById('composer')?.focus(), 30); },
  },
  actions: {
    suggest: (d) => { const ta = document.getElementById('composer'); ta.value = d.t; ta.focus(); return false; },
    confirmDraft,
    editDraft: () => { editDraft(); return false; },
    cancelDraft: () => { conv.draft = null; conv.field = null; reply('Ok, não salvei nada.'); },
    undo: (d) => {
      const m = db.get('chat', d.id);
      if (!m) return;
      D.undoRefs(m.refs);
      db.update('chat', m.id, { undone: true });
      reply('Registro desfeito.');
    },
    clearChat: async () => {
      if (await confirmDialog('Limpar o histórico da conversa? Os registros salvos continuam nas suas áreas.', { confirmLabel: 'Limpar' })) {
        db.removeWhere('chat', () => true); toast('Conversa limpa.');
      }
    },
  },
};
