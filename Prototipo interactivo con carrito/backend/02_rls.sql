-- =====================================================================
-- JESS STORE · Row Level Security
--
-- Estrategia:
--  * Todas las tablas del schema `jess` con RLS activado.
--  * No damos acceso directo a `anon` sobre las tablas → el frontend
--    consume TODO a través de las vistas y la RPC del schema `public`
--    (ver 03_public_api.sql). Ese archivo hace GRANT EXECUTE al anon.
--  * `authenticated` (panel admin en el futuro) tiene acceso total.
--
-- Requiere que en Supabase self-hosted el schema `public` esté expuesto
-- vía PostgREST (por defecto lo está).
-- =====================================================================

alter table jess.categories  enable row level security;
alter table jess.products    enable row level security;
alter table jess.customers   enable row level security;
alter table jess.orders      enable row level security;
alter table jess.order_items enable row level security;
alter table jess.payments    enable row level security;

-- Limpiar políticas previas (idempotencia)
drop policy if exists p_categories_read_auth   on jess.categories;
drop policy if exists p_categories_write_auth  on jess.categories;
drop policy if exists p_products_read_auth     on jess.products;
drop policy if exists p_products_write_auth    on jess.products;
drop policy if exists p_customers_all_auth     on jess.customers;
drop policy if exists p_orders_all_auth        on jess.orders;
drop policy if exists p_order_items_all_auth   on jess.order_items;
drop policy if exists p_payments_all_auth      on jess.payments;

-- Usuarios autenticados (admin) → acceso total
create policy p_categories_read_auth  on jess.categories
  for select to authenticated using (true);
create policy p_categories_write_auth on jess.categories
  for all to authenticated using (true) with check (true);

create policy p_products_read_auth    on jess.products
  for select to authenticated using (true);
create policy p_products_write_auth   on jess.products
  for all to authenticated using (true) with check (true);

create policy p_customers_all_auth    on jess.customers
  for all to authenticated using (true) with check (true);

create policy p_orders_all_auth       on jess.orders
  for all to authenticated using (true) with check (true);

create policy p_order_items_all_auth  on jess.order_items
  for all to authenticated using (true) with check (true);

create policy p_payments_all_auth     on jess.payments
  for all to authenticated using (true) with check (true);

-- Nota: el rol `anon` no tiene ninguna política sobre `jess.*`, por lo que
-- RLS lo bloquea. Todo su tráfico pasa por las funciones SECURITY DEFINER
-- del schema `public` definidas en 03_public_api.sql.
