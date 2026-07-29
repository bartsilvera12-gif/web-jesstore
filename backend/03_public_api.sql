-- =====================================================================
-- JESS STORE · API pública (vistas + RPC en schema `public`)
--
-- El frontend consume solo esto (vía PostgREST/supabase-js).
-- Las funciones son SECURITY DEFINER: escriben en `jess.*` con los
-- permisos del owner, esquivando RLS de forma controlada.
--
-- Asegurate de que este script sea ejecutado por un rol dueño del schema
-- `jess` (por ejemplo, `postgres` en Supabase self-hosted).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Vista: catálogo público (solo productos + categoría activos)
-- ---------------------------------------------------------------------
create or replace view public.jess_products_public as
select
  p.id,
  p.name,
  p.slug,
  p.description,
  p.diamonds,
  p.bonus_diamonds,
  p.price,
  p.image_url,
  p.is_featured,
  p.sort_order,
  c.id   as category_id,
  c.slug as category_slug,
  c.name as category_name
from jess.products p
join jess.categories c on c.id = p.category_id
where p.is_active = true
  and c.is_active = true
order by p.sort_order asc, p.price asc;

grant select on public.jess_products_public to anon, authenticated;

-- ---------------------------------------------------------------------
-- Vista: categorías activas
-- ---------------------------------------------------------------------
create or replace view public.jess_categories_public as
select id, name, slug, description, image_url, sort_order
from jess.categories
where is_active = true
order by sort_order asc, name asc;

grant select on public.jess_categories_public to anon, authenticated;

-- ---------------------------------------------------------------------
-- RPC: crear pedido completo (customer + order + items + payment)
--
-- Recibe un JSON con toda la info del checkout y devuelve
--   { order_id, order_number, total }.
--
-- Ejemplo de payload esperado:
-- {
--   "customer": { "name": "...", "phone": "+595...", "email": null },
--   "player_id": "1234567890",
--   "player_nickname": null,
--   "payment_method": "Transferencia Bancaria",
--   "discount": 0,
--   "notes": null,
--   "items": [
--     { "product_id": "uuid|null",   -- null para paquete personalizado
--       "product_name": "1.166 diamantes",
--       "diamonds": 1166,
--       "bonus_diamonds": 0,
--       "quantity": 1,
--       "unit_price": 70000 }
--   ]
-- }
-- ---------------------------------------------------------------------
create or replace function public.create_jess_order(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = jess, public, pg_temp
as $$
declare
  v_customer_id   uuid;
  v_order_id      uuid;
  v_order_number  text;
  v_subtotal      numeric(14,2) := 0;
  v_discount      numeric(14,2) := coalesce((payload->>'discount')::numeric, 0);
  v_total         numeric(14,2) := 0;
  v_item          jsonb;
  v_item_subtotal numeric(14,2);
  v_customer      jsonb := payload->'customer';
  v_items         jsonb := payload->'items';
begin
  ------------------------------------------------------------------
  -- Validaciones mínimas
  ------------------------------------------------------------------
  if v_customer is null or coalesce(v_customer->>'name','') = '' or coalesce(v_customer->>'phone','') = '' then
    raise exception 'customer.name y customer.phone son obligatorios';
  end if;

  if payload->>'player_id' is null or payload->>'player_id' = '' then
    raise exception 'player_id es obligatorio';
  end if;

  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise exception 'El pedido debe tener al menos un ítem';
  end if;

  ------------------------------------------------------------------
  -- Reutilizar cliente por teléfono si ya existe, si no crearlo
  ------------------------------------------------------------------
  select id into v_customer_id
  from jess.customers
  where phone = v_customer->>'phone'
  limit 1;

  if v_customer_id is null then
    insert into jess.customers (name, phone, email)
    values (
      v_customer->>'name',
      v_customer->>'phone',
      nullif(v_customer->>'email','')
    )
    returning id into v_customer_id;
  else
    update jess.customers
       set name  = v_customer->>'name',
           email = coalesce(nullif(v_customer->>'email',''), email)
     where id = v_customer_id;
  end if;

  ------------------------------------------------------------------
  -- Calcular subtotal (autoritativo del backend, no confiamos en el cliente)
  ------------------------------------------------------------------
  for v_item in select * from jsonb_array_elements(v_items) loop
    v_subtotal := v_subtotal
      + coalesce((v_item->>'quantity')::int, 1)
      * coalesce((v_item->>'unit_price')::numeric, 0);
  end loop;

  v_total := v_subtotal - v_discount;
  if v_total < 0 then
    raise exception 'El descuento no puede superar al subtotal';
  end if;

  ------------------------------------------------------------------
  -- Crear pedido
  ------------------------------------------------------------------
  insert into jess.orders (
    customer_id, player_id, player_nickname,
    status, payment_status, payment_method,
    subtotal, discount, total, notes
  ) values (
    v_customer_id,
    payload->>'player_id',
    nullif(payload->>'player_nickname',''),
    'pending',
    'pending',
    nullif(payload->>'payment_method',''),
    v_subtotal, v_discount, v_total,
    nullif(payload->>'notes','')
  )
  returning id, order_number into v_order_id, v_order_number;

  ------------------------------------------------------------------
  -- Ítems (snapshot del producto)
  ------------------------------------------------------------------
  for v_item in select * from jsonb_array_elements(v_items) loop
    v_item_subtotal :=
        coalesce((v_item->>'quantity')::int, 1)
      * coalesce((v_item->>'unit_price')::numeric, 0);

    insert into jess.order_items (
      order_id, product_id, product_name,
      diamonds, bonus_diamonds, quantity, unit_price, subtotal
    ) values (
      v_order_id,
      nullif(v_item->>'product_id','')::uuid,
      v_item->>'product_name',
      (v_item->>'diamonds')::int,
      coalesce((v_item->>'bonus_diamonds')::int, 0),
      coalesce((v_item->>'quantity')::int, 1),
      coalesce((v_item->>'unit_price')::numeric, 0),
      v_item_subtotal
    );
  end loop;

  ------------------------------------------------------------------
  -- Registro de pago inicial (pendiente)
  ------------------------------------------------------------------
  insert into jess.payments (order_id, method, amount, status)
  values (
    v_order_id,
    coalesce(nullif(payload->>'payment_method',''), 'Sin especificar'),
    v_total,
    'pending'
  );

  return jsonb_build_object(
    'order_id',     v_order_id,
    'order_number', v_order_number,
    'subtotal',     v_subtotal,
    'discount',     v_discount,
    'total',        v_total
  );
end;
$$;

revoke all on function public.create_jess_order(jsonb) from public;
grant execute on function public.create_jess_order(jsonb) to anon, authenticated;
