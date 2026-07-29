-- =====================================================================
-- JESS STORE · Esquema de base de datos
-- Supabase self-hosted (PostgreSQL 15+)
--
-- Orden de ejecución:
--   1) 01_schema.sql   (este archivo)
--   2) 02_rls.sql
--   3) 03_public_api.sql
--   4) 04_seed.sql
-- =====================================================================

create schema if not exists jess;

create extension if not exists pgcrypto;   -- gen_random_uuid()

-- ---------------------------------------------------------------------
-- Helper: mantener updated_at al día
-- ---------------------------------------------------------------------
create or replace function jess.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Categorías
-- ---------------------------------------------------------------------
create table if not exists jess.categories (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  slug         text not null unique,
  description  text,
  image_url    text,
  is_active    boolean not null default true,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

drop trigger if exists tg_categories_updated_at on jess.categories;
create trigger tg_categories_updated_at
before update on jess.categories
for each row execute function jess.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Productos
-- ---------------------------------------------------------------------
create table if not exists jess.products (
  id              uuid primary key default gen_random_uuid(),
  category_id     uuid not null references jess.categories(id),
  name            text not null,
  slug            text not null unique,
  description     text,
  diamonds        integer not null,
  bonus_diamonds  integer not null default 0,
  price           numeric(14,2) not null,
  image_url       text,
  is_featured     boolean not null default false,
  is_active       boolean not null default true,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint products_diamonds_positive       check (diamonds > 0),
  constraint products_bonus_nonneg            check (bonus_diamonds >= 0),
  constraint products_price_nonneg            check (price >= 0)
);

create index if not exists ix_products_category on jess.products(category_id);
create index if not exists ix_products_active   on jess.products(is_active) where is_active;

drop trigger if exists tg_products_updated_at on jess.products;
create trigger tg_products_updated_at
before update on jess.products
for each row execute function jess.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Clientes
-- ---------------------------------------------------------------------
create table if not exists jess.customers (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  phone       text not null,
  email       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists ix_customers_phone on jess.customers(phone);
create index if not exists ix_customers_email on jess.customers(email);

drop trigger if exists tg_customers_updated_at on jess.customers;
create trigger tg_customers_updated_at
before update on jess.customers
for each row execute function jess.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Pedidos
--   * status         : pending | payment_review | paid | processing | completed | cancelled | rejected
--   * payment_status : pending | under_review | approved | rejected | refunded
--   * order_number   : JESS-000001 (secuencia + trigger, seguro ante concurrencia)
-- ---------------------------------------------------------------------
create sequence if not exists jess.orders_number_seq start with 1;

create table if not exists jess.orders (
  id                uuid primary key default gen_random_uuid(),
  order_number      text not null unique,
  customer_id       uuid not null references jess.customers(id),
  player_id         text not null,
  player_nickname   text,
  status            text not null default 'pending',
  payment_status    text not null default 'pending',
  payment_method    text,
  subtotal          numeric(14,2) not null default 0,
  discount          numeric(14,2) not null default 0,
  total             numeric(14,2) not null default 0,
  receipt_url       text,
  notes             text,
  completed_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint orders_status_valid check (status in
      ('pending','payment_review','paid','processing','completed','cancelled','rejected')),
  constraint orders_payment_status_valid check (payment_status in
      ('pending','under_review','approved','rejected','refunded')),
  constraint orders_amounts_nonneg check (subtotal >= 0 and discount >= 0 and total >= 0),
  constraint orders_total_matches  check (total = subtotal - discount)
);

create index if not exists ix_orders_customer   on jess.orders(customer_id);
create index if not exists ix_orders_status     on jess.orders(status);
create index if not exists ix_orders_created_at on jess.orders(created_at desc);

drop trigger if exists tg_orders_updated_at on jess.orders;
create trigger tg_orders_updated_at
before update on jess.orders
for each row execute function jess.tg_set_updated_at();

-- Trigger: si no viene order_number, generarlo desde la secuencia.
-- nextval() sobre una sequence es atómico → seguro con inserts concurrentes.
create or replace function jess.tg_orders_number()
returns trigger
language plpgsql
as $$
begin
  if new.order_number is null or new.order_number = '' then
    new.order_number := 'JESS-' || lpad(nextval('jess.orders_number_seq')::text, 6, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists tg_orders_number on jess.orders;
create trigger tg_orders_number
before insert on jess.orders
for each row execute function jess.tg_orders_number();

-- ---------------------------------------------------------------------
-- Ítems del pedido (snapshot del producto)
-- ---------------------------------------------------------------------
create table if not exists jess.order_items (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references jess.orders(id) on delete cascade,
  product_id      uuid references jess.products(id),
  product_name    text not null,
  diamonds        integer not null,
  bonus_diamonds  integer not null default 0,
  quantity        integer not null default 1,
  unit_price      numeric(14,2) not null,
  subtotal        numeric(14,2) not null,
  created_at      timestamptz not null default now(),
  constraint order_items_qty_positive     check (quantity > 0),
  constraint order_items_diamonds_positive check (diamonds > 0),
  constraint order_items_unit_price_nonneg check (unit_price >= 0),
  constraint order_items_subtotal_matches  check (subtotal = quantity * unit_price)
);

create index if not exists ix_order_items_order   on jess.order_items(order_id);
create index if not exists ix_order_items_product on jess.order_items(product_id);

-- ---------------------------------------------------------------------
-- Pagos
-- ---------------------------------------------------------------------
create table if not exists jess.payments (
  id                     uuid primary key default gen_random_uuid(),
  order_id               uuid not null references jess.orders(id) on delete cascade,
  method                 text not null,
  amount                 numeric(14,2) not null,
  status                 text not null default 'pending',
  transaction_reference  text,
  receipt_url            text,
  paid_at                timestamptz,
  reviewed_at            timestamptz,
  reviewed_by            uuid references auth.users(id),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint payments_status_valid check (status in
      ('pending','under_review','approved','rejected','refunded')),
  constraint payments_amount_nonneg check (amount >= 0)
);

create index if not exists ix_payments_order on jess.payments(order_id);

drop trigger if exists tg_payments_updated_at on jess.payments;
create trigger tg_payments_updated_at
before update on jess.payments
for each row execute function jess.tg_set_updated_at();
