# JESS Store · Backend (Supabase self-hosted)

Backend para el prototipo **Jess Store**. La base de datos vive en el
schema `jess`, el frontend consume todo por PostgREST vía dos vistas y una
RPC en `public`.

## Estructura

```
backend/
├── 01_schema.sql        Tablas, checks, triggers, secuencia de order_number
├── 02_rls.sql           Row Level Security (bloquea anon sobre jess.*)
├── 03_public_api.sql    Vistas + RPC create_jess_order (anon las usa)
├── 04_seed.sql          Categoría Free Fire + 6 paquetes demo
├── supabase-config.js   Config del cliente (URL + anon key) — cargada por el HTML
├── .env.example         Variables para vos / para conectarte con psql
└── README.md
```

## 1. Correr los SQL

Con tu Supabase self-hosted arriba y `DATABASE_URL` copiada al `.env`:

```bash
cd backend
psql "$DATABASE_URL" -f 01_schema.sql
psql "$DATABASE_URL" -f 02_rls.sql
psql "$DATABASE_URL" -f 03_public_api.sql
psql "$DATABASE_URL" -f 04_seed.sql
```

O pegalos en orden en el **SQL Editor** de Supabase Studio.

> Los cuatro archivos son idempotentes: los podés volver a correr sin
> duplicar datos ni romper nada.

## 2. Exponer las vistas a PostgREST

Las vistas `public.jess_products_public` y `public.jess_categories_public`
ya viven en `public`, que PostgREST expone por defecto — **no hay que
tocar `db-schemas`**. Si preferís exponer también el schema `jess`,
agregalo así en `docker-compose.yml` (o `kong.yml` según tu setup):

```yaml
PGRST_DB_SCHEMAS: public,jess
```

Reiniciá `rest` (PostgREST) tras el cambio.

## 3. Configurar el frontend

Editá `backend/supabase-config.js`:

```js
window.JESS_SUPABASE = {
  url:     "http://localhost:8000",    // tu SUPABASE_URL
  anonKey: "eyJhbGciOi..."             // tu SUPABASE_ANON_KEY
};
```

El HTML (`../Jess Store.dc.html`) ya carga:

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script src="./backend/supabase-config.js"></script>
```

Si no configurás las claves, el frontend cae a un catálogo local
hardcodeado y guarda el pedido solo en localStorage — te avisa por
consola. Con las claves puestas, los productos se cargan desde
`jess.products` y el pedido se registra vía la RPC.

## 4. Servir el HTML en local

Desde la carpeta padre (donde vive `Jess Store.dc.html`):

```bash
cd "/Users/ivangonzalez/Proyectos/JESS/Prototipo interactivo con carrito"
python3 -m http.server 5173
```

Abrí <http://localhost:5173/Jess%20Store.dc.html>.

> Necesitás servirlo con un servidor HTTP (no `file://`) porque el HTML
> hace `fetch(...)` para leer el sidecar de imágenes y para llegar a
> Supabase.

## 5. Verificar

- `GET http://localhost:8000/rest/v1/jess_products_public?apikey=<ANON>`
  debe devolver los 6 paquetes.
- Hacé un pedido desde la web → mirá `select * from jess.orders order by created_at desc limit 5;`
  en Studio: debería aparecer con `order_number = JESS-000001` y los
  `order_items` correspondientes.

## Editar precios / paquetes

Todo desde `jess.products` en Studio (o UPDATE por SQL). El frontend los
recarga en cada refresh — no hace falta redeploy.

## Modelo de datos (resumen)

| Tabla                | Rol                                                          |
| -------------------- | ------------------------------------------------------------ |
| `jess.categories`    | Agrupa productos (por ahora solo "Free Fire").               |
| `jess.products`      | Paquetes de diamantes con precio, activo, orden y destacado. |
| `jess.customers`     | Se reutiliza por `phone` — si vuelve el mismo WhatsApp, actualiza. |
| `jess.orders`        | `order_number` autogenerado `JESS-000001` (secuencia + trigger). |
| `jess.order_items`   | Snapshot del producto al momento de comprar.                 |
| `jess.payments`      | Registro de pago (arranca `pending`, admin lo revisa).       |

## Flujo `create_jess_order`

1. Reusa cliente por teléfono (o lo crea).
2. Recalcula subtotal desde los ítems recibidos (no confía en el cliente).
3. Inserta `order` → trigger asigna `order_number`.
4. Inserta cada `order_item` con snapshot.
5. Inserta un `payment` en estado `pending` por el `total`.
6. Devuelve `{ order_id, order_number, subtotal, discount, total }`.

## Próximos pasos sugeridos

- Panel admin: usar `service_role` desde un backend (Next.js / Express) para
  listar pedidos, aprobar pagos y marcar `completed`.
- Storage: subir el comprobante a un bucket de Supabase y guardar la URL en
  `payments.receipt_url`.
- Notificaciones: webhook desde Postgres (`pg_net`) al hacer INSERT en
  `jess.orders` para avisar por WhatsApp/Telegram.
