# LifeOS no celular (PWA)

Gratuito, sem cartão, uns 10 minutos. O celular só instala o app a partir de um link **https**, então primeiro o app é publicado (só os arquivos do app; **nenhum dado seu vai junto**, eles ficam cifrados em cada aparelho).

## 1. Publicar o app (Netlify)

1. No PC, acesse **app.netlify.com** e crie a conta gratuita (pode entrar com e-mail ou GitHub).
   - Crie a conta **antes** de enviar: sem conta, o site enviado é apagado em pouco tempo.
2. Vá em **app.netlify.com/drop** (ou *Add new site › Deploy manually*).
3. Arraste a pasta **`LifeOS-Web`** inteira (a pasta, não os arquivos de dentro) para a página.
4. Você recebe um link como `https://nome-aleatorio.netlify.app`.
   - Para mudar o nome: *Site configuration › Change site name* (ex.: `meu-lifeos-123`).

## 2. Instalar no celular

Abra o link:
- **iPhone:** no **Safari** › botão Compartilhar › **Adicionar à Tela de Início**. Abra sempre pelo ícone.
- **Android:** no **Chrome** › menu ⋮ › **Instalar app** (ou "Adicionar à tela inicial").

Crie a senha do LifeOS no celular.

## 3. Levar seus dados do PC para o celular

1. No PC: **Perfil e ajustes › Backup e restauração › Gerar backup** (com uma senha de backup).
2. Mande o arquivo `.lifeosbackup` para o celular (Google Drive, OneDrive, iCloud Drive, WhatsApp para você mesmo, cabo).
3. No celular: **Perfil e ajustes › Backup e restauração › Escolher arquivo de backup** › senha do backup › Restaurar.

## Importante

- PC e celular **não sincronizam sozinhos**. Cada um tem sua cópia. Para levar dados de um para o outro, repita o passo 3 (a restauração substitui os dados do aparelho que recebe).
- No iPhone, o Safari pode apagar dados de sites que ficam **muitas semanas sem abrir**. Abra o app com frequência e gere backup de vez em quando.
- Se quiser, use também o link do Netlify no PC (instale pelo Edge: ⋯ › Aplicativos › Instalar este site como aplicativo). Os dados do `localhost` passam para lá pelo mesmo backup/restauração.

## Atualizações do app

Quando o LifeOS for atualizado: Netlify › seu site › **Deploys** › arraste a pasta `LifeOS-Web` de novo. Os aparelhos pegam a versão nova ao abrir o app (feche e abra se não aparecer). Os dados continuam.
