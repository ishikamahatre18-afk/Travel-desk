-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.
-- Stores ONLY encrypted data. Each login can see and change only its own row.

create table if not exists public.vaults (
  user_id uuid primary key references auth.users (id) on delete cascade,
  kdf_salt text not null,
  wrapped_dek_pw text not null,
  recovery_salt text not null,
  wrapped_dek_recovery text not null,
  data_blob text not null default '' check (length(data_blob) < 5000000),
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table public.vaults enable row level security;

drop policy if exists "vault_select_own" on public.vaults;
drop policy if exists "vault_insert_own" on public.vaults;
drop policy if exists "vault_update_own" on public.vaults;

create policy "vault_select_own" on public.vaults
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "vault_insert_own" on public.vaults
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "vault_update_own" on public.vaults
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- No delete policy on purpose: a vault cannot be deleted from the app.
