-- ============================================================
-- DIB & DIB — Plataforma de Gestão de Projetos
-- Schema Postgres / Supabase: autenticação, papéis, permissões
-- por obra e dados das obras (disciplinas, versões, atas, chat).
--
-- Rode este arquivo inteiro uma vez no SQL Editor do Supabase
-- (Project > SQL Editor > New query > colar > Run).
-- É seguro reexecutar: usa "if not exists" / "or replace" /
-- "on conflict do nothing" sempre que possível.
-- ============================================================


-- ============================================================
-- 1) OBRAS / PROJETOS
-- ============================================================
create table if not exists public.obras (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  local      text,
  cor        text,
  progresso  int  not null default 0,
  ordem      int  not null default 0,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 2) DISCIPLINAS (de cada obra)
-- ============================================================
create table if not exists public.disciplinas (
  id         uuid primary key default gen_random_uuid(),
  obra_id    uuid not null references public.obras(id) on delete cascade,
  nome       text not null,
  status     text not null default 'pend'
             check (status in ('dev','wait','review','ok','pend','redo')),
  aguardando text,
  link_drive text,
  ordem      int  not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists disciplinas_obra_id_idx on public.disciplinas(obra_id);


-- ============================================================
-- 3) PROFILES — um por usuário autenticado e autorizado
--    (criado automaticamente no primeiro login, via trigger)
-- ============================================================
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null unique,
  nome       text not null default '',
  papel      text not null default '',
  cor        text not null default 'linear-gradient(135deg,#2f6bff,#1f50cc)',
  role       text not null default 'membro'
             check (role in ('controlador','membro')),
  created_at timestamptz not null default now()
);


-- ============================================================
-- 4) INVITES — lista de e-mails autorizados pelo controlador
--    (precede o primeiro login da pessoa)
-- ============================================================
create table if not exists public.invites (
  email      text primary key,
  nome       text,
  papel      text,
  cor        text,
  role       text not null default 'membro'
             check (role in ('controlador','membro')),
  status     text not null default 'active'
             check (status in ('active','revoked')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Pré-liberação de obras para convites que ainda não logaram.
-- Quando a pessoa loga pela 1ª vez, isso é copiado para obra_access.
create table if not exists public.invite_obras (
  email   text not null references public.invites(email) on delete cascade,
  obra_id uuid not null references public.obras(id) on delete cascade,
  primary key (email, obra_id)
);


-- ============================================================
-- 5) OBRA_ACCESS — associação usuário ↔ obra (permissão real)
-- ============================================================
create table if not exists public.obra_access (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  obra_id    uuid not null references public.obras(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, obra_id)
);


-- ============================================================
-- 6) VERSOES (de cada disciplina)
-- ============================================================
create table if not exists public.versoes (
  id            uuid primary key default gen_random_uuid(),
  disciplina_id uuid not null references public.disciplinas(id) on delete cascade,
  numero        int  not null,
  titulo        text not null,
  descricao     text,
  data          date not null default current_date,
  autor_nome    text,
  status        text not null
                check (status in ('dev','wait','review','ok','pend','redo')),
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists versoes_disciplina_id_idx on public.versoes(disciplina_id);

-- numero é gerado automaticamente (1,2,3... por disciplina) e
-- exibido no front como "v{numero}".
create or replace function public.set_versao_numero()
returns trigger
language plpgsql
as $$
begin
  if new.numero is null then
    select coalesce(max(numero), 0) + 1
      into new.numero
      from public.versoes
      where disciplina_id = new.disciplina_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_versao_numero on public.versoes;
create trigger trg_versao_numero
  before insert on public.versoes
  for each row execute function public.set_versao_numero();


-- ============================================================
-- 7) FEEDBACK por versão
-- ============================================================
create table if not exists public.versao_feedback (
  id         uuid primary key default gen_random_uuid(),
  versao_id  uuid not null references public.versoes(id) on delete cascade,
  autor_id   uuid references public.profiles(id) on delete set null,
  autor_nome text,
  texto      text not null,
  created_at timestamptz not null default now()
);

create index if not exists versao_feedback_versao_id_idx on public.versao_feedback(versao_id);


-- ============================================================
-- 8) CHAT por disciplina
-- ============================================================
create table if not exists public.disciplina_chat (
  id            uuid primary key default gen_random_uuid(),
  disciplina_id uuid not null references public.disciplinas(id) on delete cascade,
  autor_id      uuid references public.profiles(id) on delete set null,
  autor_nome    text,
  texto         text not null,
  created_at    timestamptz not null default now()
);

create index if not exists disciplina_chat_disciplina_id_idx on public.disciplina_chat(disciplina_id);


-- ============================================================
-- 9) ATAS de reunião (de cada obra)
-- ============================================================
create table if not exists public.atas (
  id         uuid primary key default gen_random_uuid(),
  obra_id    uuid not null references public.obras(id) on delete cascade,
  data       date not null default current_date,
  titulo     text not null,
  resumo     text,
  drive_url  text,
  cls        text not null default '',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists atas_obra_id_idx on public.atas(obra_id);


-- ============================================================
-- 9b) NOTIF_DISMISSALS — notificações dispensadas por usuário
--     (cada pessoa fecha/limpa suas próprias notificações)
-- ============================================================
create table if not exists public.notif_dismissals (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  notif_key  text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, notif_key)
);


-- ============================================================
-- 9c) VERSAO_ARQUIVOS — uma versão pode ter vários PDFs e/ou
--     links externos
-- ============================================================
create table if not exists public.versao_arquivos (
  id         uuid primary key default gen_random_uuid(),
  versao_id  uuid not null references public.versoes(id) on delete cascade,
  tipo       text not null check (tipo in ('pdf','link')),
  nome       text not null,
  path       text, -- caminho no storage (tipo='pdf')
  url        text, -- link externo (tipo='link')
  ordem      int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists versao_arquivos_versao_id_idx on public.versao_arquivos(versao_id);


-- ============================================================
-- 9d) PDF_ANOTACOES — comentários (pins coloridos) sobre um
--     PDF, em uma página/posição específica
-- ============================================================
create table if not exists public.pdf_anotacoes (
  id         uuid primary key default gen_random_uuid(),
  arquivo_id uuid not null references public.versao_arquivos(id) on delete cascade,
  pagina     int not null default 1,
  x          numeric not null,
  y          numeric not null,
  cor        text not null default '#f5b942',
  texto      text not null,
  autor_id   uuid references public.profiles(id) on delete set null,
  autor_nome text,
  created_at timestamptz not null default now()
);

create index if not exists pdf_anotacoes_arquivo_id_idx on public.pdf_anotacoes(arquivo_id);


-- ============================================================
-- 9e) MIGRAÇÃO — links antigos (versoes.drive_url) viram
--     registros em versao_arquivos; colunas legadas removidas
-- ============================================================
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='versoes' and column_name='drive_url') then
    insert into public.versao_arquivos (versao_id, tipo, nome, url, ordem)
    select id, 'link', 'Link', drive_url, 0
    from public.versoes
    where drive_url is not null and drive_url <> '#' and drive_url <> '';

    alter table public.versoes drop column drive_url;
  end if;

  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='versoes' and column_name='files') then
    alter table public.versoes drop column files;
  end if;
end $$;


-- ============================================================
-- 9f) PRAZOS (agenda) — prazos de entrega vinculados a uma obra
--     e, opcionalmente, a uma disciplina
-- ============================================================
create table if not exists public.prazos (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references public.obras(id) on delete cascade,
  disciplina_id uuid references public.disciplinas(id) on delete cascade,
  titulo        text not null,
  descricao     text,
  data          date not null,
  status        text not null default 'pendente'
                check (status in ('pendente','concluido')),
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists prazos_obra_id_idx on public.prazos(obra_id);
create index if not exists prazos_disciplina_id_idx on public.prazos(disciplina_id);

-- pessoas mencionadas em cada prazo: só elas (e o controlador)
-- enxergam o prazo na agenda
create table if not exists public.prazo_pessoas (
  prazo_id uuid not null references public.prazos(id) on delete cascade,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  primary key (prazo_id, user_id)
);

create index if not exists prazo_pessoas_user_id_idx on public.prazo_pessoas(user_id);


-- ============================================================
-- 9g) MIGRAÇÃO — disciplinas.link_drive (link da pasta no Drive)
-- ============================================================
alter table public.disciplinas add column if not exists link_drive text;


-- ============================================================
-- 9h) MIGRAÇÃO — versoes.descricao (descrição da versão postada)
-- ============================================================
alter table public.versoes add column if not exists descricao text;


-- ============================================================
-- 9h2) MIGRAÇÃO — disciplinas.progresso (0–100, barra de avanço)
-- ============================================================
alter table public.disciplinas add column if not exists progresso integer not null default 0;


-- ============================================================
-- 9h3) MIGRAÇÃO — atas globais (obra_id vira opcional) +
--      ata_pessoas (controle de visibilidade por pessoa)
-- ============================================================
alter table public.atas alter column obra_id drop not null;

create table if not exists public.ata_pessoas (
  id       uuid primary key default gen_random_uuid(),
  ata_id   uuid not null references public.atas(id) on delete cascade,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  unique(ata_id, user_id)
);
create index if not exists ata_pessoas_ata_id_idx  on public.ata_pessoas(ata_id);
create index if not exists ata_pessoas_user_id_idx on public.ata_pessoas(user_id);

alter table public.ata_pessoas enable row level security;

drop policy if exists ata_pessoas_select on public.ata_pessoas;
create policy ata_pessoas_select on public.ata_pessoas
  for select using (public.is_controlador() or user_id = auth.uid());

drop policy if exists ata_pessoas_insert on public.ata_pessoas;
create policy ata_pessoas_insert on public.ata_pessoas
  for insert with check (public.is_controlador());

drop policy if exists ata_pessoas_delete on public.ata_pessoas;
create policy ata_pessoas_delete on public.ata_pessoas
  for delete using (public.is_controlador());

grant select, insert, delete on public.ata_pessoas to authenticated;

-- Atualiza policy de select das atas:
-- sem restrição de obra; visibilidade por ata_pessoas ou pública (sem registros)
drop policy if exists atas_select on public.atas;
create policy atas_select on public.atas
  for select using (
    public.is_controlador()
    or created_by = auth.uid()
    or not exists (select 1 from public.ata_pessoas ap where ap.ata_id = id)
    or exists     (select 1 from public.ata_pessoas ap where ap.ata_id = id and ap.user_id = auth.uid())
  );


-- ============================================================
-- 9i) MIGRAÇÃO — permissão por disciplina dentro da obra
--      Sem registros = acesso a todas as disciplinas da obra
--      (comportamento padrão/atual). Com 1+ registros para o
--      usuário em disciplinas de uma obra, o acesso fica
--      restrito a essas disciplinas.
--      A função has_disciplina_access (seção 10) já considera
--      esta tabela.
-- ============================================================
create table if not exists public.disciplina_access (
  user_id       uuid not null references public.profiles(id) on delete cascade,
  disciplina_id uuid not null references public.disciplinas(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (user_id, disciplina_id)
);

create index if not exists disciplina_access_user_id_idx on public.disciplina_access(user_id);
create index if not exists disciplina_access_disciplina_id_idx on public.disciplina_access(disciplina_id);

alter table public.disciplina_access enable row level security;

drop policy if exists disciplina_access_select on public.disciplina_access;
create policy disciplina_access_select on public.disciplina_access
  for select using (user_id = auth.uid() or public.is_controlador());

drop policy if exists disciplina_access_insert on public.disciplina_access;
create policy disciplina_access_insert on public.disciplina_access
  for insert with check (public.is_controlador());

drop policy if exists disciplina_access_delete on public.disciplina_access;
create policy disciplina_access_delete on public.disciplina_access
  for delete using (public.is_controlador());

grant select, insert, delete on public.disciplina_access to authenticated;


-- ============================================================
-- 9j) MIGRAÇÃO — membro pode editar o próprio perfil (nome/cor)
--      A policy profiles_update (seção 12) já libera o update
--      para id = auth.uid(); este trigger garante que papel,
--      role e email só mudam pela mão do controlador.
-- ============================================================
create or replace function public.profiles_protect_admin_fields()
returns trigger
language plpgsql
as $$
begin
  if not public.is_controlador() then
    new.role  := old.role;
    new.papel := old.papel;
    new.email := old.email;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_protect_admin_fields on public.profiles;
create trigger trg_profiles_protect_admin_fields
  before update on public.profiles
  for each row execute function public.profiles_protect_admin_fields();


-- ============================================================
-- 10) FUNÇÕES DE APOIO PARA RLS
--     security definer + search_path fixo: rodam com privilégio
--     do dono (postgres), que tem BYPASSRLS, evitando recursão.
-- ============================================================
create or replace function public.is_controlador()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and role = 'controlador'
  );
$$;

create or replace function public.has_obra_access(p_obra_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select
    public.is_controlador()
    or exists(
      select 1 from public.obra_access
      where user_id = auth.uid() and obra_id = p_obra_id
    );
$$;

-- Acesso a uma disciplina:
--  - controlador: sempre
--  - membro: precisa ter acesso à obra E
--      (não ter nenhuma restrição de disciplina dentro dessa obra
--       OU ter sido liberado explicitamente para esta disciplina)
--    Sem registros em disciplina_access para a obra = acesso a todas
--    as disciplinas da obra (comportamento padrão/atual).
create or replace function public.has_disciplina_access(p_disciplina_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select
    public.is_controlador()
    or (
      exists(
        select 1
        from public.obra_access oa
        join public.disciplinas d on d.obra_id = oa.obra_id
        where oa.user_id = auth.uid() and d.id = p_disciplina_id
      )
      and (
        not exists(
          select 1
          from public.disciplina_access da
          join public.disciplinas d2 on d2.id = da.disciplina_id
          where da.user_id = auth.uid()
            and d2.obra_id = (select d3.obra_id from public.disciplinas d3 where d3.id = p_disciplina_id)
        )
        or exists(
          select 1 from public.disciplina_access da
          where da.user_id = auth.uid() and da.disciplina_id = p_disciplina_id
        )
      )
    );
$$;

create or replace function public.is_mentioned_in_prazo(p_prazo_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select
    public.is_controlador()
    or exists(
      select 1 from public.prazo_pessoas
      where prazo_id = p_prazo_id and user_id = auth.uid()
    );
$$;


-- ============================================================
-- 10b) STORAGE — bucket privado para os PDFs das versões
--      Caminho de cada arquivo: {disciplina_id}/{versao_id}/arquivo
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit)
values ('versao-arquivos', 'versao-arquivos', false, 52428800)
on conflict (id) do nothing;

drop policy if exists versao_arquivos_storage_select on storage.objects;
create policy versao_arquivos_storage_select on storage.objects
  for select using (
    bucket_id = 'versao-arquivos'
    and public.has_disciplina_access((storage.foldername(name))[1]::uuid)
  );

drop policy if exists versao_arquivos_storage_insert on storage.objects;
create policy versao_arquivos_storage_insert on storage.objects
  for insert with check (
    bucket_id = 'versao-arquivos'
    and public.has_disciplina_access((storage.foldername(name))[1]::uuid)
  );

drop policy if exists versao_arquivos_storage_delete on storage.objects;
create policy versao_arquivos_storage_delete on storage.objects
  for delete using (
    bucket_id = 'versao-arquivos'
    and public.has_disciplina_access((storage.foldername(name))[1]::uuid)
  );


-- ============================================================
-- 11) BOOTSTRAP: cria profile + obra_access no primeiro login
--     Só cria profile se o e-mail estiver em invites/active.
--     Sem profile = app trata como "não autorizado" e RLS
--     devolve vazio para todas as tabelas de dados.
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text := lower(new.email);
  v_invite public.invites%rowtype;
begin
  select * into v_invite
    from public.invites
    where email = v_email and status = 'active';

  if found then
    insert into public.profiles (id, email, nome, papel, cor, role)
    values (
      new.id,
      new.email,
      coalesce(v_invite.nome, split_part(new.email, '@', 1)),
      coalesce(v_invite.papel, case when v_invite.role = 'controlador' then 'Administrador' else 'Membro' end),
      coalesce(v_invite.cor, 'linear-gradient(135deg,#2f6bff,#1f50cc)'),
      v_invite.role
    )
    on conflict (id) do nothing;

    insert into public.obra_access (user_id, obra_id)
    select new.id, io.obra_id
      from public.invite_obras io
      where io.email = v_email
    on conflict do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================
-- 12) ROW LEVEL SECURITY
-- ============================================================
alter table public.profiles        enable row level security;
alter table public.invites         enable row level security;
alter table public.invite_obras    enable row level security;
alter table public.obra_access     enable row level security;
alter table public.obras           enable row level security;
alter table public.disciplinas     enable row level security;
alter table public.versoes         enable row level security;
alter table public.versao_feedback enable row level security;
alter table public.disciplina_chat enable row level security;
alter table public.atas            enable row level security;
alter table public.notif_dismissals enable row level security;
alter table public.versao_arquivos enable row level security;
alter table public.pdf_anotacoes   enable row level security;
alter table public.prazos          enable row level security;
alter table public.prazo_pessoas   enable row level security;

-- ---- profiles ----
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (id = auth.uid() or public.is_controlador());

-- membro pode editar o próprio perfil (nome/cor); papel/role/email
-- ficam protegidos por trigger (profiles_protect_admin_fields)
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update using (id = auth.uid() or public.is_controlador())
  with check (id = auth.uid() or public.is_controlador());

-- ---- invites ----
drop policy if exists invites_select on public.invites;
create policy invites_select on public.invites
  for select using (public.is_controlador());

drop policy if exists invites_insert on public.invites;
create policy invites_insert on public.invites
  for insert with check (public.is_controlador());

drop policy if exists invites_update on public.invites;
create policy invites_update on public.invites
  for update using (public.is_controlador())
  with check (public.is_controlador());

drop policy if exists invites_delete on public.invites;
create policy invites_delete on public.invites
  for delete using (public.is_controlador());

-- ---- invite_obras ----
drop policy if exists invite_obras_select on public.invite_obras;
create policy invite_obras_select on public.invite_obras
  for select using (public.is_controlador());

drop policy if exists invite_obras_insert on public.invite_obras;
create policy invite_obras_insert on public.invite_obras
  for insert with check (public.is_controlador());

drop policy if exists invite_obras_delete on public.invite_obras;
create policy invite_obras_delete on public.invite_obras
  for delete using (public.is_controlador());

-- ---- obra_access ----
drop policy if exists obra_access_select on public.obra_access;
create policy obra_access_select on public.obra_access
  for select using (user_id = auth.uid() or public.is_controlador());

drop policy if exists obra_access_insert on public.obra_access;
create policy obra_access_insert on public.obra_access
  for insert with check (public.is_controlador());

drop policy if exists obra_access_delete on public.obra_access;
create policy obra_access_delete on public.obra_access
  for delete using (public.is_controlador());

-- ---- obras ----
drop policy if exists obras_select on public.obras;
create policy obras_select on public.obras
  for select using (public.has_obra_access(id));

drop policy if exists obras_insert on public.obras;
create policy obras_insert on public.obras
  for insert with check (public.is_controlador());

drop policy if exists obras_update on public.obras;
create policy obras_update on public.obras
  for update using (public.is_controlador())
  with check (public.is_controlador());

drop policy if exists obras_delete on public.obras;
create policy obras_delete on public.obras
  for delete using (public.is_controlador());

-- ---- disciplinas ----
drop policy if exists disciplinas_select on public.disciplinas;
create policy disciplinas_select on public.disciplinas
  for select using (public.has_disciplina_access(id));

drop policy if exists disciplinas_insert on public.disciplinas;
create policy disciplinas_insert on public.disciplinas
  for insert with check (public.is_controlador());

drop policy if exists disciplinas_update on public.disciplinas;
create policy disciplinas_update on public.disciplinas
  for update using (public.is_controlador())
  with check (public.is_controlador());

drop policy if exists disciplinas_delete on public.disciplinas;
create policy disciplinas_delete on public.disciplinas
  for delete using (public.is_controlador());

-- ---- versoes ----
drop policy if exists versoes_select on public.versoes;
create policy versoes_select on public.versoes
  for select using (public.has_disciplina_access(disciplina_id));

drop policy if exists versoes_insert on public.versoes;
create policy versoes_insert on public.versoes
  for insert with check (public.has_disciplina_access(disciplina_id));

drop policy if exists versoes_update on public.versoes;
create policy versoes_update on public.versoes
  for update using (public.is_controlador())
  with check (public.is_controlador());

drop policy if exists versoes_delete on public.versoes;
create policy versoes_delete on public.versoes
  for delete using (public.is_controlador() or created_by = auth.uid());

-- ---- versao_feedback ----
drop policy if exists versao_feedback_select on public.versao_feedback;
create policy versao_feedback_select on public.versao_feedback
  for select using (
    exists(
      select 1 from public.versoes v
      where v.id = versao_id and public.has_disciplina_access(v.disciplina_id)
    )
  );

drop policy if exists versao_feedback_insert on public.versao_feedback;
create policy versao_feedback_insert on public.versao_feedback
  for insert with check (
    autor_id = auth.uid()
    and exists(
      select 1 from public.versoes v
      where v.id = versao_id and public.has_disciplina_access(v.disciplina_id)
    )
  );

drop policy if exists versao_feedback_update on public.versao_feedback;
create policy versao_feedback_update on public.versao_feedback
  for update using (autor_id = auth.uid() or public.is_controlador())
  with check (autor_id = auth.uid() or public.is_controlador());

drop policy if exists versao_feedback_delete on public.versao_feedback;
create policy versao_feedback_delete on public.versao_feedback
  for delete using (autor_id = auth.uid() or public.is_controlador());

-- ---- disciplina_chat ----
drop policy if exists disciplina_chat_select on public.disciplina_chat;
create policy disciplina_chat_select on public.disciplina_chat
  for select using (public.has_disciplina_access(disciplina_id));

drop policy if exists disciplina_chat_insert on public.disciplina_chat;
create policy disciplina_chat_insert on public.disciplina_chat
  for insert with check (
    autor_id = auth.uid() and public.has_disciplina_access(disciplina_id)
  );

drop policy if exists disciplina_chat_update on public.disciplina_chat;
create policy disciplina_chat_update on public.disciplina_chat
  for update using (autor_id = auth.uid() or public.is_controlador())
  with check (autor_id = auth.uid() or public.is_controlador());

drop policy if exists disciplina_chat_delete on public.disciplina_chat;
create policy disciplina_chat_delete on public.disciplina_chat
  for delete using (autor_id = auth.uid() or public.is_controlador());

-- ---- atas ----
drop policy if exists atas_select on public.atas;
create policy atas_select on public.atas
  for select using (public.has_obra_access(obra_id));

drop policy if exists atas_insert on public.atas;
create policy atas_insert on public.atas
  for insert with check (public.is_controlador());

drop policy if exists atas_update on public.atas;
create policy atas_update on public.atas
  for update using (public.is_controlador())
  with check (public.is_controlador());

drop policy if exists atas_delete on public.atas;
create policy atas_delete on public.atas
  for delete using (public.is_controlador());

-- ---- notif_dismissals ----
drop policy if exists notif_dismissals_select on public.notif_dismissals;
create policy notif_dismissals_select on public.notif_dismissals
  for select using (user_id = auth.uid());

drop policy if exists notif_dismissals_insert on public.notif_dismissals;
create policy notif_dismissals_insert on public.notif_dismissals
  for insert with check (user_id = auth.uid());

drop policy if exists notif_dismissals_delete on public.notif_dismissals;
create policy notif_dismissals_delete on public.notif_dismissals
  for delete using (user_id = auth.uid());

-- ---- versao_arquivos ----
drop policy if exists versao_arquivos_select on public.versao_arquivos;
create policy versao_arquivos_select on public.versao_arquivos
  for select using (
    exists(select 1 from public.versoes v where v.id = versao_id and public.has_disciplina_access(v.disciplina_id))
  );

drop policy if exists versao_arquivos_insert on public.versao_arquivos;
create policy versao_arquivos_insert on public.versao_arquivos
  for insert with check (
    exists(select 1 from public.versoes v where v.id = versao_id and public.has_disciplina_access(v.disciplina_id))
  );

drop policy if exists versao_arquivos_delete on public.versao_arquivos;
create policy versao_arquivos_delete on public.versao_arquivos
  for delete using (
    public.is_controlador()
    or exists(select 1 from public.versoes v where v.id = versao_id and v.created_by = auth.uid())
  );

-- ---- pdf_anotacoes ----
drop policy if exists pdf_anotacoes_select on public.pdf_anotacoes;
create policy pdf_anotacoes_select on public.pdf_anotacoes
  for select using (
    exists(
      select 1 from public.versao_arquivos va
      join public.versoes v on v.id = va.versao_id
      where va.id = arquivo_id and public.has_disciplina_access(v.disciplina_id)
    )
  );

drop policy if exists pdf_anotacoes_insert on public.pdf_anotacoes;
create policy pdf_anotacoes_insert on public.pdf_anotacoes
  for insert with check (
    autor_id = auth.uid()
    and exists(
      select 1 from public.versao_arquivos va
      join public.versoes v on v.id = va.versao_id
      where va.id = arquivo_id and public.has_disciplina_access(v.disciplina_id)
    )
  );

drop policy if exists pdf_anotacoes_update on public.pdf_anotacoes;
create policy pdf_anotacoes_update on public.pdf_anotacoes
  for update using (autor_id = auth.uid() or public.is_controlador())
  with check (autor_id = auth.uid() or public.is_controlador());

drop policy if exists pdf_anotacoes_delete on public.pdf_anotacoes;
create policy pdf_anotacoes_delete on public.pdf_anotacoes
  for delete using (autor_id = auth.uid() or public.is_controlador());

-- ---- prazos ----
drop policy if exists prazos_select on public.prazos;
create policy prazos_select on public.prazos
  for select using (public.is_mentioned_in_prazo(id));

drop policy if exists prazos_insert on public.prazos;
create policy prazos_insert on public.prazos
  for insert with check (public.is_controlador());

drop policy if exists prazos_update on public.prazos;
create policy prazos_update on public.prazos
  for update using (public.is_controlador())
  with check (public.is_controlador());

drop policy if exists prazos_delete on public.prazos;
create policy prazos_delete on public.prazos
  for delete using (public.is_controlador());

-- ---- prazo_pessoas ----
drop policy if exists prazo_pessoas_select on public.prazo_pessoas;
create policy prazo_pessoas_select on public.prazo_pessoas
  for select using (user_id = auth.uid() or public.is_controlador());

drop policy if exists prazo_pessoas_insert on public.prazo_pessoas;
create policy prazo_pessoas_insert on public.prazo_pessoas
  for insert with check (public.is_controlador());

drop policy if exists prazo_pessoas_delete on public.prazo_pessoas;
create policy prazo_pessoas_delete on public.prazo_pessoas
  for delete using (public.is_controlador());


-- ============================================================
-- 12b) GRANTS — privilégios de tabela para o role authenticated
--      RLS por si só não libera acesso: o Postgres exige GRANT
--      na tabela antes de avaliar as políticas de RLS.
-- ============================================================
grant usage on schema public to authenticated;

grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.invites to authenticated;
grant select, insert, delete on public.invite_obras to authenticated;
grant select, insert, delete on public.obra_access to authenticated;
grant select, insert, update, delete on public.obras to authenticated;
grant select, insert, update, delete on public.disciplinas to authenticated;
grant select, insert, update, delete on public.versoes to authenticated;
grant select, insert, update, delete on public.versao_feedback to authenticated;
grant select, insert, update, delete on public.disciplina_chat to authenticated;
grant select, insert, update, delete on public.atas to authenticated;
grant select, insert, delete on public.notif_dismissals to authenticated;
grant select, insert, delete on public.versao_arquivos to authenticated;
grant select, insert, update, delete on public.pdf_anotacoes to authenticated;
grant select, insert, update, delete on public.prazos to authenticated;
grant select, insert, delete on public.prazo_pessoas to authenticated;


-- ============================================================
-- 13) SEED — controlador inicial
-- ============================================================
insert into public.invites (email, nome, papel, cor, role, status)
values (
  'pedro@dibdib.com.br',
  'Pedro Dib',
  'Administrador',
  'linear-gradient(135deg,#324a63,#16202b)',
  'controlador',
  'active'
)
on conflict (email) do update
  set role = 'controlador', status = 'active';


-- ============================================================
-- 14) SEED — dados de exemplo (mesmas obras do protótipo)
--     Pode apagar este bloco se preferir começar vazio.
-- ============================================================
insert into public.obras (id, nome, local, cor, progresso, ordem) values
  ('a0000000-0000-0000-0000-000000000001', 'Perimetral',    'Rio de Janeiro · RJ', 'linear-gradient(135deg,#2f6bff,#16357a)', 62, 1),
  ('a0000000-0000-0000-0000-000000000002', 'Freire Alemão', 'Copacabana · RJ',     'linear-gradient(135deg,#c9a24b,#8a6a1f)', 38, 2)
on conflict (id) do nothing;

insert into public.disciplinas (id, obra_id, nome, status, aguardando, ordem) values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Arquitetura',   'review', 'Análise Dib & Dib',  1),
  ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Estrutural',    'wait',   'Meta Arquitetura',   2),
  ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Fachada',       'dev',    'Studio Fachadas',    3),
  ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Instalações',   'pend',   'A iniciar',          4),
  ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'Arquitetura',   'dev',    'Meta Arquitetura',   1),
  ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'Fachada',       'review', 'Análise Dib & Dib',  2),
  ('b0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'Paisagismo',    'pend',   'A iniciar',          3)
on conflict (id) do nothing;

-- versões (numero explícito para refletir a ordem cronológica v1..vN)
insert into public.versoes (id, disciplina_id, numero, titulo, data, autor_nome, status) values
  ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 1, 'Estudo preliminar aprovado',              '2026-05-02', 'Meta Arquitetura', 'ok'),
  ('c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 2, 'Compatibilização com estrutura',          '2026-05-21', 'Meta Arquitetura', 'ok'),
  ('c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 3, 'Projeto executivo — revisão de layout',   '2026-06-05', 'Meta Arquitetura', 'review'),
  ('c0000000-0000-0000-0000-000000000004', 'b0000000-0000-0000-0000-000000000002', 1, 'Pré-dimensionamento',                     '2026-05-10', 'Eng. Ricardo Sá',  'ok'),
  ('c0000000-0000-0000-0000-000000000005', 'b0000000-0000-0000-0000-000000000002', 2, 'Lançamento de pilares e vigas',           '2026-05-28', 'Eng. Ricardo Sá',  'wait'),
  ('c0000000-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-000000000003', 1, 'Conceito de fachada ventilada',           '2026-05-30', 'Studio Fachadas',  'dev'),
  ('c0000000-0000-0000-0000-000000000007', 'b0000000-0000-0000-0000-000000000005', 1, 'Estudo de implantação',                   '2026-05-18', 'Meta Arquitetura', 'ok'),
  ('c0000000-0000-0000-0000-000000000008', 'b0000000-0000-0000-0000-000000000005', 2, 'Plantas com ajustes do cliente',          '2026-06-03', 'Meta Arquitetura', 'dev'),
  ('c0000000-0000-0000-0000-000000000009', 'b0000000-0000-0000-0000-000000000006', 1, 'Proposta de revestimento em pedra',       '2026-05-31', 'Studio Fachadas',  'review')
on conflict (id) do nothing;

-- feedback por versão
insert into public.versao_feedback (versao_id, autor_nome, texto) values
  ('c0000000-0000-0000-0000-000000000003', 'Marina Dib', 'O recuo da torre ficou ótimo. Só confirmar se a vaga PNE atende a norma na garagem.'),
  ('c0000000-0000-0000-0000-000000000005', 'Pedro Dib',  'Precisa receber a arquitetura v4 antes de fechar o lançamento. Vamos cobrar a Meta.'),
  ('c0000000-0000-0000-0000-000000000009', 'Pedro Dib',  'Gostei da pedra, mas vamos avaliar custo x manutenção antes de aprovar.')
on conflict do nothing;

-- chat por disciplina
insert into public.disciplina_chat (disciplina_id, autor_nome, texto) values
  ('b0000000-0000-0000-0000-000000000001', 'Pedro Dib',       'Pessoal, a arquitetura v4 já está na pasta. Podem revisar?'),
  ('b0000000-0000-0000-0000-000000000001', 'Meta Arquitetura','Recebido! Ajustamos o hall conforme a última ata.'),
  ('b0000000-0000-0000-0000-000000000002', 'Eng. Ricardo Sá', 'Assim que aprovarem a arquitetura, fecho o lançamento estrutural.'),
  ('b0000000-0000-0000-0000-000000000005', 'Pedro Dib',       'Família aprovou o programa. Meta, pode tocar as plantas.'),
  ('b0000000-0000-0000-0000-000000000005', 'Meta Arquitetura','Perfeito, começamos hoje. Subo a v3 na sexta.')
on conflict do nothing;

-- atas
insert into public.atas (obra_id, data, titulo, resumo, cls) values
  ('a0000000-0000-0000-0000-000000000001', '2026-06-04', 'Reunião de compatibilização',     'Alinhado ajuste de prumadas hidráulicas e revisão do hall. Meta vai atualizar arquitetura até 09/06.', 'gold'),
  ('a0000000-0000-0000-0000-000000000001', '2026-05-20', 'Aprovação do estudo preliminar',  'Cliente aprovou implantação e volumetria. Liberado avanço para executivo.', 'green'),
  ('a0000000-0000-0000-0000-000000000002', '2026-06-02', 'Briefing com a família',          'Definido programa de necessidades: 4 suítes, home e área gourmet integrada. Meta inicia plantas.', '')
on conflict do nothing;
