-- ============================================================
--  FORA DE FORMA DO MILHÃO — banco (Supabase).
--  Cole TUDO no SQL Editor → Run.  (Re-rodar é seguro: idempotente.)
-- ============================================================

-- PERFIS (cadastro — SEM aprovação: cadastrou, já usa) --------
create table if not exists perfis (
  id        uuid primary key references auth.users(id) on delete cascade,
  nome      text,
  email     text,
  aprovado  boolean not null default true,
  admin     boolean not null default false,
  criado_em timestamptz default now()
);
alter table perfis enable row level security;
alter table perfis alter column aprovado set default true;
update perfis set aprovado = true where aprovado is distinct from true;

-- JOGOS -------------------------------------------------------
create table if not exists jogos (
  id        bigint generated always as identity primary key,
  criado_em timestamptz default now(),
  user_id   uuid references auth.users(id) on delete cascade,
  nome      text,
  jogo      text not null,          -- 'mega' | 'lotofacil'
  data      date not null,          -- data do sorteio
  dezenas   text not null,          -- "01-05-12-..."
  qtd       int,
  score     int,
  aval      text,
  apostado  boolean not null default false   -- admin marca quando aposta de fato
);
alter table jogos enable row level security;
alter table jogos add column if not exists apostado boolean not null default false;

-- RODADAS (status do sorteio: apostas encerradas por jogo+data) -
create table if not exists rodadas (
  jogo         text not null,       -- 'mega' | 'lotofacil'
  data         date not null,       -- data do sorteio
  fechado      boolean not null default false,
  atualizado_em timestamptz default now(),
  primary key (jogo, data)
);
alter table rodadas enable row level security;

-- FUNÇÃO is_admin (security definer p/ não dar recursão de RLS) -
create or replace function is_admin() returns boolean
  language sql security definer stable set search_path=public as $$
  select coalesce((select admin from perfis where id = auth.uid()), false);
$$;

-- TRIGGER: cria perfil automático quando alguém se cadastra ----
create or replace function handle_new_user() returns trigger
  language plpgsql security definer set search_path=public as $$
begin
  insert into perfis (id, nome, email, aprovado)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome',''), new.email, true)
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- POLÍTICAS RLS ----------------------------------------------
-- perfis: cada um vê o seu; admin vê todos; só admin altera
drop policy if exists "perfis_select" on perfis;
create policy "perfis_select" on perfis for select
  using (id = auth.uid() or is_admin());
drop policy if exists "perfis_update_admin" on perfis;
create policy "perfis_update_admin" on perfis for update
  using (is_admin()) with check (is_admin());

-- jogos: insere se logado E a rodada NÃO estiver fechada (encerrar apostas)
drop policy if exists "jogos_insert" on jogos;
create policy "jogos_insert" on jogos for insert with check (
  user_id = auth.uid()
  and not exists (select 1 from rodadas r where r.jogo = jogos.jogo and r.data = jogos.data and r.fechado)
);
-- jogos: vê os seus (admin vê TODOS)
drop policy if exists "jogos_select" on jogos;
create policy "jogos_select" on jogos for select
  using (user_id = auth.uid() or is_admin());
-- jogos: só admin atualiza (marcar 'apostado')
drop policy if exists "jogos_update_admin" on jogos;
create policy "jogos_update_admin" on jogos for update
  using (is_admin()) with check (is_admin());
-- jogos: remove os seus (admin remove todos)
drop policy if exists "jogos_delete" on jogos;
create policy "jogos_delete" on jogos for delete
  using (user_id = auth.uid() or is_admin());

-- rodadas: todo logado lê (p/ ver "apostas encerradas"); só admin grava
drop policy if exists "rodadas_select" on rodadas;
create policy "rodadas_select" on rodadas for select
  using (auth.uid() is not null);
drop policy if exists "rodadas_write" on rodadas;
create policy "rodadas_write" on rodadas for all
  using (is_admin()) with check (is_admin());

-- ADMIN: garante você como organizador (troque o e-mail se preciso) --
update perfis set admin = true, aprovado = true where email = 'hhenriqk@gmail.com';

-- ============================================================
--  DIAGNÓSTICO:
-- ============================================================
select
  (select count(*) from perfis)            as total_perfis,
  (select count(*) from perfis where admin) as admins,
  (select count(*) from jogos)             as total_jogos,
  (select count(*) from jogos where apostado) as jogos_apostados,
  (select count(*) from rodadas where fechado) as rodadas_fechadas;
