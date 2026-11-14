-- TakasYeri: herkesin gördüğü ortak ilan tablosu
-- Supabase > SQL Editor > New query > bunu yapıştır > Run

create table if not exists public.trades (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  roblox_name text not null,
  game        text not null check (char_length(game) between 1 and 40),
  contact     text not null check (char_length(contact) between 1 and 40),
  have        jsonb not null check (jsonb_typeof(have) = 'array' and jsonb_array_length(have) between 1 and 30),
  want        jsonb not null check (jsonb_typeof(want) = 'array' and jsonb_array_length(want) between 1 and 30),
  boost       boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists trades_created_idx on public.trades (created_at desc);

-- Güvenlik (Row Level Security)
alter table public.trades enable row level security;

-- Giriş yapan herkes ilanları görebilir
create policy "giris yapanlar ilanlari gorur"
  on public.trades for select to authenticated
  using (true);

-- Herkes sadece kendi adına ilan ekleyebilir
create policy "kendi ilanini ekler"
  on public.trades for insert to authenticated
  with check (user_id = auth.uid());

-- Herkes sadece kendi ilanını silebilir
create policy "kendi ilanini siler"
  on public.trades for delete to authenticated
  using (user_id = auth.uid());

-- (UPDATE izni bilerek yok: kimse ilanı düzenleyip kendini "öne çıkan" yapamaz)

-- İlan eklenirken Roblox adı sunucuda profilden alınır; kimse başkası adına ilan veremez.
create or replace function public.trades_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name  text;
  v_count int;
begin
  select roblox_name into v_name from public.profiles where user_id = auth.uid();
  if v_name is null then
    raise exception 'Roblox hesabı doğrulanmamış';
  end if;

  select count(*) into v_count
  from public.trades
  where user_id = auth.uid() and created_at > now() - interval '72 hours';
  if v_count >= 10 then
    raise exception 'ilan limiti: en fazla 10 aktif ilan verebilirsin';
  end if;

  new.user_id     := auth.uid();
  new.roblox_name := v_name;
  new.boost       := false;
  new.created_at  := now();
  return new;
end;
$$;

drop trigger if exists trades_before_insert on public.trades;
create trigger trades_before_insert
  before insert on public.trades
  for each row execute function public.trades_before_insert();

-- İSTEĞE BAĞLI: 7 günden eski ilanları temizlemek için (elle çalıştırabilirsin)
-- delete from public.trades where created_at < now() - interval '7 days';
