-- LifeOS — configuração do Supabase (rode UMA vez: Supabase › SQL Editor › New query › colar › Run)
-- Cria a tabela de dados cifrados, o armazenamento de documentos e as regras de acesso
-- (cada usuário só enxerga e altera os PRÓPRIOS dados). O conteúdo chega já cifrado pelo app.

-- 1) Tabela: uma linha por coleção (eventos, finanças, treinos...) com o conteúdo cifrado.
create table if not exists public.lifeos_blobs (
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  key        text        not null,
  data       text        not null,
  device     text,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

create index if not exists lifeos_blobs_updated_idx on public.lifeos_blobs (user_id, updated_at);

-- Data de atualização definida pelo servidor (evita problemas com relógio do aparelho).
create or replace function public.lifeos_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;

drop trigger if exists lifeos_touch on public.lifeos_blobs;
create trigger lifeos_touch before insert or update on public.lifeos_blobs
  for each row execute function public.lifeos_touch();

-- 2) Segurança em nível de linha: só o dono acessa.
alter table public.lifeos_blobs enable row level security;

drop policy if exists "lifeos: dono lê" on public.lifeos_blobs;
drop policy if exists "lifeos: dono cria" on public.lifeos_blobs;
drop policy if exists "lifeos: dono altera" on public.lifeos_blobs;
drop policy if exists "lifeos: dono apaga" on public.lifeos_blobs;
create policy "lifeos: dono lê"     on public.lifeos_blobs for select to authenticated using (user_id = auth.uid());
create policy "lifeos: dono cria"   on public.lifeos_blobs for insert to authenticated with check (user_id = auth.uid());
create policy "lifeos: dono altera" on public.lifeos_blobs for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "lifeos: dono apaga"  on public.lifeos_blobs for delete to authenticated using (user_id = auth.uid());

-- 3) Documentos anexados (arquivos cifrados), privados, até 50 MB cada.
insert into storage.buckets (id, name, public, file_size_limit)
values ('lifeos', 'lifeos', false, 52428800)
on conflict (id) do nothing;

drop policy if exists "lifeos arquivos: dono lê" on storage.objects;
drop policy if exists "lifeos arquivos: dono cria" on storage.objects;
drop policy if exists "lifeos arquivos: dono altera" on storage.objects;
drop policy if exists "lifeos arquivos: dono apaga" on storage.objects;
create policy "lifeos arquivos: dono lê" on storage.objects for select to authenticated
  using (bucket_id = 'lifeos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "lifeos arquivos: dono cria" on storage.objects for insert to authenticated
  with check (bucket_id = 'lifeos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "lifeos arquivos: dono altera" on storage.objects for update to authenticated
  using (bucket_id = 'lifeos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'lifeos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "lifeos arquivos: dono apaga" on storage.objects for delete to authenticated
  using (bucket_id = 'lifeos' and (storage.foldername(name))[1] = auth.uid()::text);
