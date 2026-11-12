# Segurança e privacidade — LifeOS Web

## Implementado

| Controle | Como |
|---|---|
| Dados cifrados em repouso | Todas as coleções e documentos são cifrados com AES-256-GCM antes de ir para o IndexedDB. Verificado nos testes: o texto não aparece no banco do navegador. |
| Chave | Chave de dados aleatória (256 bits), guardada "embrulhada" por uma chave derivada da senha (PBKDF2-SHA256, 310 mil iterações, salt de 16 bytes). Trocar a senha só re-embrulha a chave. |
| Bloqueio | Ao bloquear (manual, inatividade ou app em segundo plano além do tempo configurado), a chave e os dados descriptografados são descartados da memória. |
| Tentativas de senha | Após 5 erros, espera progressiva (30 s → 1 h). |
| Tela no seletor de apps | Conteúdo desfocado quando o app vai para segundo plano. |
| Documentos sensíveis | Exigem a senha novamente para abrir ou exportar. |
| Backup | Arquivo `.lifeosbackup`: AES-256-GCM, chave por PBKDF2 (310 mil) a partir de uma senha de backup; cabeçalho autenticado; SHA-256 do conteúdo conferido; verificado logo após ser gerado. Adulteração ou senha errada são detectadas. |
| XSS | Todo texto do usuário passa por escape antes de ir para a tela; Content-Security-Policy bloqueia scripts externos e inline (`script-src 'self'`). |
| Rede | Nenhuma requisição externa. O único link externo é o "link oficial" de concurso cadastrado pelo usuário (só `https://`, com `noopener noreferrer`). |
| Servidor local (Windows) | Só escuta em `localhost`, só lê arquivos da pasta do app, bloqueia `..` e não serve `.ps1/.bat`. |
| CSV | Proteção contra injeção de fórmulas em planilhas. |
| Arquivos | Nomes sanitizados; limite de 25 MB por documento. |

## Sincronização (Supabase)

- O conteúdo é cifrado **no aparelho** com a chave de dados (AES-256-GCM) antes de ir para a nuvem; o Supabase só armazena blocos ilegíveis (verificado nos testes: nenhum texto legível chegou ao servidor).
- Para outro aparelho abrir os dados, a nuvem guarda também a chave de dados **embrulhada pela senha do LifeOS** (PBKDF2, 310 mil iterações). Sem a senha do LifeOS, a conta da nuvem não dá acesso ao conteúdo.
- Regras do banco (RLS) e do armazenamento: cada conta só lê e altera os próprios dados.
- A chave pública (anon) fica no app por design; nunca use a chave `service_role`.
- Risco que aumenta: quem obtiver o banco do Supabase pode tentar adivinhar a senha do LifeOS offline. **Use uma senha longa** (frase).
- Metadados visíveis na nuvem: e-mail da conta, nomes das coleções, tamanhos e datas de atualização, tipo de aparelho.

## Limitações reais

1. **Não é inviolável.** Malware no computador, extensões maliciosas do navegador ou alguém usando o aparelho com o app desbloqueado podem acessar os dados.
2. **Senha esquecida = dados perdidos.** Não há recuperação (é o preço da criptografia de verdade). Faça backups.
3. **Ataque offline.** Quem copiar os arquivos do navegador pode tentar adivinhar a senha fora do app; o limite de tentativas não vale nesse caso. O PBKDF2 encarece isso, mas a defesa principal é uma **senha forte** (frase longa).
4. **Sem biometria** nesta versão (Face ID / Windows Hello não estão integrados).
5. **Metadados de lembretes.** Para avisar mesmo com o app bloqueado, uma lista de horários de lembretes (sem títulos ou valores) fica fora da criptografia.
6. **Navegador pode limpar dados** de sites não instalados quando falta espaço. Instale o app (pedimos "armazenamento persistente") e faça backups.
7. **Exportação JSON** e **CSV** não são cifradas (o app avisa).
8. **Sem auditoria externa** do código.
