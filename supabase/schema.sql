-- Swap backend for Supabase. This is the version already applied to the live project
-- as migration "swap_initial_schema". Run it once on any new project.
-- Safe to read top to bottom: tables, row level security, storage, moderation, account deletion.

------------------------------------------------------------------------------
-- Profiles (one per auth user, created automatically on sign up)
------------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null default '' check (char_length(name) <= 60),
  created_at timestamptz not null default now()
);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(left(new.raw_user_meta_data ->> 'name', 60), ''));
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

------------------------------------------------------------------------------
-- Core tables
------------------------------------------------------------------------------
create table public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  price numeric(10, 2) not null check (price >= 0),
  category text not null check (category in
    ('electronics', 'furniture', 'vehicles', 'clothing', 'home', 'sports', 'toys', 'other')),
  condition text not null check (condition in ('new', 'likeNew', 'good', 'fair')),
  details text not null default '' check (char_length(details) <= 4000),
  location_name text not null check (char_length(location_name) between 1 and 120),
  photo_urls text[] not null default '{}' check (cardinality(photo_urls) <= 6),
  is_sold boolean not null default false,
  created_at timestamptz not null default now()
);
create index listings_created_at_idx on public.listings (created_at desc);
create index listings_seller_idx on public.listings (seller_id);

create table public.favorites (
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

create index favorites_listing_idx on public.favorites (listing_id);

create table public.threads (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  buyer_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (listing_id, buyer_id),
  check (buyer_id <> seller_id)
);
create index threads_buyer_idx on public.threads (buyer_id);
create index threads_seller_idx on public.threads (seller_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.threads (id) on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index messages_thread_idx on public.messages (thread_id, created_at);
create index messages_sender_idx on public.messages (sender_id);

------------------------------------------------------------------------------
-- Moderation (App Store requires report and block for user generated content)
------------------------------------------------------------------------------
create table public.blocks (
  blocker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index blocks_blocked_idx on public.blocks (blocked_id);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  listing_id uuid references public.listings (id) on delete set null,
  reported_user_id uuid references public.profiles (id) on delete set null,
  reason text not null check (char_length(reason) between 1 and 200),
  created_at timestamptz not null default now(),
  check (listing_id is not null or reported_user_id is not null)
);

create index reports_reporter_idx on public.reports (reporter_id);
create index reports_listing_idx on public.reports (listing_id);
create index reports_reported_user_idx on public.reports (reported_user_id);

------------------------------------------------------------------------------
-- Row level security
------------------------------------------------------------------------------
alter table public.profiles  enable row level security;
alter table public.listings  enable row level security;
alter table public.favorites enable row level security;
alter table public.threads   enable row level security;
alter table public.messages  enable row level security;
alter table public.blocks    enable row level security;
alter table public.reports   enable row level security;

-- Profiles: names are public (shown on listings). You can only edit your own.
create policy "profiles are readable" on public.profiles
  for select to anon, authenticated using (true);
create policy "edit own profile" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Listings: anyone can browse, except sellers you blocked. Only the seller writes.
create policy "browse listings" on public.listings
  for select to anon, authenticated
  using (not exists (
    select 1 from public.blocks b
    where b.blocker_id = (select auth.uid()) and b.blocked_id = listings.seller_id));
create policy "post own listings" on public.listings
  for insert to authenticated with check (seller_id = (select auth.uid()));
create policy "edit own listings" on public.listings
  for update to authenticated using (seller_id = (select auth.uid())) with check (seller_id = (select auth.uid()));
create policy "delete own listings" on public.listings
  for delete to authenticated using (seller_id = (select auth.uid()));

-- Favorites: private to you.
create policy "own favorites" on public.favorites
  for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Threads: only the buyer and the seller can see them. A buyer starts a thread
-- with the real seller of the listing.
create policy "see own threads" on public.threads
  for select to authenticated using ((select auth.uid()) in (buyer_id, seller_id));
create policy "start thread as buyer" on public.threads
  for insert to authenticated
  with check (
    buyer_id = (select auth.uid())
    and seller_id = (select l.seller_id from public.listings l where l.id = listing_id));

-- Messages: only participants can read or send, and only as themselves.
create policy "read messages in my threads" on public.messages
  for select to authenticated
  using (exists (
    select 1 from public.threads t
    where t.id = messages.thread_id and (select auth.uid()) in (t.buyer_id, t.seller_id)));
create policy "send messages in my threads" on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.threads t
      where t.id = messages.thread_id and (select auth.uid()) in (t.buyer_id, t.seller_id)));

-- Blocks: private to you.
create policy "own blocks" on public.blocks
  for all to authenticated using (blocker_id = (select auth.uid())) with check (blocker_id = (select auth.uid()));

-- Reports: you can file them, nobody can read them through the app API.
-- Review them in the Supabase dashboard (Table editor, reports).
create policy "file reports" on public.reports
  for insert to authenticated with check (reporter_id = (select auth.uid()));

------------------------------------------------------------------------------
-- Photo storage: public read, you can only write inside your own folder
------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', true, 5242880,
        array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

create policy "upload to own folder" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "delete from own folder" on storage.objects
  for delete to authenticated
  using (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

------------------------------------------------------------------------------
-- In-app account deletion (App Store requires it)
------------------------------------------------------------------------------
create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();  -- cascades to everything above
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
