-- Phase 1: foundation (roles, customers, KYC, products, MRP, discounts, audit log)
-- Run in the Supabase SQL editor, or with `supabase db push`.

create extension if not exists pgcrypto;

-- ---------- Enums ----------
create type public.app_role as enum ('admin', 'manager', 'driver', 'customer');
create type public.customer_segment as enum ('domestic', 'commercial');
create type public.gst_type as enum ('gst', 'non_gst');
create type public.connection_type as enum ('single', 'double');
create type public.cylinder_type as enum ('VOT', 'LOT');

-- ---------- Helpers ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------- Profiles (one per auth user) ----------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.app_role not null,
  full_name text not null,
  mobile text not null unique check (mobile ~ '^[0-9]{10}$'),
  active boolean not null default true,
  must_change_password boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

-- Role lookup used by every policy. SECURITY DEFINER avoids policy recursion.
create or replace function public.current_app_role()
returns public.app_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.current_app_role() in ('admin', 'manager'), false)
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.current_app_role() = 'admin', false)
$$;

-- ---------- Customers (non-sensitive) ----------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles (id) on delete set null,
  segment public.customer_segment not null,
  gst_type public.gst_type,                       -- commercial only
  name text not null,
  trade_name text,
  mobile text not null check (mobile ~ '^[0-9]{10}$'),
  whatsapp_number text check (whatsapp_number ~ '^[0-9]{10}$'),
  consumer_number text,                            -- domestic LPG consumer number
  delivery_address text,
  location_url text,                               -- Google Maps pin
  connection_type public.connection_type,          -- domestic: single = 1 cylinder, double = 2
  default_pack_kg int check (default_pack_kg in (4, 8, 12)),
  active boolean not null default true,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gst_type_only_commercial check (segment = 'commercial' or gst_type is null)
);
create unique index customers_mobile_segment_idx on public.customers (mobile, segment);
create index customers_name_idx on public.customers (lower(name) text_pattern_ops);
create trigger customers_updated before update on public.customers
  for each row execute function public.set_updated_at();

-- ---------- Customer KYC (sensitive: Aadhaar, GSTIN, ID proofs). Staff only. ----------
create table public.customer_kyc (
  customer_id uuid primary key references public.customers (id) on delete cascade,
  aadhaar_number text check (aadhaar_number ~ '^[0-9]{12}$'),
  aadhaar_address text,
  gstin text check (gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'),
  legal_name text,
  billing_address text,
  id_proof_type text check (id_proof_type in (
    'aadhaar', 'pan', 'voter_id', 'driving_licence',
    'shop_establishment', 'food_licence', 'electricity_bill')),
  id_proof_number text,
  updated_at timestamptz not null default now()
);
create trigger customer_kyc_updated before update on public.customer_kyc
  for each row execute function public.set_updated_at();

-- ---------- Scanned documents (files live in the private storage bucket) ----------
create table public.customer_documents (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  doc_type text not null check (doc_type in (
    'aadhaar_front', 'aadhaar_back', 'gst_certificate', 'pan', 'voter_id',
    'driving_licence', 'shop_establishment', 'food_licence', 'electricity_bill', 'other')),
  storage_path text not null unique,
  uploaded_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index customer_documents_customer_idx on public.customer_documents (customer_id);

-- ---------- Products ----------
create table public.products (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  segment public.customer_segment not null,
  kg int not null,
  cylinder_type public.cylinder_type,              -- only for 33 kg commercial
  active boolean not null default true,
  sort_order int not null default 0
);

insert into public.products (code, name, segment, kg, cylinder_type, sort_order) values
  ('D4',    '4 kg Domestic',         'domestic',   4,  null,  1),
  ('D8',    '8 kg Domestic',         'domestic',   8,  null,  2),
  ('D12',   '12 kg Domestic',        'domestic',   12, null,  3),
  ('C17',   '17 kg Commercial',      'commercial', 17, null,  4),
  ('C21',   '21 kg Commercial',      'commercial', 21, null,  5),
  ('C33V',  '33 kg Commercial VOT',  'commercial', 33, 'VOT', 6),
  ('C33L',  '33 kg Commercial LOT',  'commercial', 33, 'LOT', 7);

-- ---------- MRP (effective-dated; admin only; same for all customers) ----------
create table public.mrp_prices (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id),
  mrp numeric(10, 2) not null check (mrp > 0),
  effective_from timestamptz not null default now(),
  set_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index mrp_prices_lookup_idx on public.mrp_prices (product_id, effective_from desc);

create view public.current_mrp with (security_invoker = true) as
  select distinct on (product_id) product_id, mrp, effective_from
  from public.mrp_prices
  where effective_from <= now()
  order by product_id, effective_from desc;

-- ---------- Per-customer discount (commercial; admin only) ----------
-- Discounted price = current MRP - discount_per_cylinder.
create table public.customer_discounts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  product_id uuid not null references public.products (id),
  discount_per_cylinder numeric(10, 2) not null check (discount_per_cylinder >= 0),
  effective_from timestamptz not null default now(),
  set_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index customer_discounts_lookup_idx
  on public.customer_discounts (customer_id, product_id, effective_from desc);

-- ---------- Audit log ----------
create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  table_name text not null,
  row_id text,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  at timestamptz not null default now()
);
create index audit_log_table_idx on public.audit_log (table_name, at desc);

create or replace function public.audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  rid text;
begin
  rid := coalesce(
    (to_jsonb(coalesce(new, old)) ->> 'id'),
    (to_jsonb(coalesce(new, old)) ->> 'customer_id'));
  insert into public.audit_log (actor_id, table_name, row_id, action, old_data, new_data)
  values (
    auth.uid(), tg_table_name, rid, tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create trigger audit_customers after insert or update or delete on public.customers
  for each row execute function public.audit_row();
create trigger audit_customer_kyc after insert or update or delete on public.customer_kyc
  for each row execute function public.audit_row();
create trigger audit_mrp after insert or update or delete on public.mrp_prices
  for each row execute function public.audit_row();
create trigger audit_discounts after insert or update or delete on public.customer_discounts
  for each row execute function public.audit_row();
create trigger audit_profiles after insert or update or delete on public.profiles
  for each row execute function public.audit_row();

-- ---------- Row-level security ----------
alter table public.profiles            enable row level security;
alter table public.customers           enable row level security;
alter table public.customer_kyc        enable row level security;
alter table public.customer_documents  enable row level security;
alter table public.products            enable row level security;
alter table public.mrp_prices          enable row level security;
alter table public.customer_discounts  enable row level security;
alter table public.audit_log           enable row level security;

-- profiles
create policy profiles_self_read on public.profiles
  for select using (id = auth.uid());
create policy profiles_staff_read on public.profiles
  for select using (public.is_staff());
create policy profiles_admin_write on public.profiles
  for all using (public.is_admin()) with check (public.is_admin());

-- customers: staff full access, driver read, customer reads own row.
-- Customers edit their own delivery address / location through a server action
-- (service role) that updates only those two columns.
create policy customers_staff_all on public.customers
  for all using (public.is_staff()) with check (public.is_staff());
create policy customers_driver_read on public.customers
  for select using (public.current_app_role() = 'driver');
create policy customers_self_read on public.customers
  for select using (profile_id = auth.uid());

-- KYC and documents: staff only (no driver, no customer)
create policy kyc_staff_all on public.customer_kyc
  for all using (public.is_staff()) with check (public.is_staff());
create policy documents_staff_all on public.customer_documents
  for all using (public.is_staff()) with check (public.is_staff());

-- products: every signed-in user reads; admin writes
create policy products_read on public.products
  for select using (auth.uid() is not null);
create policy products_admin_write on public.products
  for all using (public.is_admin()) with check (public.is_admin());

-- MRP: every signed-in user reads; admin inserts (history is never edited)
create policy mrp_read on public.mrp_prices
  for select using (auth.uid() is not null);
create policy mrp_admin_insert on public.mrp_prices
  for insert with check (public.is_admin());

-- discounts: staff read, customer reads own, admin writes
create policy discounts_staff_read on public.customer_discounts
  for select using (public.is_staff());
create policy discounts_self_read on public.customer_discounts
  for select using (exists (
    select 1 from public.customers c
    where c.id = customer_id and c.profile_id = auth.uid()));
create policy discounts_admin_insert on public.customer_discounts
  for insert with check (public.is_admin());

-- audit log: admin reads; rows are written only by the trigger
create policy audit_admin_read on public.audit_log
  for select using (public.is_admin());

-- ---------- Private storage bucket for scans ----------
insert into storage.buckets (id, name, public)
values ('customer-documents', 'customer-documents', false)
on conflict (id) do nothing;

create policy documents_bucket_staff_select on storage.objects
  for select using (bucket_id = 'customer-documents' and public.is_staff());
create policy documents_bucket_staff_insert on storage.objects
  for insert with check (bucket_id = 'customer-documents' and public.is_staff());
create policy documents_bucket_admin_delete on storage.objects
  for delete using (bucket_id = 'customer-documents' and public.is_admin());
