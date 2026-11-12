import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import * as N from '../nlp.js';
import { esc, money } from '../util.js';
import { form, seg, empty, icon, section, stat, confirmDialog, toast, download } from '../ui.js';
import { bars, hbars, line, donut, progress } from '../charts.js';
import { csvTransactions } from '../backup.js';

const ui = { monthOffset: 0, tab: 'resumo', period: 'mes', search: '', kind: 'todas', invoice: {} };

const TABS = { resumo: 'Resumo', movimentacoes: 'Movimentações', contas: 'Contas', cartoes: 'Cartões', dividas: 'Dívidas', metas: 'Metas', graficos: 'Gráficos' };
const catOptions = (kind) => Object.fromEntries(D.finCatsFor(kind).map((k) => [k, `${D.FIN_CATS[k].icon} ${D.FIN_CATS[k].label}`]));
const sortedTx = () => [...db.all('transactions')].sort((a, b) => new Date(b.date) - new Date(a.date));

// ---------- Editores ----------
export function transactionEditor(tx = null, kind = 'despesa') {
  const k = tx?.kind || kind;
  const cards = db.all('cards');
  const f = form({
    title: tx ? 'Editar movimentação' : (k === 'receita' ? 'Nova receita' : 'Nova despesa'),
    values: { kind: k, amount: tx?.amount ?? '', title: tx?.title || '', category: tx?.category || (k === 'receita' ? 'salario' : 'alimentacao'), date: tx ? new Date(tx.date) : new Date(), cardId: tx?.cardId || '', installments: 1, note: tx?.note || '' },
    fields: [
      ...(tx ? [] : [{ name: 'kind', label: 'Tipo', type: 'select', options: { despesa: 'Despesa', receita: 'Receita' } }]),
      { name: 'amount', label: 'Valor (R$)', type: 'money', required: true, placeholder: '0,00' },
      { name: 'title', label: 'Descrição', max: 120 },
      { name: 'category', label: 'Categoria', type: 'select', options: { ...catOptions('despesa'), ...catOptions('receita') } },
      { name: 'date', label: 'Data', type: 'date', required: true },
      ...(cards.length && !tx?.installmentGroup ? [{ name: 'cardId', label: 'Cartão de crédito', type: 'select', options: { '': 'Débito / dinheiro / Pix', ...Object.fromEntries(cards.map((c) => [c.id, c.name])) }, show: (v) => (v.kind || k) === 'despesa' }] : []),
      ...(!tx && cards.length ? [{ name: 'installments', label: 'Parcelas', type: 'int', min: 1, maxv: 48, show: (v) => v.kind === 'despesa' && !!v.cardId }] : []),
      { name: 'note', label: 'Observação', type: 'textarea', rows: 2 },
    ],
    onDelete: tx ? () => db.remove('transactions', tx.id) : null,
    onSubmit: (v) => {
      if (!(v.amount > 0) || v.amount > 1e7) return 'Informe um valor válido.';
      const kind2 = v.kind || k;
      if (D.FIN_CATS[v.category]?.kind !== kind2) return `A categoria escolhida não é de ${kind2}.`;
      const title = v.title || D.FIN_CATS[v.category].label;
      if (tx) db.update('transactions', tx.id, { title, amount: v.amount, category: v.category, date: v.date.toISOString(), note: v.note, ...(tx.installmentGroup ? {} : { cardId: kind2 === 'despesa' ? v.cardId || null : null }) });
      else {
        const d = new Date(v.date); const n = new Date(); d.setHours(n.getHours(), n.getMinutes());
        D.addTransaction({ title, amount: v.amount, kind: kind2, category: v.category, date: d.toISOString(), cardId: kind2 === 'despesa' ? v.cardId || null : null, installments: v.installments || 1, note: v.note });
      }
    },
  });
  // Sugere a categoria pela descrição (até o usuário escolher uma manualmente).
  const titleEl = f.el.querySelector('[name=title]');
  const catEl = f.el.querySelector('[name=category]');
  const kindEl = f.el.querySelector('[name=kind]');
  let manual = !!tx;
  catEl.addEventListener('change', () => { manual = true; });
  const suggest = () => {
    if (manual) return;
    const kind2 = kindEl ? kindEl.value : k;
    const g = kind2 === 'receita' ? N.guessIncome(U.fold(titleEl.value)) : N.guessExpense(U.fold(titleEl.value));
    if (g !== 'outros' && g !== 'outrasReceitas') catEl.value = g;
    else if (D.FIN_CATS[catEl.value]?.kind !== kind2) catEl.value = kind2 === 'receita' ? 'salario' : 'outros';
  };
  titleEl.addEventListener('input', suggest);
  kindEl?.addEventListener('change', suggest);
}

function recurringEditor(r = null) {
  form({
    title: r ? 'Editar conta' : 'Nova conta ou receita prevista',
    values: { kind: r?.kind || 'despesa', title: r?.title || '', amount: r?.amount ?? '', category: r?.category || 'moradia', dueDate: r ? new Date(r.dueDate) : new Date(), recurrence: r?.recurrence || 'mensal', notify: r?.notify ?? true },
    fields: [
      { name: 'kind', label: 'Tipo', type: 'select', options: { despesa: 'Conta a pagar', receita: 'Receita prevista (ex.: salário)' } },
      { name: 'title', label: 'Nome', required: true, placeholder: 'Ex.: Internet' },
      { name: 'amount', label: 'Valor (R$)', type: 'money', required: true },
      { name: 'category', label: 'Categoria', type: 'select', options: { ...catOptions('despesa'), ...catOptions('receita') } },
      { name: 'dueDate', label: 'Próximo vencimento / data prevista', type: 'date', required: true },
      { name: 'recurrence', label: 'Repetição', type: 'select', options: { nenhuma: 'Uma vez', semanal: 'Semanal', mensal: 'Mensal', anual: 'Anual' } },
      { name: 'notify', label: 'Lembrar antes do vencimento', type: 'checkbox', show: (v) => v.kind === 'despesa' },
    ],
    onDelete: r ? () => db.remove('recurring', r.id) : null,
    onSubmit: (v) => {
      if (!(v.amount > 0)) return 'Informe o valor.';
      if (D.FIN_CATS[v.category]?.kind !== v.kind) return 'Escolha uma categoria compatível com o tipo.';
      const data = { kind: v.kind, title: v.title, amount: v.amount, category: v.category, dueDate: v.dueDate.toISOString(), recurrence: v.recurrence, notify: v.notify, isActive: true };
      if (r) db.update('recurring', r.id, data); else db.insert('recurring', data);
    },
  });
}

function cardEditor(c = null) {
  form({
    title: c ? 'Editar cartão' : 'Novo cartão',
    intro: '<p class="muted small">Use só um apelido. Nunca informe número, CVV ou senha do cartão.</p>',
    values: { name: c?.name || '', limit: c?.limit ?? '', closingDay: c?.closingDay ?? 1, dueDay: c?.dueDay ?? 10, color: c?.color || '#1c1c1e' },
    fields: [
      { name: 'name', label: 'Apelido', required: true, max: 30, placeholder: 'Ex.: Nubank' },
      { name: 'limit', label: 'Limite (R$)', type: 'money' },
      { name: 'closingDay', label: 'Dia do fechamento', type: 'int', min: 1, maxv: 31, required: true },
      { name: 'dueDay', label: 'Dia do vencimento', type: 'int', min: 1, maxv: 31, required: true },
      { name: 'color', label: 'Cor', type: 'color', options: ['#1c1c1e', '#820ad1', '#ec7000', '#cc092f', '#0f766e', '#1d4ed8', '#b45309', '#475569'] },
    ],
    onDelete: c ? () => { db.all('transactions').filter((t) => t.cardId === c.id && !t.isInvoicePayment).forEach((t) => db.update('transactions', t.id, { cardId: null })); db.remove('cards', c.id); } : null,
    onSubmit: (v) => {
      if (v.closingDay < 1 || v.closingDay > 31 || v.dueDay < 1 || v.dueDay > 31) return 'Dias devem estar entre 1 e 31.';
      const data = { name: v.name, limit: v.limit || 0, closingDay: v.closingDay, dueDay: v.dueDay, color: v.color };
      if (c) db.update('cards', c.id, data); else db.insert('cards', data);
    },
  });
}

function debtEditor(d = null) {
  form({
    title: d ? 'Editar dívida' : 'Nova dívida',
    values: { creditor: d?.creditor || '', original: d?.original ?? '', remainingAmount: d?.remainingAmount ?? '', monthlyPayment: d?.monthlyPayment ?? '', interest: d?.interest ?? '', dueDay: d?.dueDay ?? 10 },
    fields: [
      { name: 'creditor', label: 'Credor', required: true, placeholder: 'Ex.: Empréstimo banco' },
      { name: 'original', label: 'Valor original (R$)', type: 'money', required: true },
      { name: 'remainingAmount', label: 'Saldo devedor atual (R$)', type: 'money' },
      { name: 'monthlyPayment', label: 'Parcela mensal (R$)', type: 'money' },
      { name: 'interest', label: 'Juros ao mês (%) — opcional', type: 'decimal' },
      { name: 'dueDay', label: 'Dia do vencimento', type: 'int', min: 1, maxv: 31 },
    ],
    onDelete: d ? () => db.remove('debts', d.id) : null,
    onSubmit: (v) => {
      if (!(v.original > 0)) return 'Informe o valor original.';
      const data = { creditor: v.creditor, original: v.original, remainingAmount: Math.min(v.remainingAmount ?? v.original, v.original), monthlyPayment: v.monthlyPayment || 0, interest: v.interest || 0, dueDay: v.dueDay || 10 };
      if (d) db.update('debts', d.id, data); else db.insert('debts', { ...data, payments: [] });
    },
  });
}

export function balanceEditor() {
  const p = db.profile();
  form({
    title: 'Saldo e economia',
    intro: '<p class="muted small">Informe o saldo real da sua conta em uma data. Daí em diante o LifeOS soma receitas e subtrai despesas. Nenhuma conexão com banco é feita.</p>',
    values: { initialBalance: p.initialBalance, balanceDate: new Date(p.balanceDate), monthlySavingsTarget: p.monthlySavingsTarget || '' },
    fields: [
      { name: 'initialBalance', label: 'Saldo (R$)', type: 'money' },
      { name: 'balanceDate', label: 'Na data', type: 'date', required: true },
      { name: 'monthlySavingsTarget', label: 'Meta de economia mensal (R$)', type: 'money', help: 'Descontada do quanto você pode gastar por semana.' },
    ],
    onSubmit: (v) => db.setProfile({ initialBalance: v.initialBalance || 0, balanceDate: U.startOfDay(v.balanceDate).toISOString(), monthlySavingsTarget: Math.max(0, v.monthlySavingsTarget || 0) }),
  });
}

// ---------- Componentes ----------
export function txRow(t) {
  const c = D.FIN_CATS[t.category] || D.FIN_CATS.outros;
  const card = t.cardId && db.get('cards', t.cardId);
  return `<div class="card row" data-act="editTx" data-id="${t.id}"><span class="badge" style="--c:${c.color}">${c.icon}</span>
    <div class="grow"><b>${esc(t.title)}</b><small>${U.capFirst(U.relDay(t.date))}${card ? ' · ' + esc(card.name) : ''}</small></div>
    <b class="${t.kind === 'receita' ? 'green' : ''} num">${U.signedMoney(D.signed(t))}</b></div>`;
}

function monthCompare(txs, offset) {
  const m = U.addMonths(U.startOfMonth(new Date()), offset);
  const cur = { start: m, end: offset === 0 ? new Date() : U.addMonths(m, 1) };
  const prev = { start: U.addMonths(m, -1), end: m };
  const inc = D.income(txs, cur), out = D.spending(txs, cur);
  const pOut = D.spending(txs, prev);
  const max = Math.max(inc, out, 1);
  const delta = pOut ? (out - pOut) / pOut : null;
  return { m, cur, inc, out, res: inc - out, max, delta };
}

/** Contas e faturas que vencem nos próximos 10 dias (ou já venceram). */
function billsDue() {
  const until = U.addDays(U.startOfDay(new Date()), 11);
  return db.all('recurring').filter((r) => r.isActive && r.kind === 'despesa' && new Date(r.dueDate) < until)
    .sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
}

function resumo() {
  const now = new Date();
  const p = D.weeklyPlan(now);
  const txs = db.all('transactions');
  const mc = monthCompare(txs, ui.monthOffset);
  const cats = D.byCategory(txs, mc.cur);
  const total = cats.reduce((a, c) => a + c.total, 0);
  const recent = sortedTx().slice(0, 6);
  const due = billsDue();
  const bar = (label, v, color) => `<div class="mbar"><span>${label}</span><div class="mbar-t"><i style="width:${Math.max(2, (v / mc.max) * 100)}%;background:${color}"></i></div><b class="num">${money(v)}</b></div>`;
  return `
    <div class="grad g-finance" data-act="balance"><div class="grow"><small>Saldo disponível ✎</small><h1 class="num">${money(p.balance)}</h1>
      <small>${p.overBudget ? `Passou ${money(-p.remaining)} do planejado na semana` : `Pode gastar ${money(Math.max(0, p.remaining))} nesta semana`}</small></div></div>
    <div class="quick">
      <button data-act="newTx" data-k="despesa"><span class="badge" style="--c:#ef4444">⬆</span>Despesa</button>
      <button data-act="newTx" data-k="receita"><span class="badge" style="--c:#22c55e">⬇</span>Receita</button>
      <button data-act="tab" data-v="contas"><span class="badge" style="--c:#f97316">📆</span>Contas</button>
      <button data-act="tab" data-v="cartoes"><span class="badge" style="--c:#6366f1">💳</span>Cartões</button></div>
    <div class="card">
      <div class="cal-h"><button class="icon-btn" data-act="finMonth" data-n="-1" aria-label="Mês anterior">${icon('back')}</button><b>${U.monthYear(mc.m)}</b>
        <button class="icon-btn" data-act="finMonth" data-n="1" aria-label="Próximo mês" ${ui.monthOffset >= 0 ? 'disabled' : ''}>${icon('chevron')}</button></div>
      ${bar('Entradas', mc.inc, '#22c55e')}${bar('Saídas', mc.out, '#ef4444')}
      <div class="row-sb mres"><span>Resultado do mês</span><b class="num ${mc.res < 0 ? 'red' : 'green'}">${mc.res < 0 ? '−' : '+'}${money(Math.abs(mc.res))}</b></div>
      ${mc.delta !== null ? `<small class="muted">Gastos ${mc.delta > 0 ? `${U.pct(mc.delta)} maiores` : `${U.pct(-mc.delta)} menores`} que no mês anterior</small>` : ''}</div>
    <div class="card" data-act="tab" data-v="planejamento"><div class="row-sb"><b>Posso gastar nesta semana</b>${icon('chevron', 18)}</div>
      <div class="big num ${p.overBudget ? 'red' : ''}">${money(Math.max(0, p.remaining))} <small class="muted">de ${money(p.weeklyAllowance)}</small></div>
      ${progress(p.weeklyAllowance ? p.spentThisWeek / p.weeklyAllowance : 0, p.overBudget ? '#ef4444' : '#10b981')}</div>
    ${section('Contas a vencer', 'tab', 'Ver todas', 'data-v="contas"')}
    ${due.length ? `<div class="card">${due.map((r) => { const d = U.daysUntil(r.dueDate); return `<div class="li"><span class="badge sm" style="--c:${D.FIN_CATS[r.category]?.color || '#f97316'}">${D.FIN_CATS[r.category]?.icon || '📆'}</span>
      <div class="grow" data-act="editRec" data-id="${r.id}"><b>${esc(r.title)}</b><small class="${d < 0 ? 'red' : ''}">${d < 0 ? `Venceu há ${-d} dia(s)` : d === 0 ? 'Vence hoje' : `Vence ${U.relDay(r.dueDate)}`}</small></div>
      <b class="num">${money(r.amount)}</b><button class="btn btn-sm btn-primary" data-act="settle" data-id="${r.id}">Pagar</button></div>`; }).join('')}</div>`
      : '<p class="muted">Nenhuma conta vencendo nos próximos 10 dias.</p>'}
    <div class="card"><h3>Para onde foi o dinheiro</h3>${cats.length ? `<div class="donut-row">${donut(cats.map((c) => ({ label: D.FIN_CATS[c.category].label, value: c.total, color: D.FIN_CATS[c.category].color })), { center: money(total), sub: 'Total' })}</div>
      <div class="rank">${cats.map((c, i) => `<div class="rank-i"><span class="muted">${i + 1}</span><span class="grow">${D.FIN_CATS[c.category].icon} ${D.FIN_CATS[c.category].label}</span><b class="num">${money(c.total)}</b><small class="muted">${U.pct(c.total / total)}</small>
        <div class="rank-bar">${progress(c.total / cats[0].total, D.FIN_CATS[c.category].color)}</div></div>`).join('')}</div>` : '<p class="muted">Sem despesas neste mês.</p>'}</div>
    ${section('Últimas movimentações', 'tab', 'Ver todas', 'data-v="movimentacoes"')}
    ${recent.length ? recent.map(txRow).join('') : empty('🧾', 'Sem movimentações', 'Registre um gasto pelo + ou diga "gastei 35 reais no almoço".')}`;
}

function planejamento() {
  const p = D.weeklyPlan();
  const row = (l, v, cls = '') => `<div class="row-sb ${cls}"><span>${l}</span><b class="num">${money(v)}</b></div>`;
  return `<div class="grad ${p.overBudget ? 'g-body' : 'g-finance'}"><div class="grow"><small>Você pode gastar por semana</small><h1 class="num">${money(p.weeklyAllowance)}</h1>
    <small>Restam ${money(p.remaining)} nesta semana · ${p.weeksRemaining} semana(s) até o fim do mês</small></div></div>
    <div class="card lines">${row('Saldo atual', p.balance)}${row('+ Receitas previstas no mês', p.expectedIncome, 'green')}${row('− Contas pendentes no mês', -p.pendingBills, 'red')}
      ${row('− Parcelas de dívidas', -p.debtPayments, 'red')}${row('− Faturas de cartão em aberto', -p.cardInvoices, 'red')}${row('− Meta de economia', -p.savingsTarget, 'red')}
      <hr>${row('= Disponível até o fim do mês', p.available, 'bold')}${row('Gasto nesta semana', p.spentThisWeek)}</div>
    <p class="muted small">O cálculo parte do saldo informado, soma receitas previstas e desconta tudo o que ainda precisa ser pago no mês. O resultado é dividido pelas semanas restantes. Você recebe um aviso quando passa do valor da semana.</p>
    <button class="btn" data-act="balance">Ajustar saldo e meta de economia</button>`;
}

function movimentacoes() {
  const q = U.fold(ui.search);
  const list = sortedTx().filter((t) => (ui.kind === 'todas' || t.kind === ui.kind) && (!q || U.fold(t.title).includes(q) || U.fold(D.FIN_CATS[t.category]?.label || '').includes(q)));
  const groups = {};
  for (const t of list) (groups[U.dateKey(t.date)] ||= []).push(t);
  return `<div class="toolbar"><input class="search" data-keep id="txSearch" data-input="txSearch" placeholder="Buscar" value="${esc(ui.search)}">
    <button class="btn btn-sm" data-act="exportCsv">${icon('download', 16)} CSV</button></div>
    ${seg('kind', { todas: 'Todas', receita: 'Receitas', despesa: 'Despesas' }, ui.kind)}
    ${Object.entries(groups).map(([k, items]) => `<h4 class="day-h">${U.fullDate(U.fromDateKey(k))}</h4>${items.map(txRow).join('')}`).join('') || empty('🔍', 'Nada encontrado', 'Ajuste o filtro ou a busca.')}`;
}

function contas() {
  const active = db.all('recurring').filter((r) => r.isActive).sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
  const rowR = (r) => `<div class="card row"><span class="badge" style="--c:${D.FIN_CATS[r.category]?.color}">${D.FIN_CATS[r.category]?.icon}</span>
    <div class="grow" data-act="editRec" data-id="${r.id}"><b>${esc(r.title)}</b><small class="${new Date(r.dueDate) < U.startOfDay(new Date()) ? 'red' : ''}">${r.kind === 'receita' ? 'Previsto' : 'Vence'} ${U.relDay(r.dueDate)} · ${D.RECURRENCES[r.recurrence] || 'Uma vez'}</small></div>
    <b class="num">${money(r.amount)}</b><button class="btn btn-sm" data-act="settle" data-id="${r.id}">${r.kind === 'receita' ? 'Recebido' : 'Pago'}</button></div>`;
  const bills = active.filter((r) => r.kind === 'despesa'), incomes = active.filter((r) => r.kind === 'receita');
  const fixed = bills.filter((r) => r.recurrence === 'mensal').reduce((a, r) => a + r.amount, 0);
  return `<div class="toolbar"><span class="muted">Despesas fixas mensais: <b>${money(fixed)}</b></span><button class="btn btn-primary btn-sm" data-act="newRec">${icon('plus', 16)} Nova</button></div>
    ${section('Contas a pagar')}${bills.map(rowR).join('') || '<p class="muted">Nenhuma conta cadastrada.</p>'}
    ${section('Receitas previstas')}${incomes.map(rowR).join('') || '<p class="muted">Cadastre seu salário para melhorar o planejamento.</p>'}`;
}

function cartoes() {
  const cards = db.all('cards');
  if (!cards.length) return empty('💳', 'Nenhum cartão', 'Cadastre seus cartões para controlar faturas e parcelamentos.', 'newCard', 'Adicionar cartão');
  return `<div class="toolbar"><span></span><button class="btn btn-primary btn-sm" data-act="newCard">${icon('plus', 16)} Cartão</button></div>` + cards.map((c) => {
    const now = new Date();
    const month = ui.invoice[c.id] ? new Date(ui.invoice[c.id]) : D.invoiceMonth(now, c.closingDay);
    const items = db.all('transactions').filter((t) => t.cardId === c.id && !t.isInvoicePayment && D.invoiceMonth(t.date, c.closingDay).getTime() === month.getTime()).sort((a, b) => new Date(b.date) - new Date(a.date));
    const out = D.outstanding(c, now), used = out + D.futureInstallments(c, now);
    const hist = [5, 4, 3, 2, 1, 0].map((i) => { const m = U.addMonths(D.invoiceMonth(now, c.closingDay), -i); return { label: U.monthShort(m), value: D.invoiceTotal(c, m) }; });
    return `<div class="ccard" style="--c:${c.color}" data-act="editCard" data-id="${c.id}"><div class="row-sb"><b>${esc(c.name)}</b><span>💳</span></div>
      <small>Fatura atual</small><h2 class="num">${money(D.invoiceTotal(c, D.invoiceMonth(now, c.closingDay)))}</h2>
      ${c.limit ? `${progress(used / c.limit, '#fff')}<small>Limite usado ${money(used)} de ${money(c.limit)}</small>` : ''}
      <small>Fecha dia ${c.closingDay} · vence dia ${c.dueDay}</small></div>
      <div class="card"><div class="cal-h"><button class="icon-btn" data-act="invMonth" data-id="${c.id}" data-m="${U.addMonths(month, -1).toISOString()}">${icon('back')}</button>
        <b>Fatura de ${U.monthYear(month)}</b><button class="icon-btn" data-act="invMonth" data-id="${c.id}" data-m="${U.addMonths(month, 1).toISOString()}">${icon('chevron')}</button></div>
        ${items.map((t) => `<div class="li" data-act="editTx" data-id="${t.id}"><div class="grow"><b>${esc(t.title)}</b><small>${U.dayMonth(t.date)}</small></div><b class="num">${money(t.amount)}</b></div>`).join('') || '<p class="muted">Nenhuma compra nesta fatura.</p>'}
        <div class="row-sb"><span>Total da fatura</span><b>${money(items.reduce((a, t) => a + t.amount, 0))}</b></div>
        <div class="row-sb"><span>Em aberto (até hoje)</span><b>${money(out)}</b></div>
        ${out > 0 ? `<button class="btn btn-primary wide" data-act="payInvoice" data-id="${c.id}">Registrar pagamento de ${money(out)}</button>` : ''}
        <h4>Últimas faturas</h4>${bars(hist, { height: 110, color: c.color, format: money })}</div>`;
  }).join('');
}

function dividas() {
  const debts = db.all('debts');
  const total = debts.reduce((a, d) => a + d.remainingAmount, 0);
  const monthly = debts.filter((d) => d.remainingAmount > 0).reduce((a, d) => a + (d.monthlyPayment || 0), 0);
  return `<div class="grad g-body"><div class="grow"><small>Total em dívidas</small><h1 class="num">${money(total)}</h1><small>Parcelas mensais: ${money(monthly)}</small></div></div>
    <div class="toolbar"><span></span><button class="btn btn-primary btn-sm" data-act="newDebt">${icon('plus', 16)} Dívida</button></div>
    ${debts.length ? debts.map((d) => {
      const p = d.original ? Math.min(1, 1 - d.remainingAmount / d.original) : 0;
      const pts = (d.payments || []).map((x) => ({ x: x.date, y: x.remainingAfter }));
      const months = d.monthlyPayment > 0 && d.remainingAmount > 0 ? Math.ceil(d.remainingAmount / d.monthlyPayment) : null;
      return `<div class="card"><div class="row-sb" data-act="editDebt" data-id="${d.id}"><b>${esc(d.creditor)}</b><b class="num">${money(d.remainingAmount)}</b></div>
        ${progress(p, '#22c55e')}<div class="row-sb"><small class="muted">${U.pct(p)} quitado · parcela ${money(d.monthlyPayment || 0)} · dia ${d.dueDay}</small>
        ${d.remainingAmount > 0 ? `<button class="btn btn-sm" data-act="payDebt" data-id="${d.id}">Pagar</button>` : '<small class="green">Quitada ✓</small>'}</div>
        ${months ? `<small class="muted">Previsão de quitação: ${U.monthYear(U.addMonths(new Date(), months))} (sem considerar juros)</small>` : ''}
        ${pts.length >= 2 ? line(pts, { height: 100, color: '#ef4444', format: money }) : ''}</div>`;
    }).join('') : empty('✅', 'Sem dívidas cadastradas', 'Cadastre empréstimos, acordos e financiamentos para acompanhar a quitação.', 'newDebt', 'Adicionar dívida')}`;
}

function metas() {
  const goals = db.all('savingsGoals');
  return `<div class="toolbar"><span></span><button class="btn btn-primary btn-sm" data-act="newSaving">${icon('plus', 16)} Meta</button></div>
    ${goals.length ? goals.map((g) => {
      const p = g.target ? Math.min(1, g.saved / g.target) : 0;
      return `<div class="card"><div class="row-sb"><b>${esc(g.title)}</b><b class="teal">${U.pct(p)}</b></div>${progress(p, '#14b8a6')}
        <div class="row-sb"><small class="muted">${money(g.saved)} de ${money(g.target)}</small><span><button class="btn btn-sm" data-act="deposit" data-id="${g.id}">Guardar/retirar</button>
        <button class="icon-btn" data-act="delSaving" data-id="${g.id}" aria-label="Excluir">${icon('trash', 18)}</button></span></div></div>`;
    }).join('') : empty('🎯', 'Nenhuma meta', 'Ex.: reserva de emergência, viagem, notebook.', 'newSaving', 'Criar meta')}`;
}

export function financeCharts(period) {
  const now = new Date();
  const interval = U.periodInterval(period, now);
  const txs = db.all('transactions');
  const months = [];
  for (let m = U.startOfMonth(interval.start); m <= interval.end; m = U.addMonths(m, 1)) months.push(m);
  const weeks = [];
  for (let w = U.startOfWeek(interval.start); w <= interval.end; w = U.addDays(w, 7)) weeks.push(w);
  const p = db.profile();
  const io = months.flatMap((m) => {
    const mi = { start: m, end: U.endOfMonth(m) };
    return [{ label: U.monthShort(m) + ' ⬇', value: D.income(txs, mi), color: '#22c55e' }, { label: '⬆', value: D.spending(txs, mi), color: '#ef4444' }];
  });
  const cats = D.byCategory(txs, interval);
  const cards = db.all('cards');
  const fixed = db.all('recurring').filter((r) => r.isActive && r.kind === 'despesa');
  return `
    <div class="card"><h3>Entradas × saídas por mês</h3>${bars(io, { height: 150, format: money })}</div>
    <div class="card"><h3>Gastos por semana</h3>${bars(weeks.map((w) => ({ label: U.dayMonth(w), value: D.spending(txs, { start: w, end: U.addDays(w, 7) }) })), { height: 130, color: '#10b981', format: money })}</div>
    <div class="card"><h3>Gastos por categoria</h3>${cats.length ? hbars(cats.map((c) => ({ label: D.FIN_CATS[c.category].label, value: c.total, color: D.FIN_CATS[c.category].color }))) : '<p class="muted">Sem dados.</p>'}</div>
    <div class="card"><h3>Saldo ao longo dos meses</h3>${line(months.map((m) => ({ x: m, y: D.balance(p.initialBalance, p.balanceDate, txs, new Date(Math.min(now, U.endOfMonth(m)))) })), { height: 130, color: '#10b981', format: money }) || '<p class="muted">Precisa de pelo menos 2 meses.</p>'}</div>
    ${cards.length ? `<div class="card"><h3>Gastos por cartão</h3>${hbars(cards.map((c) => ({ label: c.name, color: c.color, value: txs.filter((t) => t.cardId === c.id && !t.isInvoicePayment && new Date(t.date) >= interval.start && new Date(t.date) <= interval.end).reduce((a, t) => a + t.amount, 0) })))}</div>` : ''}
    ${fixed.length ? `<div class="card"><h3>Despesas recorrentes</h3>${hbars(fixed.map((r) => ({ label: r.title, value: r.amount, color: D.FIN_CATS[r.category]?.color })))}</div>` : ''}
    ${db.all('debts').some((d) => (d.payments || []).length >= 2) ? `<div class="card"><h3>Evolução das dívidas</h3>${db.all('debts').filter((d) => (d.payments || []).length >= 2).map((d) => `<small>${esc(d.creditor)}</small>${line(d.payments.map((x) => ({ x: x.date, y: x.remainingAfter })), { height: 90, color: '#ef4444', format: money })}`).join('')}</div>` : ''}`;
}

const graficos = () => `${seg('period', U.PERIODS, ui.period)}${financeCharts(ui.period)}`;

export default {
  render() {
    const body = { resumo, planejamento, movimentacoes, contas, cartoes, dividas, metas, graficos }[ui.tab] || resumo;
    return `<header class="top"><h1>${ui.tab === 'planejamento' ? 'Planejamento' : 'Financeiro'}</h1><div class="top-a">
      ${ui.tab !== 'resumo' ? `<button class="btn btn-sm" data-act="tab" data-v="resumo">${icon('back', 16)} Resumo</button>` : ''}
      <button class="icon-btn accent" data-act="newTx" data-k="despesa" aria-label="Nova despesa">${icon('plus')}</button></div></header>
      <div class="tabs-scroll">${seg('tab', TABS, ui.tab)}</div>${body()}`;
  },
  actions: {
    tab: (d) => { ui.tab = d.v; window.scrollTo(0, 0); },
    period: (d) => { ui.period = d.v; },
    finMonth: (d) => { ui.monthOffset = Math.min(0, ui.monthOffset + Number(d.n)); },
    kind: (d) => { ui.kind = d.v; },
    newTx: (d) => { transactionEditor(null, d.k); return false; },
    editTx: (d) => { const t = db.get('transactions', d.id); if (t) transactionEditor(t); return false; },
    balance: () => { balanceEditor(); return false; },
    newRec: () => { recurringEditor(); return false; },
    editRec: (d) => { recurringEditor(db.get('recurring', d.id)); return false; },
    settle: async (d) => { const r = db.get('recurring', d.id); if (r && await confirmDialog(`Registrar ${r.title} (${money(r.amount)}) como ${r.kind === 'receita' ? 'recebido' : 'pago'} hoje?`)) { D.settleRecurring(r); toast('Lançado em Finanças.'); } },
    newCard: () => { cardEditor(); return false; },
    editCard: (d) => { cardEditor(db.get('cards', d.id)); return false; },
    invMonth: (d) => { ui.invoice[d.id] = d.m; },
    payInvoice: async (d) => { const c = db.get('cards', d.id); const out = D.outstanding(c); if (await confirmDialog(`Registrar o pagamento de ${money(out)} da fatura? O valor sairá do seu saldo.`)) D.payInvoice(c, out); },
    newDebt: () => { debtEditor(); return false; },
    editDebt: (d) => { debtEditor(db.get('debts', d.id)); return false; },
    payDebt: (d) => {
      const debt = db.get('debts', d.id);
      form({ title: `Pagamento · ${debt.creditor}`, values: { amount: Math.min(debt.monthlyPayment || debt.remainingAmount, debt.remainingAmount), register: true },
        fields: [{ name: 'amount', label: 'Valor pago (R$)', type: 'money', required: true }, { name: 'register', label: 'Lançar como despesa no saldo', type: 'checkbox' }],
        onSubmit: (v) => { if (!(v.amount > 0)) return 'Valor inválido.'; D.payDebt(debt, v.amount, v.register); } });
      return false;
    },
    newSaving: () => {
      form({ title: 'Nova meta financeira', fields: [{ name: 'title', label: 'Nome', required: true }, { name: 'target', label: 'Valor alvo (R$)', type: 'money', required: true }],
        onSubmit: (v) => { if (!(v.target > 0)) return 'Valor inválido.'; db.insert('savingsGoals', { title: v.title, target: v.target, saved: 0 }); } });
      return false;
    },
    deposit: (d) => {
      const g = db.get('savingsGoals', d.id);
      form({ title: g.title, values: { op: 'guardar', amount: '', affect: true },
        fields: [{ name: 'op', label: 'Operação', type: 'select', options: { guardar: 'Guardar', retirar: 'Retirar' } }, { name: 'amount', label: 'Valor (R$)', type: 'money', required: true }, { name: 'affect', label: 'Movimentar o saldo disponível', type: 'checkbox' }],
        onSubmit: (v) => {
          if (!(v.amount > 0)) return 'Valor inválido.';
          const w = v.op === 'retirar';
          db.update('savingsGoals', g.id, { saved: Math.max(0, g.saved + (w ? -v.amount : v.amount)) });
          if (v.affect) db.insert('transactions', { title: `Meta: ${g.title}`, amount: v.amount, kind: w ? 'receita' : 'despesa', category: w ? 'outrasReceitas' : 'reserva', date: new Date().toISOString(), cardId: null });
        } });
      return false;
    },
    delSaving: async (d) => { if (await confirmDialog('Excluir esta meta?', { danger: true, confirmLabel: 'Excluir' })) db.remove('savingsGoals', d.id); },
    exportCsv: () => { download('LifeOS-financas.csv', csvTransactions(db.all('transactions')), 'text/csv;charset=utf-8'); return false; },
  },
  inputs: { txSearch: (v) => { ui.search = v; } },
};
