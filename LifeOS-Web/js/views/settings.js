import * as db from '../store.js';
import * as D from '../domain.js';
import * as U from '../util.js';
import * as B from '../backup.js';
import * as C from '../crypto.js';
import { esc } from '../util.js';
import { form, icon, confirmDialog, askPassword, toast, download, pickFile, modal } from '../ui.js';
import { notificationPermission, requestNotifications, testNotification } from '../notify.js';
import * as S from '../sync.js';

const back = (to, label) => `<button class="back" data-act="nav" data-to="${to}">${icon('back', 18)} ${esc(label)}</button>`;
const navRow = (to, emoji, color, title, sub = '') => `<button class="nav-row" data-act="nav" data-to="${to}"><span class="badge" style="--c:${color}">${emoji}</span><span class="grow"><b>${esc(title)}</b>${sub ? `<small>${esc(sub)}</small>` : ''}</span>${icon('chevron', 18)}</button>`;

// ---------- Perfil (hub) ----------
export const profile = {
  render() {
    const p = db.profile();
    const tile = (to, cls, emoji, title, sub) => `<button class="tile ${cls}" data-act="nav" data-to="${to}"><span class="tile-i">${emoji}</span><b>${esc(title)}</b><small>${esc(sub)}</small></button>`;
    return `<header class="top"><h1>Perfil e ajustes</h1></header>
      <button class="card row profile-h" data-act="editName"><span class="avatar">${esc((p.name || '?').slice(0, 1).toUpperCase())}</span><span class="grow"><b>${esc(p.name || 'Seu perfil')}</b><small>Dados guardados somente neste aparelho</small></span>${icon('edit', 18)}</button>
      <div class="tiles">
        ${tile('food', 'g-food', '🍽️', 'Alimentação', `${db.all('pantry').length} item(ns) em casa`)}
        ${tile('growth', 'g-growth', '🌱', 'Desenvolvimento', `${db.all('goals').filter((g) => !g.completed).length} meta(s) ativa(s)`)}
        ${tile('docs', 'g-docs', '🔐', 'Documentos', `${db.all('documents').length} arquivo(s)`)}
        ${tile('reports', 'g-reports', '📊', 'Relatórios', 'Gráficos e exportação')}
      </div>
      <div class="card list">
        ${navRow('security', '🛡️', '#14b8a6', 'Segurança e Privacidade')}
        ${navRow('sync', '☁️', '#0ea5e9', 'Sincronização entre aparelhos', syncLabel())}
        ${navRow('backup', '💾', '#3b82f6', 'Backup e restauração', B.lastBackupLabel())}
        ${navRow('notifications', '🔔', '#ef4444', 'Notificações')}
        ${navRow('install', '📱', '#8b5cf6', 'Instalar no celular e no computador')}
        ${navRow('settings', '⚙️', '#64748b', 'Configurações')}
      </div>`;
  },
  actions: {
    editName: () => { form({ title: 'Perfil', values: { name: db.profile().name }, fields: [{ name: 'name', label: 'Nome', max: 40 }], onSubmit: (v) => db.setProfile({ name: v.name }) }); return false; },
  },
};

// ---------- Configurações ----------
export const settings = {
  render() {
    const theme = localStorage.getItem('theme') || 'system';
    return `${back('profile', 'Perfil e ajustes')}<header class="top"><h1>Configurações</h1></header>
      <div class="card"><h3>Aparência</h3><div class="seg">${Object.entries({ system: 'Automático', light: 'Claro', dark: 'Escuro' }).map(([k, v]) => `<button class="${theme === k ? 'on' : ''}" data-act="theme" data-v="${k}">${v}</button>`).join('')}</div></div>
      <div class="card list">
        <button class="nav-row" data-act="customizeHome"><span class="badge" style="--c:#7c5cff">🏠</span><span class="grow"><b>Personalizar tela inicial</b></span>${icon('chevron', 18)}</button>
        ${navRow('notifications', '🔔', '#ef4444', 'Notificações')}
        ${navRow('security', '🛡️', '#14b8a6', 'Segurança e Privacidade')}
        ${navRow('backup', '💾', '#3b82f6', 'Backup, exportação e restauração')}
        ${navRow('storage', '🗄️', '#64748b', 'Armazenamento')}
        ${navRow('limits', 'ℹ️', '#94a3b8', 'Limitações conhecidas')}
      </div>
      <p class="muted small center">LifeOS ${esc(window.LIFEOS_VERSION || '')} · sem anúncios, sem rastreadores, sem servidores.</p>`;
  },
  actions: {
    theme: (d) => { localStorage.setItem('theme', d.v); document.documentElement.dataset.theme = d.v; },
  },
};

// ---------- Segurança ----------
export const security = {
  render() {
    const p = db.profile();
    const opts = { 30: '30 segundos', 60: '1 minuto', 120: '2 minutos', 300: '5 minutos', 900: '15 minutos' };
    const st = (ok, title, sub) => `<div class="li"><span>${ok ? '✅' : '⚠️'}</span><div class="grow"><b>${title}</b><small>${sub}</small></div></div>`;
    return `${back('profile', 'Perfil e ajustes')}<header class="top"><h1>Segurança e Privacidade</h1></header>
      <div class="card"><h3>Status de proteção</h3>
        ${st(true, 'Senha do app', 'Chave derivada com PBKDF2-SHA256 (310 mil iterações)')}
        ${st(true, 'Dados cifrados', 'Todo o banco e os documentos com AES-256-GCM')}
        ${st(true, 'Bloqueio automático', opts[p.autoLockSeconds] || '2 minutos')}
        ${st(!!B.lastBackupDate(), 'Último backup', B.lastBackupLabel() || 'Nunca — recomendado fazer um')}
        <div data-persist></div></div>
      <div class="card"><h3>Acesso</h3>
        <div class="field"><label class="lbl">Bloquear após inatividade</label><select data-change="autoLock">${Object.entries(opts).map(([k, v]) => `<option value="${k}" ${Number(k) === p.autoLockSeconds ? 'selected' : ''}>${v}</option>`).join('')}</select></div>
        <div class="btn-row"><button class="btn" data-act="changePwd">Alterar senha</button><button class="btn" data-act="lockNow">${icon('lock', 16)} Bloquear agora</button></div></div>
      <div class="card list">${navRow('backup', '💾', '#3b82f6', 'Backup e exportação')}${navRow('storage', '🗄️', '#64748b', 'Armazenamento e arquivos')}${navRow('limits', 'ℹ️', '#94a3b8', 'Limitações de segurança')}</div>
      <div class="card"><h3>Privacidade</h3><ul class="plain">
        <li>☁️ Nenhum dado é enviado para servidores</li><li>🙈 Sem rastreadores, anúncios ou analytics</li>
        <li>🧾 Nada pessoal é registrado em logs</li><li>🔒 Ao bloquear, os dados descriptografados saem da memória</li></ul></div>
      <div class="card danger"><h3>Excluir todos os dados</h3><p class="muted small">Apaga permanentemente registros, documentos e a senha deste aparelho. Backups exportados não são afetados.</p>
        <button class="btn btn-danger" data-act="wipe">Excluir tudo</button></div>`;
  },
  after() {
    const el = document.querySelector('[data-persist]');
    if (el) db.storageInfo().then((s) => { el.innerHTML = `<div class="li"><span>${s.persisted ? '✅' : '⚠️'}</span><div class="grow"><b>Armazenamento persistente</b><small>${s.persisted ? 'O navegador não apagará os dados automaticamente' : 'Instale o app para reduzir o risco de limpeza automática'}</small></div>${s.persisted ? '' : '<button class="btn btn-sm" data-act="persist">Solicitar</button>'}</div>`; });
  },
  actions: {
    lockNow: () => { db.lock(); return false; },
    persist: async () => { toast((await db.requestPersistence()) ? 'Armazenamento persistente concedido.' : 'O navegador não concedeu agora. Instalar o app ajuda.'); },
    changePwd: () => {
      form({ title: 'Alterar senha', fields: [
        { name: 'old', label: 'Senha atual', type: 'password', required: true },
        { name: 'n1', label: 'Nova senha (mín. 8 caracteres)', type: 'password', autocomplete: 'new-password', required: true },
        { name: 'n2', label: 'Confirmar nova senha', type: 'password', autocomplete: 'new-password', required: true }],
        onSubmit: async (v) => {
          if (v.n1.length < 8) return 'A nova senha precisa de pelo menos 8 caracteres.';
          if (v.n1 !== v.n2) return 'As senhas não coincidem.';
          if (!(await db.verifyPassword(v.old))) return 'Senha atual incorreta.';
          await db.changePassword(v.old, v.n1); S.pushVaultIfConnected().catch(() => {}); toast('Senha alterada. Nos outros aparelhos, use a nova senha após a próxima sincronização.', { ms: 6000 });
        } });
      return false;
    },
    wipe: async () => {
      if (!(await askPassword('Confirme para excluir todos os dados.'))) return false;
      if (!(await confirmDialog('Esta ação não pode ser desfeita. Faça um backup antes, se quiser guardar seus dados.', { danger: true, confirmLabel: 'Excluir definitivamente', requireText: 'EXCLUIR' }))) return false;
      await db.wipeEverything(); location.hash = ''; location.reload();
      return false;
    },
  },
  changes: { autoLock: (d, el) => db.setProfile({ autoLockSeconds: Number(el.value) }) },
};

// ---------- Backup ----------
export const backup = {
  render() {
    return `${back('profile', 'Perfil e ajustes')}<header class="top"><h1>Backup</h1></header>
      <div class="card warn">⚠️ Seus dados ficam apenas neste aparelho/navegador. Sem backup, perder o aparelho ou limpar os dados do navegador significa perder tudo. <b>Último backup: ${esc(B.lastBackupLabel() || 'nunca')}</b></div>
      <div class="card"><h3>Criar backup criptografado</h3><p class="muted small">AES-256-GCM com chave derivada da senha do backup (PBKDF2, 310 mil iterações). O arquivo é verificado logo após ser gerado.</p>
        <button class="btn btn-primary" data-act="makeBackup">💾 Gerar backup</button></div>
      <div class="card"><h3>Restaurar</h3><p class="muted small">A restauração SUBSTITUI todos os dados atuais. O arquivo é verificado (senha e integridade) antes de qualquer alteração.</p>
        <button class="btn" data-act="restore">📂 Escolher arquivo de backup</button></div>
      <div class="card"><h3>Exportação aberta (JSON)</h3><p class="muted small">Dados legíveis, SEM criptografia e sem os documentos. Guarde em local seguro.</p>
        <button class="btn" data-act="exportJson">Exportar JSON</button></div>
      <div class="card"><h3>Passar os dados para outro aparelho</h3><ol class="steps small">
        <li>Gere um backup aqui e envie o arquivo para o outro aparelho (cabo, Google Drive, iCloud Drive, e-mail para você mesmo, pendrive).</li>
        <li>No outro aparelho, abra o LifeOS e crie uma senha.</li>
        <li>Em Perfil › Backup, toque em "Escolher arquivo de backup", informe a senha do backup e restaure.</li></ol>
        <p class="muted small">Os dados do computador e do celular são independentes (não há sincronização automática). Use o backup para levar os dados de um para o outro.</p></div>`;
  },
  actions: {
    makeBackup: () => {
      form({ title: 'Gerar backup', submitLabel: 'Gerar e baixar', values: { files: true, risk: false },
        fields: [
          { name: 'p1', label: 'Senha do backup (mín. 8 caracteres)', type: 'password', autocomplete: 'new-password', required: true },
          { name: 'p2', label: 'Confirmar senha', type: 'password', autocomplete: 'new-password', required: true },
          { name: 'files', label: 'Incluir documentos do cofre', type: 'checkbox' },
          { name: 'risk', label: 'Entendo que, se eu esquecer esta senha, o backup NÃO poderá ser recuperado por ninguém', type: 'checkbox' }],
        onSubmit: async (v) => {
          if (v.p1.length < 8) return 'Use pelo menos 8 caracteres.';
          if (v.p1 !== v.p2) return 'As senhas não coincidem.';
          if (!v.risk) return 'Confirme que entendeu o risco de perder a senha.';
          const text = await B.createBackup(v.p1, v.files);
          await B.decryptPayload(text, v.p1); // verificação imediata
          download(B.backupFileName(), text, 'application/octet-stream');
          B.markBackup();
          toast('Backup gerado. Guarde o arquivo e a senha em local seguro.', { ms: 6000 });
        } });
      return false;
    },
    restore: async () => {
      const file = await pickFile('.lifeosbackup,.json,application/json,application/octet-stream');
      if (!file) return false;
      if (file.size > 300 * 1024 * 1024) { toast('Arquivo grande demais.'); return false; }
      const text = await file.text();
      const apply = async (payload) => {
        const rows = B.summarize(payload).map(([k, v]) => `<li>${esc(k)}: <b>${v}</b></li>`).join('');
        const ok = await new Promise((resolve) => {
          let done = false;
          modal({ title: 'Restaurar backup', body: `<p>Backup de <b>${U.dateTime(payload.createdAt)}</b></p><ul class="plain">${rows || '<li>(vazio)</li>'}</ul><p class="red">Todos os dados atuais serão substituídos.</p>`,
            footer: '<button class="btn" data-close>Cancelar</button><button class="btn btn-danger" data-ok>Restaurar</button>',
            onMount: (el, close) => { el.querySelector('[data-ok]').onclick = () => { done = true; resolve(true); close(); }; },
            onClose: () => { if (!done) resolve(false); } });
        });
        if (!ok) return;
        await B.restore(payload);
        toast('Dados restaurados com sucesso.');
        location.hash = '#/home';
      };
      if (B.isPlainExport(text)) { await apply(JSON.parse(text)); return false; }
      form({ title: 'Senha do backup', submitLabel: 'Verificar', fields: [{ name: 'pw', label: 'Senha', type: 'password', required: true }],
        onSubmit: async (v) => {
          try { const payload = await B.decryptPayload(text, v.pw); setTimeout(() => apply(payload), 250); }
          catch (e) { return e.message || 'Não foi possível abrir o backup.'; }
        } });
      return false;
    },
    exportJson: async () => {
      if (!(await confirmDialog('O arquivo JSON NÃO é criptografado. Qualquer pessoa com acesso a ele poderá ler seus dados. Continuar?', { confirmLabel: 'Exportar' }))) return false;
      download('LifeOS-dados.json', await B.plainExport(), 'application/json');
      return false;
    },
  },
};

// ---------- Notificações ----------
export const notifications = {
  render() {
    const p = db.profile();
    const perm = notificationPermission();
    const permLabel = { granted: 'Permitida', denied: 'Bloqueada (libere nas configurações do navegador)', default: 'Não solicitada', unsupported: 'Não suportada neste navegador' }[perm];
    return `${back('profile', 'Perfil e ajustes')}<header class="top"><h1>Notificações</h1></header>
      <div class="card"><div class="row-sb"><span>Permissão</span><b>${permLabel}</b></div>
        <div class="btn-row">${perm === 'default' ? '<button class="btn btn-primary" data-act="askNotif">Permitir notificações</button>' : ''}<button class="btn" data-act="testNotif">Enviar teste</button></div>
        <p class="muted small">Os avisos são gerados no próprio aparelho, sem servidor. Na versão web eles disparam enquanto o LifeOS estiver aberto (ou em segundo plano recente). Ao abrir o app, avisos atrasados das últimas 12 horas aparecem. Para lembretes críticos, mantenha o app instalado e aberto em segundo plano.</p></div>
      <div class="card"><h3>Categorias</h3>${Object.entries(D.NOTIF_CATS).map(([k, c]) => {
        const s = p.notif?.[k] || {};
        return `<div class="li"><label class="check grow"><input type="checkbox" data-change="notifOn" data-k="${k}" ${s.on === false ? '' : 'checked'}><span>${c.label}</span></label>
          ${['provas', 'trabalhos', 'compromissos', 'contas', 'metas'].includes(k) ? `<select data-change="notifLead" data-k="${k}" aria-label="Antecedência">${Object.entries(D.LEAD_OPTIONS).map(([m, l]) => `<option value="${m}" ${Number(m) === (s.lead ?? c.lead) ? 'selected' : ''}>${l}</option>`).join('')}</select>` : ''}</div>`;
      }).join('')}
      <div class="field"><label class="lbl">Horário padrão (contas, revisões, dia inteiro)</label><select data-change="notifHour">${[...Array(18).keys()].map((i) => i + 5).map((h) => `<option value="${h}" ${h === p.notifDefaultHour ? 'selected' : ''}>${h}:00</option>`).join('')}</select></div></div>`;
  },
  actions: {
    askNotif: async () => { await requestNotifications(); },
    testNotif: () => { testNotification(); return false; },
  },
  changes: {
    notifOn: (d, el) => { const n = { ...db.profile().notif }; n[d.k] = { ...(n[d.k] || {}), on: el.checked }; db.setProfile({ notif: n }); },
    notifLead: (d, el) => { const n = { ...db.profile().notif }; n[d.k] = { ...(n[d.k] || {}), lead: Number(el.value) }; db.setProfile({ notif: n }); },
    notifHour: (d, el) => db.setProfile({ notifDefaultHour: Number(el.value) }),
  },
};

// ---------- Armazenamento ----------
export const storage = {
  render() {
    return `${back('settings', 'Configurações')}<header class="top"><h1>Armazenamento</h1></header>
      <div class="card" data-storage><p class="muted">Calculando…</p></div>
      <div class="card"><h3>Onde ficam os dados</h3><ul class="plain small">
        <li>📦 IndexedDB deste navegador, neste aparelho (origem ${esc(location.origin)})</li>
        <li>🔐 Tudo cifrado; a chave só existe na memória enquanto o app está desbloqueado</li>
        <li>📄 ${db.all('documents').length} documento(s) no cofre</li></ul></div>`;
  },
  after() {
    const el = document.querySelector('[data-storage]');
    if (el) db.storageInfo().then((s) => { el.innerHTML = `<div class="row-sb"><span>Uso</span><b>${U.bytes(s.usage)}</b></div><div class="row-sb"><span>Cota disponível</span><b>${s.quota ? U.bytes(s.quota) : '–'}</b></div><div class="row-sb"><span>Persistente</span><b>${s.persisted ? 'Sim' : 'Não'}</b></div>`; });
  },
};

// ---------- Instalação ----------
export const install = {
  render() {
    const local = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);
    return `${back('profile', 'Perfil e ajustes')}<header class="top"><h1>Instalar</h1></header>
      <div class="card"><h3>💻 Windows (Edge ou Chrome)</h3><ol class="steps small"><li>Com o LifeOS aberto, clique no ícone de instalar na barra de endereço (ou menu ⋯ › Aplicativos › Instalar este site como aplicativo).</li><li>Ele ganha atalho no Menu Iniciar e abre em janela própria, mesmo sem internet.</li></ol>
        <button class="btn btn-primary" data-act="installNow">Instalar agora</button></div>
      <div class="card"><h3>📱 Android (Chrome)</h3><ol class="steps small"><li>Abra o endereço do LifeOS no Chrome.</li><li>Menu ⋮ › "Instalar app" ou "Adicionar à tela inicial".</li></ol></div>
      <div class="card"><h3>📱 iPhone (Safari)</h3><ol class="steps small"><li>Abra o endereço do LifeOS no Safari.</li><li>Toque em Compartilhar › "Adicionar à Tela de Início".</li><li>Abra sempre pelo ícone (os dados ficam ligados ao app instalado).</li></ol></div>
      ${local ? '<div class="card warn">Você está usando a versão local (localhost). Ela funciona só neste computador. Para usar no celular, o LifeOS precisa estar publicado em um endereço HTTPS (ex.: GitHub Pages, gratuito). Veja o README.</div>' : ''}`;
  },
  actions: {
    installNow: async () => {
      const ev = window.__installPrompt;
      if (ev) { ev.prompt(); await ev.userChoice; window.__installPrompt = null; }
      else toast('Use o ícone de instalar na barra de endereço do navegador (ou o app já está instalado).', { ms: 6000 });
      return false;
    },
  },
};

// ---------- Limitações ----------
export const limits = {
  render() {
    return `${back('settings', 'Configurações')}<header class="top"><h1>Limitações conhecidas</h1></header>
      <div class="card"><h3>Segurança</h3><ul class="plain small">
        <li>Nenhum aplicativo é inviolável. A proteção depende da força da sua senha e de o aparelho não estar comprometido (malware, extensões maliciosas do navegador).</li>
        <li>Enquanto o app está desbloqueado, os dados ficam descriptografados na memória do navegador.</li>
        <li>Se você esquecer a senha do app, os dados NÃO podem ser recuperados — só restaurando um backup (com a senha do backup).</li>
        <li>Não há Face ID/Windows Hello nesta versão web; o desbloqueio é por senha.</li>
        <li>As tentativas erradas de senha são limitadas pela interface, mas quem copiar os arquivos do navegador pode tentar senhas fora do app. Use uma senha forte.</li></ul></div>
      <div class="card"><h3>Funcionalidades</h3><ul class="plain small">
        <li>Notificações funcionam enquanto o app está aberto ou em segundo plano recente; não há push com o app fechado.</li>
        <li>Computador e celular não sincronizam sozinhos; use o backup para levar os dados.</li>
        <li>A foto das compras serve de referência; a identificação automática de alimentos não está disponível na versão web.</li>
        <li>O assistente entende frases comuns em português, não tudo; sempre há confirmação.</li>
        <li>Concursos: não há busca automática de editais; os dados são cadastrados por você.</li>
        <li>Navegadores podem apagar dados de sites não instalados em caso de pouco espaço. Instale o app e faça backups.</li></ul></div>`;
  },
};

// ---------- Sincronização ----------
function syncLabel() {
  const s = S.getStatus();
  return { off: 'Desativada', ok: s.lastSync ? `Sincronizado ${U.time(s.lastSync)}` : 'Ativa', syncing: 'Sincronizando…', error: 'Erro — toque para ver', offline: 'Sem internet — tenta de novo sozinho' }[s.state] || '';
}

/** Depois de entrar na conta: liga este aparelho (e resolve o caso de a conta já ter outros dados). */
async function connectThisDevice() {
  const r = await S.connectExisting();
  if (r.ok) { toast('Sincronização ativada.'); return; }
  form({
    title: 'Juntar com os dados da conta',
    intro: '<p class="small">Esta conta já tem dados de outro aparelho. Para juntar tudo, digite a <b>senha do LifeOS usada no outro aparelho</b>. Depois disso, ela passa a ser a senha do LifeOS também aqui, e os dados dos dois aparelhos são mesclados.</p>',
    fields: [{ name: 'pw', label: 'Senha do LifeOS do outro aparelho', type: 'password', required: true }],
    submitLabel: 'Juntar dados',
    onSubmit: async (v) => {
      const ok = await S.mergeIntoRemoteVault(r.remoteVault, v.pw);
      if (!ok) return 'Senha incorreta.';
      toast('Dados mesclados. Use a senha do outro aparelho daqui em diante.', { ms: 7000 });
    },
  });
}

export const sync = {
  render() {
    const st = S.getStatus();
    const stateText = { off: 'Desativada', ok: 'Ativa', syncing: 'Sincronizando…', error: 'Erro', offline: 'Sem internet' }[st.state] || '';
    const color = { ok: 'green', syncing: '', error: 'red', offline: 'orange', off: 'muted' }[st.state] || '';
    return `${back('profile', 'Perfil e ajustes')}<header class="top"><h1>Sincronização</h1></header>
      <div class="card"><div class="row-sb"><span>Status</span><b class="${color}">${esc(stateText)}</b></div>
        <div data-account class="small muted"></div>
        ${st.lastSync ? `<div class="row-sb small"><span class="muted">Última sincronização</span><span>${U.dateTime(st.lastSync)}</span></div>` : ''}
        ${st.message ? `<p class="small ${st.state === 'error' ? 'red' : 'orange'}">${esc(st.message)}</p>` : ''}
        <div data-actions class="btn-row"></div></div>
      <div data-connect></div>
      <div class="card"><h3>Como funciona</h3><ul class="plain small">
        <li>🔐 Seus dados saem deste aparelho <b>já cifrados com a sua senha do LifeOS</b>. O serviço na nuvem (Supabase) só guarda blocos ilegíveis.</li>
        <li>🔁 Mudanças sincronizam sozinhas em poucos segundos, a cada minuto e quando a internet volta. Sem internet, tudo continua funcionando.</li>
        <li>🧩 Edições em aparelhos diferentes são juntadas registro a registro; se o mesmo registro for editado nos dois, vale a última edição.</li>
        <li>📎 Documentos anexados também vão para a nuvem (cifrados) e são baixados no outro aparelho quando você abre.</li>
        <li>🔑 São duas senhas: a da <b>conta</b> (entrar na nuvem) e a do <b>LifeOS</b> (abrir os dados). Sem a senha do LifeOS, nem a conta dá acesso ao conteúdo.</li></ul></div>`;
  },
  after() {
    (async () => {
      const acc = await S.account();
      const connected = await S.isConnected();
      const accEl = document.querySelector('[data-account]');
      const actEl = document.querySelector('[data-actions]');
      const conEl = document.querySelector('[data-connect]');
      if (!accEl) return;
      if (connected) {
        accEl.innerHTML = `Conta: <b>${esc(acc?.email || '')}</b>`;
        actEl.innerHTML = '<button class="btn btn-primary" data-act="syncNow">Sincronizar agora</button><button class="btn" data-act="syncOff">Desconectar este aparelho</button>';
        conEl.innerHTML = '';
        return;
      }
      const cfg = await S.getConfig();
      const needCfg = !S.hasBuiltInConfig();
      conEl.innerHTML = `<form class="card form" data-submit="syncLogin">
        <h3>Ativar neste aparelho</h3>
        <p class="small muted">Use a mesma conta em todos os seus aparelhos. Comece pelo aparelho que já tem seus dados.</p>
        ${needCfg ? `<div class="field"><label class="lbl" for="sy_url">Endereço do projeto Supabase</label><input id="sy_url" name="url" placeholder="https://xxxx.supabase.co" value="${esc(cfg.url)}" autocomplete="off"></div>
        <div class="field"><label class="lbl" for="sy_key">Chave pública (anon key)</label><input id="sy_key" name="key" placeholder="eyJhbGciOi…" value="${esc(cfg.anonKey)}" autocomplete="off"></div>` : ''}
        <div class="field"><label class="lbl" for="sy_email">E-mail da conta</label><input id="sy_email" name="email" type="email" autocomplete="email" required></div>
        <div class="field"><label class="lbl" for="sy_pw">Senha da conta (mín. 6)</label><input id="sy_pw" name="password" type="password" autocomplete="current-password" required></div>
        <p class="form-err" data-err></p>
        <div class="btn-row"><button class="btn btn-primary" name="mode" value="signin">Entrar</button><button class="btn" name="mode" value="signup">Criar conta</button></div></form>`;
    })();
  },
  submit: {
    syncLogin: async (f, e) => {
      const err = f.querySelector('[data-err]');
      const mode = e.submitter?.value || 'signin';
      const email = f.email.value.trim();
      const pw = f.password.value;
      if (!email || pw.length < 6) { err.textContent = 'Informe e-mail e senha (mín. 6 caracteres).'; return; }
      f.querySelectorAll('button').forEach((b) => { b.disabled = true; });
      try {
        if (f.url) await S.saveConfig(f.url.value, f.key.value);
        if (mode === 'signup') {
          const r = await S.signUp(email, pw);
          if (r.needsConfirm) { err.textContent = 'Conta criada. Confirme pelo link enviado ao seu e-mail e depois toque em "Entrar".'; return; }
        } else {
          await S.signIn(email, pw);
        }
        await S.start();
        await connectThisDevice();
      } catch (ex) {
        err.textContent = ex.message || 'Não foi possível conectar.';
      } finally {
        f.querySelectorAll('button').forEach((b) => { b.disabled = false; });
        document.dispatchEvent(new Event('lifeos:refresh'));
      }
    },
  },
  actions: {
    syncNow: async () => { await S.syncNow(); const s = S.getStatus(); toast(s.state === 'ok' ? 'Sincronizado.' : s.message || 'Não foi possível sincronizar agora.'); },
    syncOff: async () => {
      if (await confirmDialog('Desconectar este aparelho da nuvem? Os dados continuam aqui e na nuvem; só param de sincronizar neste aparelho.', { confirmLabel: 'Desconectar' })) {
        await S.signOut(); toast('Aparelho desconectado.');
      }
    },
  },
};
