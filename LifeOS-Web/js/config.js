// Configuração da sincronização (Supabase, plano gratuito).
// Preencha com os dados do SEU projeto: Supabase › Project Settings › API.
// A "anon public key" é feita para ficar no app (não é senha): o acesso aos dados
// é protegido por login e pelas regras do banco, e o conteúdo vai cifrado com a sua senha.
export const SYNC_DEFAULTS = {
  url: '',      // ex.: 'https://abcdefghijklm.supabase.co'
  anonKey: '',  // ex.: 'eyJhbGciOi...'
};
