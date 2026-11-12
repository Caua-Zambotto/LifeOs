# LifeOS (app web / PWA) — versão principal

> **Esta é a versão em uso**: um único app para o PC e o celular, com **sincronização cifrada** entre aparelhos (Supabase, plano gratuito).
> 👉 Para configurar, siga o **[PASSO-A-PASSO.md](PASSO-A-PASSO.md)**.
> A versão nativa de iPhone (`../LifeOS`) está pausada.

### Sincronização (resumo técnico)

- `js/sync.js`: só API REST do Supabase (sem SDK). Uma linha por coleção + arquivos no Storage; tudo cifrado no aparelho com a chave de dados (AES-256-GCM) antes do envio.
- Mesclagem registro a registro (`updatedAt` e registros de exclusão), então edições em aparelhos diferentes não se perdem. Se o mesmo registro for editado nos dois, vale a última edição.
- `supabase/setup.sql`: tabela, gatilho de data no servidor, RLS (cada usuário só acessa os próprios dados) e bucket privado.
- Testado com um servidor que imita o Supabase e três "aparelhos": envio, entrada em aparelho novo, documentos, edições cruzadas, exclusões, junção de aparelho que já tinha dados, troca de senha e modo offline.

Organizador pessoal: agenda, faculdade, concursos, finanças, treinos, corpo, alimentação, metas, hábitos e documentos — com um assistente que entende frases em português.

- **Custo zero:** JavaScript puro, sem bibliotecas, sem servidor, sem APIs pagas.
- **Offline:** depois de aberto uma vez, funciona sem internet (service worker).
- **Privado:** todos os dados ficam no aparelho, **cifrados** (AES-256-GCM) com a sua senha.
- **Um só app para tudo:** no Windows ele é instalado como aplicativo pelo Edge/Chrome; no celular, como PWA.

## Usar no Windows (agora)

1. Dê dois cliques em **`Iniciar LifeOS.bat`**.
   - Ele inicia um servidor local mínimo (`servidor.ps1`, só PowerShell, nada para instalar) em `http://localhost:8765` e abre o LifeOS numa janela do Edge.
2. Crie sua senha (mínimo de 8 caracteres). **Não existe recuperação de senha.**
3. Para ter atalho no Menu Iniciar: no Edge, menu **⋯ › Aplicativos › Instalar este site como aplicativo** (ou Perfil › Instalar no próprio LifeOS).
   - Depois de instalado, o app abre mesmo sem o servidor rodando (os arquivos ficam em cache). Use o `.bat` só se o app não abrir.

> Os dados ficam ligados ao endereço `http://localhost:8765` neste navegador. Não troque a porta e não limpe os "dados de sites" do Edge sem antes fazer um backup.

## Usar no celular (PWA)

Celulares só instalam PWAs a partir de um endereço **HTTPS**. Opções gratuitas para publicar esta pasta (são só arquivos estáticos; nenhum dado seu vai junto):

| Opção | Como | Observação |
|---|---|---|
| **GitHub Pages** | Criar um repositório, enviar o conteúdo de `LifeOS-Web/`, ativar Pages (Settings › Pages › branch `main`) | Gratuito. Em conta gratuita o repositório precisa ser **público** (o código fica visível; seus dados não). |
| **Netlify Drop** | Arrastar a pasta `LifeOS-Web` em app.netlify.com/drop | Gratuito, sem Git. |
| **Cloudflare Pages** | Upload direto da pasta | Gratuito. |

Depois, no celular:
- **Android (Chrome):** abrir o endereço › menu ⋮ › **Instalar app**.
- **iPhone (Safari):** abrir o endereço › Compartilhar › **Adicionar à Tela de Início**. Abra sempre pelo ícone.

### Levar os dados do PC para o celular

Computador e celular **não sincronizam sozinhos** (não há servidor). Para transferir:
1. No PC: Perfil › Backup › **Gerar backup** (com senha) — baixa um arquivo `.lifeosbackup`.
2. Envie o arquivo para o celular (Google Drive, iCloud Drive, cabo, e-mail para você mesmo).
3. No celular: crie a senha do app › Perfil › Backup › **Escolher arquivo de backup** › senha do backup › Restaurar.

## Testes

Com o servidor rodando, abra `http://localhost:8765/tests.html`: **60 testes** automatizados (assistente, datas, criptografia, finanças, estudos, receitas, backup, desfazer, mescla, calendário integrado, próximo treino, % do edital) rodam no navegador. Resultado atual: 60/60.

## Estrutura

```
LifeOS-Web/
├── index.html, manifest.webmanifest, sw.js   # app e PWA
├── Iniciar LifeOS.bat, servidor.ps1          # lançador do Windows
├── css/app.css                               # visual (claro/escuro, celular e desktop)
├── icons/                                    # ícones do app
├── js/
│   ├── app.js        # inicialização, bloqueio, navegação
│   ├── store.js      # banco IndexedDB cifrado
│   ├── crypto.js     # Web Crypto (AES-GCM, PBKDF2)
│   ├── nlp.js        # assistente: interpretação de frases em pt-BR
│   ├── domain.js     # regras: finanças, estudos, hábitos, receitas, gravar/desfazer
│   ├── backup.js     # backup cifrado, JSON, CSV
│   ├── notify.js     # notificações locais
│   ├── ui.js, charts.js
│   └── views/        # telas: home, studies (Estudos), agenda (Calendário), health + live (Treino e treino ao vivo),
│                     #        study (Editais/faculdade), finance, settings (Perfil e ajustes)…
├── tests.html, js/tests.js
└── docs/SECURITY.md, docs/TEST_REPORT.md
```

## Relação com a versão iPhone nativa

A pasta `../LifeOS/` contém a versão nativa em Swift/SwiftUI (não compilada — exige Mac). A versão web cobre as mesmas áreas e é a que dá para usar hoje no Windows e no celular. As duas usam formatos de backup diferentes.
