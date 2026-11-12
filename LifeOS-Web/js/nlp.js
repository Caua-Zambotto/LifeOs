// Assistente: interpretação local de frases em português (regras + expressões regulares).
// Nada é enviado para fora do aparelho. Nunca inventa dados: se faltar algo, pergunta.

import { fold, capFirst, startOfDay, addDays, addMonths } from './util.js';

const R = String.raw;

// ---------- Expressões regulares ----------
const cache = new Map();
function re(p) {
  let r = cache.get(p);
  if (!r) { r = new RegExp(p, 'id'); cache.set(p, r); }
  r.lastIndex = 0;
  return r;
}
export function first(p, s) {
  const m = re(p).exec(s);
  if (!m) return null;
  return { index: m.index, length: m[0].length, groups: [...m], ranges: m.indices };
}
export const test = (p, s) => re(p).test(s);

// ---------- Texto normalizado alinhado ----------
export class NText {
  constructor(text) {
    this.original = String(text).normalize('NFC').replace(/\n/g, ' ').trim();
    this.folded = fold(this.original);
    this.masked = this.original;
    this.aligned = this.folded.length === this.original.length;
  }
  blank(start, len) {
    if (start < 0 || len <= 0) return;
    const sp = ' '.repeat(len);
    this.folded = this.folded.slice(0, start) + sp + this.folded.slice(start + len);
    if (this.aligned) this.masked = this.masked.slice(0, start) + sp + this.masked.slice(start + len);
  }
  blankMatch(m) { this.blank(m.index, m.length); }
  originalText(start, end) { return (this.aligned ? this.masked : this.folded).slice(start, end); }
}

export function parseNumber(s, money) {
  let x = String(s).trim();
  if (x.includes(',')) x = x.replace(/\./g, '').replace(',', '.');
  else if (money && /^\d{1,3}(\.\d{3})+$/.test(x)) x = x.replace(/\./g, '');
  const v = Number(x);
  return Number.isFinite(v) ? v : null;
}

const NUMBER_WORDS = { um: 1, uma: 1, dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5, seis: 6, sete: 7, oito: 8, nove: 9, dez: 10, onze: 11, doze: 12, meia: 6 };

// ---------- Datas ----------
const WEEKDAYS = { domingo: 0, segunda: 1, terca: 2, quarta: 3, quinta: 4, sexta: 5, sabado: 6 };
const MONTHS = ['janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

function makeDate(y, m, d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  const x = new Date(y, m - 1, d);
  return x.getDate() === d ? x : null; // rejeita 31/02
}

/** Retorna { date, hasDate, hasTime }. Apaga do texto os trechos interpretados. */
export function parseDate(t, preferPast, now = new Date()) {
  const today = startOfDay(now);
  let day = null;

  for (const [p, off] of [[R`\bdepois de amanha\b`, 2], [R`\banteontem\b`, -2], [R`\bamanha\b`, 1], [R`\bhoje\b`, 0], [R`\bontem\b`, -1]]) {
    const m = first(p, t.folded);
    if (m) { day = addDays(today, off); t.blankMatch(m); break; }
  }

  let m;
  if (!day && (m = first(R`\b(?:daqui a|daqui|em)\s+(\d{1,3})\s+dias?\b`, t.folded))) {
    day = addDays(today, Number(m.groups[1])); t.blankMatch(m);
  }

  if (!day && (m = first(R`\b(\d{1,2})[/\-](\d{1,2})(?:[/\-](\d{2,4}))?\b`, t.folded))) {
    let year = today.getFullYear();
    if (m.groups[3]) { const y = Number(m.groups[3]); year = y < 100 ? 2000 + y : y; }
    let d = makeDate(year, Number(m.groups[2]), Number(m.groups[1]));
    if (d) {
      if (!m.groups[3]) {
        if (!preferPast && d < today) d = makeDate(year + 1, d.getMonth() + 1, d.getDate()) || d;
        if (preferPast && d > today) d = makeDate(year - 1, d.getMonth() + 1, d.getDate()) || d;
      }
      day = d; t.blankMatch(m);
    }
  }

  if (!day && (m = first(R`\b(?:dia\s+)?(\d{1,2})\s+de\s+(${MONTHS.join('|')})(?:\s+de\s+(\d{4}))?\b`, t.folded))) {
    let year = m.groups[3] ? Number(m.groups[3]) : today.getFullYear();
    let d = makeDate(year, MONTHS.indexOf(m.groups[2]) + 1, Number(m.groups[1]));
    if (d) {
      if (!m.groups[3] && !preferPast && d < today) d = makeDate(year + 1, d.getMonth() + 1, d.getDate()) || d;
      day = d; t.blankMatch(m);
    }
  }

  if (!day && (m = first(R`\bdia\s+(\d{1,2})\b`, t.folded))) {
    const n = Number(m.groups[1]);
    let d = makeDate(today.getFullYear(), today.getMonth() + 1, n);
    if (d) {
      if (!preferPast && d < today) {
        for (let off = 1; off <= 3; off++) {
          const base = addMonths(startOfDay(new Date(today.getFullYear(), today.getMonth(), 1)), off);
          const c = makeDate(base.getFullYear(), base.getMonth() + 1, n);
          if (c) { d = c; break; }
        }
      }
      if (preferPast && d > today) d = addMonths(d, -1);
      day = d; t.blankMatch(m);
    }
  }

  if (!day && (m = first(R`\b(?:(?:na|no|nesta|neste|nessa|nesse|esta|este|essa|esse)\s+)?(proxim[oa]\s+)?(domingo|segunda|terca|quarta|quinta|sexta|sabado)(?:[\s\-]feira)?(\s+que vem)?\b`, t.folded))) {
    const wd = WEEKDAYS[m.groups[2].toLowerCase()];
    const isNext = !!(m.groups[1] || m.groups[3]);
    const cur = today.getDay();
    let diff;
    if (preferPast && !isNext) diff = -((cur - wd + 7) % 7);
    else { diff = (wd - cur + 7) % 7; if (diff === 0 && isNext) diff = 7; }
    day = addDays(today, diff); t.blankMatch(m);
  }

  if (!day && (m = first(R`\b(?:semana que vem|proxima semana)\b`, t.folded))) { day = addDays(today, 7); t.blankMatch(m); }
  if (!day && (m = first(R`\b(?:mes que vem|proximo mes)\b`, t.folded))) { day = addMonths(today, 1); t.blankMatch(m); }

  // Horário
  let hour = null, minute = 0;
  if ((m = first(R`\b(?:as\s+|a\s+partir\s+das\s+)?(\d{1,2}):(\d{2})\b`, t.folded))) {
    hour = Number(m.groups[1]); minute = Number(m.groups[2]); t.blankMatch(m);
  } else if ((m = first(R`\b(?:as\s+)?(\d{1,2})\s*h(?:oras?)?(?:\s*(\d{2}))?(?![a-z])`, t.folded))
             && !test(R`^\s*(?:de|em)\b`, t.folded.slice(m.index + m.length))) {
    hour = Number(m.groups[1]); minute = Number(m.groups[2] || 0); t.blankMatch(m);
  } else if ((m = first(R`\b(?:as|a partir das)\s+(\d{1,2})\b(?!\s*(?:reais|real|kg|x|vezes))`, t.folded))) {
    hour = Number(m.groups[1]); t.blankMatch(m);
  } else if ((m = first(R`\b(?:ao\s+)?meio[\s\-]dia\b`, t.folded))) {
    hour = 12; t.blankMatch(m);
  } else if ((m = first(R`\bmeia[\s\-]noite\b`, t.folded))) {
    hour = 0; t.blankMatch(m);
  }
  if (hour !== null) {
    if ((m = first(R`\b(?:da|de)\s+(manha|tarde|noite|madrugada)\b`, t.folded))) {
      const p = m.groups[1];
      if ((p === 'tarde' || p === 'noite') && hour < 12) hour += 12;
      t.blankMatch(m);
    }
    if (hour > 23 || minute > 59) hour = null;
  }

  if (hour !== null) {
    let base = day || today;
    if (!day && !preferPast) {
      const cand = new Date(today); cand.setHours(hour, minute, 0, 0);
      if (cand < now) base = addDays(today, 1);
    }
    const date = new Date(base); date.setHours(hour, minute, 0, 0);
    return { date, hasDate: !!day, hasTime: true };
  }
  return { date: day, hasDate: !!day, hasTime: false };
}

// ---------- Categorias ----------
const EXPENSE_RULES = [
  ['assinaturas', 'netflix|spotify|prime video|amazon prime|disney|hbo|max|youtube premium|icloud|assinatura|deezer|globoplay|chatgpt|apple music|game pass'],
  ['internet', 'internet|wi-?fi|banda larga|telefone|plano de celular|recarga|fibra'],
  ['alimentacao', 'almoco|almocei|jantar|jantei|lanche|lanchei|cafe|comida|restaurante|mercado|supermercado|ifood|padaria|pizza|hamburguer|acougue|feira|marmita|refeicao|sorvete|acai|lanchonete|delivery|hortifruti|salgado'],
  ['transporte', 'uber|99|onibus|metro|gasolina|combustivel|estacionamento|passagem|taxi|pedagio|etanol|posto|mecanico|oficina|brt|trem|bilhete unico'],
  ['moradia', 'aluguel|condominio|luz|energia|conta de agua|agua|gas|iptu|reforma|moveis|movel|faxina|diarista'],
  ['faculdade', 'faculdade|mensalidade|livro|apostila|curso|xerox|copias|material|matricula|cursinho|concurso|inscricao|universidade'],
  ['saude', 'farmacia|remedio|medico|consulta|exame|dentista|plano de saude|academia|suplemento|whey|creatina|terapia|psicologo|hospital'],
  ['lazer', 'cinema|bar|show|festa|viagem|jogo|cerveja|balada|passeio|teatro|ingresso|role|praia'],
  ['dividas', 'emprestimo|divida|financiamento|acordo|parcela do|juros'],
  ['compras', 'roupa|tenis|sapato|loja|shopping|presente|eletronico|celular|fone|amazon|shopee|mercado livre|camisa|calca|perfume'],
];

export function guessExpense(f) {
  for (const [cat, words] of EXPENSE_RULES) if (test(R`\b(?:${words})\b`, f)) return cat;
  return 'outros';
}
export function guessIncome(f) {
  if (test(R`\b(salario|pagamento do mes|holerite|contracheque)\b`, f)) return 'salario';
  if (test(R`\b(freela|freelance|extra|bico|venda|vendi)\b`, f)) return 'rendaExtra';
  if (test(R`\b(servico|aula particular|conserto|projeto)\b`, f)) return 'servicos';
  return 'outrasReceitas';
}

export const MUSCLE_GROUPS = [
  ['peito|peitoral', 'Peito'], ['triceps', 'Tríceps'], ['biceps', 'Bíceps'], ['costas|dorsal', 'Costas'],
  ['ombros?|deltoides?', 'Ombros'], ['pernas?', 'Pernas'], ['gluteos?', 'Glúteos'], ['abdomen|abdominais?|abs', 'Abdômen'],
  ['posteriores?', 'Posterior'], ['quadriceps', 'Quadríceps'], ['panturrilhas?', 'Panturrilha'], ['cardio|aerobico', 'Cardio'],
  ['corri|corrida', 'Corrida'], ['caminhei|caminhada', 'Caminhada'], ['pedalei|bike|bicicleta', 'Bike'], ['nadei|natacao', 'Natação'],
  ['full ?body|corpo todo|corpo inteiro', 'Corpo inteiro'], ['superiores', 'Superiores'], ['inferiores', 'Inferiores'],
  ['funcional', 'Funcional'], ['trapezio', 'Trapézio'], ['antebraco', 'Antebraço'],
];
export const muscleGroupsIn = (f) => MUSCLE_GROUPS.filter(([p]) => test(R`\b(?:${p})\b`, f)).map(([, n]) => n);
export const joinNatural = (a) => (a.length > 1 ? a.slice(0, -1).join(', ') + ' e ' + a[a.length - 1] : a[0] || '');

/** Correspondência aproximada entre nome digitado e nomes existentes. */
export function bestMatch(name, candidates) {
  const n = fold(name).trim();
  if (n.length < 3) return null;
  const exact = candidates.find((c) => fold(c).trim() === n);
  if (exact) return exact;
  const partial = candidates.filter((c) => { const x = fold(c).trim(); return x.length >= 3 && (x.includes(n) || n.includes(x)); });
  partial.sort((a, b) => Math.abs(a.length - name.length) - Math.abs(b.length - name.length));
  return partial[0] || null;
}

// ---------- Interpretador ----------
export const HELP = `Ainda não entendi. Tente frases como:
• "Gastei 35 reais no almoço"
• "Tenho prova de cálculo na próxima quinta às 19h"
• "Minha conta de internet vence dia 15 e custa 120 reais"
• "Meu peso é 77,5 kg"
• "Hoje treinei peito e tríceps"
• "Preciso estudar redes amanhã"
• "Comprei ovos, arroz e frango no mercado"`;

const newDraft = (kind, source) => ({
  kind, title: '', amount: null, date: null, hasTime: false, financeCategory: 'outros', eventCategory: 'compromisso',
  priority: 1, subjectName: null, subjectExists: false, cardName: null, installments: 1, recurrence: 'nenhuma',
  items: [], weight: null, measurements: {}, muscleGroups: [], minutes: null, habitName: null, sourceText: source,
});

const DEFAULT_STOPS = [' no ', ' na ', ' com ', ' pelo ', ' pela ', ' em ', ' para ', ' pra ', ' e ', ' que ', ' por '];

/** Trecho após um padrão, com grafia original, cortado nas palavras de parada. */
export function phrase(pattern, t, stops = DEFAULT_STOPS, maxWords = 6) {
  const m = first(pattern + R`([^\d,.;!?]+)`, t.folded);
  if (!m) return null;
  const [s0, e0] = m.ranges[m.ranges.length - 1];
  let s = t.originalText(s0, e0);
  const padded = ' ' + fold(s) + ' ';
  let cut = s.length;
  for (const st of stops) { const i = padded.indexOf(st); if (i >= 0) cut = Math.min(cut, i); }
  s = s.slice(0, cut);
  const words = s.split(/\s+/).filter(Boolean).slice(0, maxWords).join(' ').replace(/^[\s\-:]+|[\s\-:]+$/g, '');
  return words.length >= 2 ? capFirst(words) : null;
}

export function extractAmount(t, allowBare) {
  for (const p of [R`r\$\s*(\d+(?:[.,]\d+)*)`, R`(\d+(?:[.,]\d+)*)\s*(?:reais|real|conto|contos|pila|pilas|brl)\b`]) {
    const m = first(p, t.folded);
    if (m) { const v = parseNumber(m.groups[1], true); if (v !== null) { t.blankMatch(m); return v; } }
  }
  if (allowBare) {
    const m = first(R`(?<![\d/:])(\d+(?:[.,]\d+)*)(?![\d/:])(?!\s*(?:x\b|vezes|h\b|hs\b|horas|min|kg|cm|%|anos))`, t.folded);
    if (m) { const v = parseNumber(m.groups[1], true); if (v !== null) { t.blankMatch(m); return v; } }
  }
  return null;
}

export function extractDuration(t) {
  let m;
  if ((m = first(R`\b(\d+(?:[.,]\d+)?)\s*(?:h|hs|hrs?|horas?)\s*(?:e\s*)?(\d{1,2})?\s*(?:min|minutos)?\b`, t.folded))) {
    const h = parseNumber(m.groups[1], false);
    if (h !== null) { t.blankMatch(m); return Math.round(h * 60) + Number(m.groups[2] || 0); }
  }
  if ((m = first(R`\b(\d{1,3})\s*(?:min|mins|minutos?)\b`, t.folded))) { t.blankMatch(m); return Number(m.groups[1]); }
  if ((m = first(R`\b(?:uma|1)\s+hora\s+e\s+meia\b`, t.folded))) { t.blankMatch(m); return 90; }
  if ((m = first(R`\bmeia\s+hora\b`, t.folded))) { t.blankMatch(m); return 30; }
  if ((m = first(R`\b(uma|duas|tres|quatro|cinco)\s+horas?\b`, t.folded))) { t.blankMatch(m); return NUMBER_WORDS[m.groups[1]] * 60; }
  return null;
}

export function normalizeUnit(u) {
  return ({ kg: 'kg', g: 'g', gr: 'g', l: 'L', litro: 'L', litros: 'L', ml: 'ml', duzia: 'dz', duzias: 'dz',
    pacote: 'pct', pacotes: 'pct', pct: 'pct', caixa: 'cx', caixas: 'cx', lata: 'lata', latas: 'lata',
    garrafa: 'garrafa', garrafas: 'garrafa', bandeja: 'bandeja', bandejas: 'bandeja', saco: 'saco', sacos: 'saco' })[u] || 'un';
}

export function splitItems(text) {
  const parts = String(text).replace(/\s+e\s+/gi, ',').split(/[,;]/).map((s) => s.trim()).filter(Boolean);
  const out = [];
  for (const part of parts) {
    let name = part, qty = 1, unit = 'un';
    const m = first(R`^(\d+(?:[.,]\d+)?|(?:uma|um|duas|dois|tres|três|meia|meio)(?=\s))\s*(?:(kg|g|gr|l|litros?|ml|un|unidades?|duzias?|dúzias?|pacotes?|pct|caixas?|latas?|garrafas?|bandejas?|sacos?)(?![a-zà-ÿ]))?\s*(?:de\s+)?(.+)$`, part);
    if (m) {
      const q = fold(m.groups[1]);
      const n = parseNumber(q, false);
      if (n !== null) qty = n;
      else if (q === 'meia' || q === 'meio') qty = 0.5;
      else if (NUMBER_WORDS[q]) qty = NUMBER_WORDS[q];
      if (m.groups[2]) {
        unit = normalizeUnit(fold(m.groups[2]));
        if (unit === 'dz') { qty *= 12; unit = 'un'; }
      }
      name = m.groups[3] || part;
    }
    name = name.replace(/^(?:o|a|os|as|um|uma|uns|umas)\s+/i, '').trim();
    if (name.length >= 2) out.push({ name: capFirst(name), quantity: qty, unit });
  }
  return out;
}

const firstNumber = (f) => { const m = first(R`(\d+(?:[.,]\d+)?)`, f); return m ? parseNumber(m.groups[1], false) : null; };

// Detecção de intenção
const isBill = (f) => !test(R`\b(gastei|paguei|recebi)\b`, f)
  && (test(R`\b(vence|vencimento|vencendo|boleto|mensalidade)\b`, f) || test(R`\bconta\s+d[aeo]s?\s+\w+.*\b(custa|e de|valor)\b`, f));
const isIncome = (f) => test(R`\b(recebi|ganhei|entrou|caiu|recebimento|me pagaram|me pagou)\b`, f);
function isGroceries(f) {
  if (!test(R`\bcomprei\b`, f) || test(R`\bgastei\b`, f)) return false;
  if (test(R`\b(mercado|supermercado|feira|hortifruti|sacolao|acougue|padaria|atacad\w*|quitanda)\b`, f)) return true;
  return f.includes(',') && extractAmount(new NText(f), false) === null;
}
function isBody(f) {
  if (test(R`\bpes(?:o|ei|ando|agem)\b`, f) && firstNumber(f) !== null) return true;
  if (test(R`\b(cintura|braco|biceps|peito|torax|coxa|perna|quadril)\b[^\d]{0,20}\d{2,3}(?:[.,]\d)?\s*cm\b`, f)) return true;
  return test(R`\b(gordura|bf|percentual de gordura)\b[^\d]{0,20}\d{1,2}(?:[.,]\d)?\s*%`, f);
}
const isExpense = (f) => test(R`\b(gastei|paguei|gasto|comprei|custou|torrei|despesa|pago)\b`, f) || test(R`r\$\s*\d|\d\s*(reais|real)\b`, f);
const isWorkoutDone = (f) => test(R`\b(treinei|malhei|corri|pedalei|nadei|caminhei|fiz (?:o\s+)?treino|fiz (?:uma\s+)?(?:corrida|caminhada|musculacao|academia))\b`, f)
  || (test(R`\b(hoje|ontem)\b`, f) && test(R`\btreino\b`, f) && !test(R`\b(tenho|vou|preciso|amanha)\b`, f));

export function validate(d) {
  switch (d.kind) {
    case 'expense': case 'income':
      if (!(d.amount > 0)) return { type: 'needsInfo', draft: d, field: 'amount', question: 'Qual foi o valor?' };
      break;
    case 'bill':
      if (!(d.amount > 0)) return { type: 'needsInfo', draft: d, field: 'amount', question: `Qual o valor da conta ${d.title.toLowerCase()}?` };
      if (!d.date) return { type: 'needsInfo', draft: d, field: 'date', question: 'Qual o dia do vencimento?' };
      break;
    case 'event':
      if (!d.date) return { type: 'needsInfo', draft: d, field: 'date', question: 'Para quando? (ex.: amanhã às 19h, dia 20)' };
      break;
    case 'studySession':
      if (!(d.minutes > 0)) return { type: 'needsInfo', draft: d, field: 'duration', question: 'Quanto tempo você estudou? (ex.: 1h30, 45 min)' };
      break;
    case 'body':
      if (d.weight === null && !Object.keys(d.measurements).length) return { type: 'needsInfo', draft: d, field: 'weight', question: 'Qual o seu peso, em kg?' };
      break;
    case 'groceries':
      if (!d.items.length) return { type: 'needsInfo', draft: d, field: 'items', question: 'Quais itens você comprou? (separe por vírgula)' };
      break;
    default: break;
  }
  return { type: 'draft', draft: d };
}

/**
 * ctx: { subjectNames, contestSubjectNames, habitNames, cardNames, now }
 * Retorna { type: 'draft'|'needsInfo'|'notUnderstood', draft?, field?, question?, help? }
 */
export function interpret(raw, ctx = {}) {
  const now = ctx.now || new Date();
  const t = new NText(raw);
  const f = t.folded;
  if (f.trim().length < 3) return { type: 'notUnderstood', help: HELP };

  // Hábito
  if (test(R`\b(fiz|feito|conclui|completei|cumpri|marcar|marque|marca|check|li|meditei|bebi|pratiquei)\b`, f)) {
    const habit = (ctx.habitNames || []).filter((h) => h.length >= 3 && f.includes(fold(h))).sort((a, b) => b.length - a.length)[0];
    if (habit) {
      const d = newDraft('habitCheck', raw);
      d.habitName = habit; d.title = habit;
      d.date = parseDate(t, true, now).date || now;
      return { type: 'draft', draft: d };
    }
  }
  if (isBill(f)) return parseBill(t, raw, now);
  if (isIncome(f)) return parseIncome(t, raw, now);
  if (isGroceries(f)) return parseGroceries(t, raw, now);
  if (isBody(f)) return parseBody(t, raw, now);
  if (isExpense(f)) return parseExpense(t, raw, now, ctx);
  if (isWorkoutDone(f)) return parseWorkout(t, raw, now);
  if (test(R`\bestudei\b`, f)) return parseStudySession(t, raw, now, ctx);
  const ev = parseEvent(t, raw, now, ctx);
  return ev || { type: 'notUnderstood', help: HELP };
}

/** Completa o rascunho com a resposta a uma pergunta. */
export function complete(draft, field, answer, ctx = {}) {
  const now = ctx.now || new Date();
  const d = { ...draft, measurements: { ...draft.measurements }, items: [...draft.items] };
  const t = new NText(answer);
  if (field === 'amount') d.amount = extractAmount(t, true);
  else if (field === 'date') {
    const past = ['expense', 'income', 'body', 'workout', 'studySession'].includes(d.kind);
    let r = parseDate(t, past, now);
    if (!r.date && /^\s*\d{1,2}\s*$/.test(answer)) r = parseDate(new NText(`dia ${answer.trim()}`), past, now);
    if (r.date) { d.date = r.date; d.hasTime = r.hasTime; }
  } else if (field === 'items') d.items = splitItems(answer);
  else if (field === 'duration') {
    let v = extractDuration(t);
    if (v === null && /^\s*\d+\s*$/.test(answer)) { const n = Number(answer); v = n <= 12 ? n * 60 : n; }
    d.minutes = v;
  } else if (field === 'weight') {
    const v = firstNumber(t.folded);
    d.weight = v !== null && v >= 20 && v <= 400 ? v : null;
  }
  return validate(d);
}

function parseExpense(t, raw, now, ctx) {
  const d = newDraft('expense', raw);
  const f = t.folded;
  const cards = ctx.cardNames || [];
  let m = first(R`\b(?:no|pelo|com o|com|via)\s+(?:cartao|credito)(?:\s+(?:de credito\s+)?(?:do\s+|da\s+)?([a-z0-9]+))?`, f);
  if (m) {
    const hint = m.groups[1] || '';
    d.cardName = cards.find((c) => hint && fold(c).includes(hint)) || cards[0] || null;
    t.blankMatch(m);
  }
  m = first(R`\b(?:em\s+)?(\d{1,2})\s*(?:x|vezes)\b`, t.folded);
  if (m && Number(m.groups[1]) > 1) { d.installments = Math.min(48, Number(m.groups[1])); t.blankMatch(m); }
  d.amount = extractAmount(t, false);
  const r = parseDate(t, true, now);
  d.date = r.date || now; d.hasTime = r.hasTime;
  if (d.amount === null) d.amount = extractAmount(t, true);
  d.financeCategory = guessExpense(f);
  let desc = phrase(R`\b(?:comprei|paguei|gastei com|paguei o|paguei a)\s+(?:(?:um|uma|uns|umas|o|a|os|as)\s+)?`, t);
  if (!desc || test(R`^(no|na|em|com|de)\b`, fold(desc))) desc = phrase(R`\b(?:no|na|nos|nas|num|numa|em|com|de|do|da|dos|das|pra|para|pro)\s+`, t);
  d.title = desc || CATEGORY_LABEL[d.financeCategory];
  if (!d.cardName) d.installments = 1;
  return validate(d);
}

function parseIncome(t, raw, now) {
  const d = newDraft('income', raw);
  const f = t.folded;
  d.amount = extractAmount(t, false);
  d.date = parseDate(t, true, now).date || now;
  if (d.amount === null) d.amount = extractAmount(t, true);
  d.financeCategory = guessIncome(f);
  d.title = phrase(R`\b(?:de|do|da|com|pelo|pela)\s+`, t) || CATEGORY_LABEL[d.financeCategory];
  return validate(d);
}

function parseBill(t, raw, now) {
  const d = newDraft('bill', raw);
  const f = t.folded;
  d.amount = extractAmount(t, false);
  d.date = parseDate(t, false, now).date;
  if (d.amount === null) d.amount = extractAmount(t, true);
  const name = phrase(R`\b(?:conta|boleto|fatura|mensalidade)\s+(?:d[aeo]s?\s+)?`, t, [' vence', ' venc', ' custa', ' que ', ' no valor', ' de r', ' todo', ' e ', ' com ']);
  d.title = capFirst(name || 'Conta');
  d.financeCategory = guessExpense(f);
  if (d.financeCategory === 'outros' && test(R`\bmensalidade\b`, f)) d.financeCategory = 'faculdade';
  d.recurrence = test(R`\b(boleto|unica|so uma vez|parcela unica)\b`, f) && !test(R`\b(todo mes|mensal)\b`, f) ? 'nenhuma' : 'mensal';
  return validate(d);
}

function parseGroceries(t, raw, now) {
  const d = newDraft('groceries', raw);
  d.amount = extractAmount(t, false);
  d.date = parseDate(t, true, now).date || now;
  let m;
  if (d.amount === null && (m = first(R`\b(?:por|paguei|gastei|total(?: de)?)\s+(\d+(?:[.,]\d+)*)`, t.folded))) {
    d.amount = parseNumber(m.groups[1], true); t.blankMatch(m);
  }
  if ((m = first(R`\bcomprei\s+(.+)$`, t.folded))) {
    const [s0, e0] = m.ranges[1];
    let text = t.originalText(s0, e0);
    const stop = first(R`\s+(?:n[oa]s?|em)\s+(?:mercado|supermercado|feira|hortifruti|sacolao|acougue|padaria|atacad\w*|quitanda)\b|\s+(?:por|e gastei|gastei|paguei)\b|[.;!?]`, fold(text));
    if (stop) text = text.slice(0, stop.index);
    d.items = splitItems(text);
  }
  d.title = 'Compras de mercado';
  d.financeCategory = 'alimentacao';
  return validate(d);
}

function parseBody(t, raw, now) {
  const d = newDraft('body', raw);
  for (const [key, words] of [['waist', 'cintura'], ['arm', 'braco|biceps'], ['chest', 'peito|torax'], ['leg', 'coxa|perna'], ['hip', 'quadril']]) {
    const m = first(R`\b(?:${words})\b[^\d]{0,20}(\d{2,3}(?:[.,]\d)?)\s*(?:cm)?`, t.folded);
    const v = m && parseNumber(m.groups[1], false);
    if (v && v >= 10 && v <= 250) { d.measurements[key] = v; t.blankMatch(m); }
  }
  let m = first(R`\b(?:gordura|bf|percentual de gordura)\b[^\d]{0,20}(\d{1,2}(?:[.,]\d)?)\s*%?`, t.folded);
  let v = m && parseNumber(m.groups[1], false);
  if (v && v >= 2 && v <= 70) { d.measurements.bodyFat = v; t.blankMatch(m); }
  m = first(R`(\d{2,3}(?:[.,]\d{1,2})?)\s*(?:kg|quilos?|kilos?)\b`, t.folded) || first(R`\bpes(?:o|ei|ando|agem)\b[^\d]{0,30}(\d{2,3}(?:[.,]\d{1,2})?)`, t.folded);
  v = m && parseNumber(m.groups[1], false);
  if (v && v >= 20 && v <= 400) { d.weight = v; t.blankMatch(m); }
  d.date = parseDate(t, true, now).date || now;
  return validate(d);
}

function parseWorkout(t, raw, now) {
  const d = newDraft('workout', raw);
  d.minutes = extractDuration(t);
  d.date = parseDate(t, true, now).date || now;
  d.muscleGroups = muscleGroupsIn(t.folded);
  d.title = d.muscleGroups.length ? joinNatural(d.muscleGroups) : 'Treino';
  return validate(d);
}

function parseStudySession(t, raw, now, ctx) {
  const d = newDraft('studySession', raw);
  d.minutes = extractDuration(t);
  d.date = parseDate(t, true, now).date || now;
  const topic = phrase(R`\bestudei\s+(?:(?:um pouco|bastante|muito)\s+)?(?:(?:de|sobre|da|do|o|a)\s+)?`, t) || phrase(R`\b(?:de|sobre)\s+`, t);
  if (topic) {
    const match = bestMatch(topic, [...(ctx.subjectNames || []), ...(ctx.contestSubjectNames || [])]);
    d.subjectName = match || topic;
    d.subjectExists = !!match;
  }
  d.title = d.subjectName || 'Estudo';
  return validate(d);
}

function applySubject(name, d, ctx, createIfMissing) {
  if (!name) return;
  const match = bestMatch(name, ctx.subjectNames || []);
  if (match) { d.subjectName = match; d.subjectExists = true; }
  else if (createIfMissing) { d.subjectName = capFirst(name); d.subjectExists = false; }
}

function parseEvent(t, raw, now, ctx) {
  const f = t.folded;
  const d = newDraft('event', raw);
  const wantsTask = test(R`\b(preciso|tenho que|tenho de|vou|devo|quero|lembrar de)\b`, f);
  if (test(R`\b(prova|avaliacao|p1|p2|p3|teste|exame(?! de sangue| medico| de rotina))\b`, f) && !test(R`\b(medico|sangue|laboratorio)\b`, f)) { d.eventCategory = 'prova'; d.priority = 2; }
  else if (test(R`\b(entrega|entregar|prazo)\b`, f)) { d.eventCategory = 'entrega'; d.priority = 2; }
  else if (test(R`\b(trabalho|seminario|relatorio|tcc|atividade|lista de exercicios)\b`, f) && !test(R`\b(reuniao|no trabalho)\b`, f)) { d.eventCategory = 'trabalho'; d.priority = 2; }
  else if (test(R`\b(reuniao|call|meet|videochamada)\b`, f)) d.eventCategory = 'reuniao';
  else if (test(R`\b(consulta|dentista|medico|medica|exame|psicologo|psicologa|terapia|fisioterapia|nutricionista)\b`, f)) d.eventCategory = 'consulta';
  else if (test(R`\btreino\b`, f)) d.eventCategory = 'treino';
  else if (wantsTask && test(R`\b(estudar|revisar|revisao|ler|resolver|fazer exercicios|fazer questoes)\b`, f)) d.eventCategory = 'estudo';
  else if (test(R`\b(aniversario|casamento|formatura)\b`, f)) d.eventCategory = 'dataImportante';
  else if (test(R`\b(me lembre|lembre-me|lembrete|lembrar|me avise|me avisa)\b`, f)) d.eventCategory = 'lembrete';
  else if (test(R`\b(tenho|vou ter|marcar|agendar|agende|marque|compromisso|encontro|evento)\b`, f)) d.eventCategory = 'compromisso';
  else return null;
  if (test(R`\b(urgente|importante|prioridade)\b`, f)) d.priority = 2;

  const r = parseDate(t, false, now);
  d.date = r.date; d.hasTime = r.hasTime;
  const stops = [' na ', ' no ', ' para ', ' pra ', ' ate ', ' que ', ' as ', ' em '];
  let x;
  switch (d.eventCategory) {
    case 'prova':
      x = phrase(R`\b(?:prova|avaliacao|exame|teste|p1|p2|p3)\s+(?:de|da|do|sobre)\s+`, t, stops);
      applySubject(x, d, ctx, true);
      d.title = x ? `Prova de ${d.subjectName || x}` : 'Prova';
      break;
    case 'trabalho':
      x = phrase(R`\b(?:trabalho|seminario|relatorio|atividade|lista de exercicios)\s+(?:de|da|do|sobre)\s+`, t, stops);
      applySubject(x, d, ctx, true);
      d.title = x ? `Trabalho de ${d.subjectName || x}` : 'Trabalho';
      break;
    case 'entrega':
      x = phrase(R`\b(?:entrega|entregar)\s+(?:(?:d[aeo]s?|o|a|os|as)\s+)?`, t, stops);
      applySubject(x, d, ctx, false);
      d.title = x ? `Entrega: ${x}` : 'Entrega';
      break;
    case 'estudo': {
      const verb = test(R`\brevis`, f) ? 'Revisar' : 'Estudar';
      x = phrase(R`\b(?:estudar|revisar|revisao de|ler|resolver|fazer)\s+(?:(?:a|o|as|os|sobre|de|da|do|um pouco de)\s+)?`, t, stops);
      applySubject(x, d, ctx, false);
      d.title = x ? `${verb} ${d.subjectExists ? d.subjectName : x}` : verb;
      break;
    }
    case 'lembrete':
      d.title = phrase(R`\b(?:me lembre|lembre-me|lembrete|lembrar|me avise|me avisa)\s*(?:(?:de|que|para|pra|:)\s+)?`, t, [' as ']) || 'Lembrete';
      break;
    default:
      d.title = phrase(R`^(?:\s*(?:eu|hoje|amanha))*\s*(?:tenho|vou ter|vou|marcar|agendar|agende|marque)?\s*(?:(?:uma?|o|a)\s+)?`, t, stops) || EVENT_LABEL[d.eventCategory];
  }
  d.title = capFirst(d.title.trim());
  return validate(d);
}

// Rótulos usados pelo interpretador (fonte única em domain.js para a interface).
const CATEGORY_LABEL = {
  salario: 'Salário', rendaExtra: 'Renda extra', servicos: 'Serviços', outrasReceitas: 'Outras entradas',
  alimentacao: 'Alimentação', transporte: 'Transporte', moradia: 'Moradia', faculdade: 'Faculdade', saude: 'Saúde',
  lazer: 'Lazer', compras: 'Compras', assinaturas: 'Assinaturas', internet: 'Internet e telefone', dividas: 'Dívidas',
  reserva: 'Reserva e metas', outros: 'Outros',
};
const EVENT_LABEL = {
  compromisso: 'Compromisso', reuniao: 'Reunião', pessoal: 'Pessoal', prova: 'Prova', trabalho: 'Trabalho', entrega: 'Entrega',
  consulta: 'Consulta', treino: 'Treino', lembrete: 'Lembrete', dataImportante: 'Data importante', estudo: 'Estudo',
};
