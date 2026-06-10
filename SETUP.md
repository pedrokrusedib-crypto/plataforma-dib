# Setup — Plataforma Dib & Dib

Este guia cobre os passos únicos no Supabase e o deploy no Vercel. O `index.html` já está pronto e aponta para:

- **Supabase URL**: `https://ctkbfvalqfcjebxfylry.supabase.co`
- **Anon key** (pública, segura para o frontend): `sb_publishable_wPNwxdMjtFzdp2UcExI3UA_P9ULTDyw`

> A chave `anon`/`publishable` pode ficar exposta no frontend — o acesso aos dados é controlado pelas políticas de RLS do banco. **Nunca** use a chave `service_role` no `index.html` ou em qualquer código que rode no navegador.

## 1. Aplicar o schema no Supabase

1. Acesse o [painel do Supabase](https://supabase.com/dashboard/project/ctkbfvalqfcjebxfylry).
2. Vá em **SQL Editor → New query**.
3. Cole o conteúdo inteiro de `schema.sql` e clique em **Run**.
4. Isso cria as tabelas (`obras`, `disciplinas`, `profiles`, `invites`, `invite_obras`, `obra_access`, `versoes`, `versao_feedback`, `disciplina_chat`, `atas`), as funções/triggers de apoio, ativa RLS com as políticas corretas, semeia o controlador inicial (`pedro@dibdib.com.br`) e os dados de exemplo das duas obras.
5. O script é seguro para rodar de novo (usa `if not exists` / `or replace` / `on conflict do nothing`), caso precise reaplicar depois de alguma alteração.

## 2. Configurar autenticação (magic link / OTP)

A plataforma usa **somente login por link mágico** (sem senha). Em **Authentication → Providers**:

- O provedor **Email** já vem habilitado por padrão — não precisa mexer.
- **Não desative** "Allow new users to sign up". Embora o objetivo seja "ninguém entra sem convite", esse controle acontece **dentro do banco**: a trigger `handle_new_user` só cria a linha em `profiles` (e portanto libera o app) se o e-mail estiver na tabela `invites` com `status = 'active'`. Se os signups forem desabilitados no Supabase, o primeiro login de uma pessoa convidada também falha.
- Quem tentar logar sem estar na lista de convites: o Supabase cria a sessão normalmente, mas o `index.html` não encontra `profiles` para esse usuário e mostra a tela "Acesso não autorizado" + botão Sair — a pessoa não acessa nenhum dado (RLS bloqueia tudo).

### URLs de redirecionamento

Em **Authentication → URL Configuration**:

- **Site URL**: a URL de produção, ex.: `https://pedrokrusedib-crypto.github.io/plataforma-dib/`.
- **Redirect URLs**: adicione essa mesma URL de produção (com `/**` no final, ex.: `https://pedrokrusedib-crypto.github.io/plataforma-dib/**`) e, se for testar localmente, também `http://localhost:8080` e `http://localhost:8080/**`.

O link mágico enviado por e-mail redireciona de volta para `window.location.origin + window.location.pathname` (o mesmo endereço de onde o login foi pedido). Se essa URL não estiver na lista de Redirect URLs, o Supabase recusa o redirecionamento.

### E-mail (opcional, recomendado para produção)

O serviço de e-mail padrão do Supabase tem limite baixo de envios (poucos e-mails por hora) — suficiente para testes, mas não para uso real. Para produção, configure um provedor SMTP próprio em **Authentication → Settings → SMTP Settings** (ex.: Resend, Postmark, SendGrid).

## 3. Deploy no GitHub Pages

O app é um único `index.html` estático na raiz do repositório, sem build — perfeito para o GitHub Pages.

1. Suba o repositório para o GitHub (se ainda não estiver lá). O repositório precisa ser **público** para usar o GitHub Pages no plano gratuito.
2. No GitHub, vá em **Settings → Pages**.
3. Em **Build and deployment → Source**, escolha **Deploy from a branch**.
4. Em **Branch**, escolha `main` e a pasta `/ (root)`, depois **Save**.
5. Em alguns minutos o site fica disponível em `https://<usuário>.github.io/<repositório>/` (ex.: `https://pedrokrusedib-crypto.github.io/plataforma-dib/`).
6. Volte ao passo 2 (acima) para configurar **Site URL** e **Redirect URLs** no Supabase com essa URL.
7. Toda vez que houver `git push` para `main`, o GitHub Pages republica o site automaticamente.

## 4. Gerenciar pessoas e permissões

Logado como controlador (`pedro@dibdib.com.br`):

- **Pessoas & acessos** (menu lateral, só aparece para administradores) lista todos os usuários ativos e convites pendentes.
- **+ Convidar pessoa**: informe nome, e-mail, papel, função (Membro ou Administrador) e marque as obras que a pessoa pode acessar. Isso grava em `invites` (e `invite_obras`, para pré-liberar as obras). Quando a pessoa entrar pela primeira vez com esse e-mail, o acesso é liberado automaticamente.
- Dentro de cada obra, a aba **Acessos** mostra só quem tem acesso àquela obra, com o mesmo botão de edição (✎) — útil para liberar/revogar uma obra específica para alguém.
- **✎ (editar)**: reabre o formulário de convite para ajustar nome, papel, função e obras de uma pessoa já existente.
- **🗑 (revogar)**: marca o convite como `revoked`, remove pré-liberações pendentes e remove o acesso às obras de quem já tem login. A pessoa continua conseguindo logar (a sessão do Supabase não é apagada), mas deixa de ver qualquer obra.
- Quem tem `role = 'controlador'` sempre vê todas as obras, independentemente da tabela `obra_access`.

## 5. Trocar/adicionar um controlador

Edite o bloco de seed em `schema.sql` e rode no SQL Editor:

```sql
insert into public.invites (email, nome, papel, cor, role, status)
values ('outro-admin@empresa.com', 'Nome', 'Administrador', 'linear-gradient(135deg,#324a63,#16202b)', 'controlador', 'active')
on conflict (email) do update set role = 'controlador', status = 'active';
```

Ou, com o app já em uso, peça para o controlador atual abrir **Pessoas & acessos → ✎** na pessoa e mudar a "Função" para **Administrador**.
