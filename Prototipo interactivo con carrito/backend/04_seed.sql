-- =====================================================================
-- JESS STORE · Datos demo
--
-- Categoría "Free Fire" + los mismos 6 paquetes que trae el prototipo
-- (110 / 341 / 572 / 1166 / 2398 / 6160 diamantes, en guaraníes).
-- Los IDs son fijos → si volvés a correr el seed, ON CONFLICT actualiza
-- en vez de duplicar.
-- =====================================================================

insert into jess.categories (id, name, slug, description, sort_order, is_active)
values (
  '00000000-0000-0000-0000-000000000001',
  'Free Fire',
  'free-fire',
  'Recargas de diamantes para Garena Free Fire.',
  1,
  true
)
on conflict (id) do update set
  name         = excluded.name,
  slug         = excluded.slug,
  description  = excluded.description,
  sort_order   = excluded.sort_order,
  is_active    = excluded.is_active;

insert into jess.products
  (id, category_id, name, slug, diamonds, bonus_diamonds, price, is_featured, is_active, sort_order, description)
values
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001',
   '110 diamantes', 'ff-110',   100,   10,   9000, false, true, 10,
   '100 diamantes + 10 de bonus'),
  ('00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000001',
   '341 diamantes', 'ff-341',   310,   31,  25000, false, true, 20,
   '310 diamantes + 31 de bonus · OFERTA'),
  ('00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000001',
   '572 diamantes', 'ff-572',   520,   52,  38000, false, true, 30,
   '520 diamantes + 52 de bonus'),
  ('00000000-0000-0000-0000-000000000104', '00000000-0000-0000-0000-000000000001',
   '1.166 diamantes', 'ff-1166', 1060, 106,  70000,  true, true, 40,
   '1060 diamantes + 106 de bonus · MÁS POPULAR'),
  ('00000000-0000-0000-0000-000000000105', '00000000-0000-0000-0000-000000000001',
   '2.398 diamantes', 'ff-2398', 2180, 218, 131000, false, true, 50,
   '2180 diamantes + 218 de bonus'),
  ('00000000-0000-0000-0000-000000000106', '00000000-0000-0000-0000-000000000001',
   '6.160 diamantes', 'ff-6160', 5600, 560, 316000, false, true, 60,
   '5600 diamantes + 560 de bonus · MEJOR VALOR')
on conflict (id) do update set
  category_id     = excluded.category_id,
  name            = excluded.name,
  slug            = excluded.slug,
  diamonds        = excluded.diamonds,
  bonus_diamonds  = excluded.bonus_diamonds,
  price           = excluded.price,
  is_featured     = excluded.is_featured,
  is_active       = excluded.is_active,
  sort_order      = excluded.sort_order,
  description     = excluded.description;
