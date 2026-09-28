# Wasla — Restaurant Template API Contract

> Everything a UI developer needs to build the restaurant experience **without
> any backend source code**. This is the HTTP interface only: base URL, auth,
> endpoints, request bodies, response JSON, and error codes.
>
> Base URL (example): `http://<host>:8000/api/v1`
> All requests/responses are JSON. Send `Accept: application/json`.
> Language: send `Accept-Language: ar` or `en`; server-localized text follows it.

---

## 1. Authentication

Wasla uses bearer tokens (Laravel Sanctum).

- Send `Authorization: Bearer <token>` on every authenticated request.
- **Customer** endpoints require a customer token (OTP login flow).
- **Merchant** endpoints require a merchant-owner/staff token and an **approved** merchant.

A token is returned by the login/register responses (field `token`).

Roles and access:
| Area | Who |
|---|---|
| Storefront (menu) | public — no token needed |
| Customer orders | customer token |
| Merchant menu + orders | merchant_owner / merchant_staff token, merchant approved |

---

## 2. Storefront — read the menu (public)

### `GET /stores/{token}`
Returns the whole storefront. For a **restaurant** store, `store.type == "restaurant"`
and a `menu` object is present. (Beauty stores omit `menu` and carry `services` instead.)

Response (restaurant, trimmed to menu-relevant fields):
```json
{
  "store": {
    "token": "QJ6VJFYN",
    "name": "برجر بلد",
    "type": "restaurant",
    "logo": "stores/3/logo-xxxx.jpg",
    "cover": "stores/3/cover-xxxx.jpg",
    "brand_color": "#111111",
    "currency": "SAR",
    "timezone": "Asia/Riyadh"
  },
  "configuration": {
    "order_pickup": true,
    "order_dine_in": true,
    "auto_accept_orders": false,
    "default_prep_minutes": 20,
    "customer_notes": true
  },
  "flow": [
    { "step": "menu" }, { "step": "cart" },
    { "step": "payment", "mode": "pay_at_store" }, { "step": "confirm" }
  ],
  "menu": {
    "categories": [
      {
        "id": 1,
        "name": "البرجر",
        "image": "stores/3/menu/cat-xxxx.jpg",
        "items": [ /* MenuItem[] — see below */ ]
      }
    ],
    "uncategorised": [ /* MenuItem[] */ ]
  }
}
```

**MenuItem** shape (also the item objects inside categories):
```json
{
  "id": 12,
  "name": "بيج تيستي",
  "description": "برجر لحم مع صوص خاص",
  "image": "stores/3/menu/xxxx.jpg",
  "price": 32.0,
  "calories": 850,
  "category_id": 1,
  "is_available": true,
  "is_featured": true,
  "option_groups": [
    {
      "id": 10,
      "name": "الحجم",
      "min_select": 1,
      "max_select": 1,
      "required": true,
      "options": [
        { "id": 100, "name": "وسط", "price_delta": 0.0,  "is_available": true },
        { "id": 101, "name": "كبير", "price_delta": 5.0, "is_available": true }
      ]
    }
  ]
}
```

**Rendering rules the UI must honour**
- `is_featured` items → the "الأكثر مبيعاً" section.
- `is_available == false` → show the dish dimmed / "نفد", not orderable.
- Image paths are relative to the site root: full URL = `<origin>/storage/<path>`
  (origin = base URL without `/api/v1`).
- Option groups:
  - `max_select == 1` → single choice (radios).
  - `min_select >= 1` → required (must pick before adding to cart).
  - `min_select == 0` → optional; cap picks at `max_select`.
- **Price is display-only.** Unit price = item `price` + sum of selected
  `price_delta`. The server recomputes the authoritative total at order time.

---

## 3. Customer — place & track orders (customer token)

### `POST /orders` — place an order
The client sends **intents only** (ids + quantities). The server prices and
validates everything.

Request:
```json
{
  "store_token": "QJ6VJFYN",
  "fulfillment_type": "pickup",          // "pickup" | "dine_in"
  "table_number": "12",                   // only for dine_in, optional
  "notes": "بدون مخلل",                    // optional
  "items": [
    { "item_id": 12, "quantity": 2, "option_ids": [101, 110] }
  ]
}
```

Response `201` — an **Order** object:
```json
{
  "id": 7,
  "reference": "WSL-7A3K",
  "status": "placed",
  "fulfillment_type": "pickup",
  "table_number": null,
  "subtotal": 76.0,
  "total": 76.0,
  "prep_minutes": null,
  "customer_notes": "بدون مخلل",
  "created_at": "2026-09-20T18:30:00+03:00",
  "store": { "token": "QJ6VJFYN", "name": "برجر بلد" },
  "items": [
    {
      "id": 31, "name": "بيج تيستي", "unit_price": 38.0,
      "quantity": 2, "line_total": 76.0,
      "options": [
        { "group": "الحجم", "name": "كبير", "price_delta": 5.0 },
        { "group": "الإضافات", "name": "جبن", "price_delta": 3.0 }
      ]
    }
  ]
}
```
If `configuration.auto_accept_orders` is true, `status` returns `"accepted"` with a `prep_minutes`.

### `GET /orders?filter=active|past` — the customer's orders
`active` = placed/accepted/preparing/ready; `past` = completed/rejected/cancelled.
Returns `{ "data": [ Order, ... ] }` (paginated).

### `GET /orders/{id}` — one order (for the tracking screen)
Returns an **Order** object. Poll / refetch to reflect status changes.

### `POST /orders/{id}/cancel` — cancel
Allowed **only while `status == "placed"`** (before the kitchen accepts).
Returns the updated Order, or `422 ORDER_NOT_CANCELLABLE`.

---

## 4. Order status lifecycle

```
placed ──► accepted ──► preparing ──► ready ──► completed   (terminal)
   │           │            │
   └► rejected └────────────┴──────► cancelled              (terminal)
```
- Customer may cancel only from `placed`.
- Merchant drives `accepted → preparing → ready → completed`, and may `reject`/`cancel`.
- `prep_minutes` is committed when the order is **accepted**.

The UI should render these seven statuses; localized labels are the app's own.

---

## 5. Merchant — manage orders (merchant token)

### `GET /merchant/orders?filter=active|past`
Returns `{ "data": [ Order, ... ] }` for the merchant's store. Each Order also
includes a `customer` object `{ name, phone }`.

### `POST /merchant/orders/{id}/status` — advance an order
Request:
```json
{ "status": "accepted", "prep_minutes": 15 }   // prep_minutes only on "accepted"
{ "status": "rejected", "reason": "مغلق حالياً" } // reason only on "rejected"
{ "status": "preparing" }
{ "status": "ready" }
{ "status": "completed" }
```
Response `200`:
```json
{
  "order": { /* Order */ },
  "allowed_transitions": ["preparing", "ready", "cancelled"]
}
```
An illegal move (e.g. `accepted → completed`) returns `422` with
`error_code: "INVALID_ORDER_TRANSITION"`. Use `allowed_transitions` to show only
the buttons that are valid from the current state.

---

## 6. Merchant — manage the menu (merchant token)

### Categories
- `GET  /merchant/menu/categories` → `{ "data": [ MenuCategory ] }`
- `POST /merchant/menu/categories` — body `{ name_ar, name_en?, sort_order?, is_active? }`
- `PUT  /merchant/menu/categories/{id}` — same fields (all optional)
- `DELETE /merchant/menu/categories/{id}`
- `POST /merchant/menu/categories/{id}/image` — multipart form, field `image` (jpg/png/webp ≤ 4 MB)

### Items
- `GET  /merchant/menu/items` → `{ "data": [ MenuItem ] }` (includes `option_groups`)
- `POST /merchant/menu/items` — body:
  `{ name_ar, name_en?, description_ar?, description_en?, menu_category_id?, price, calories?, is_available?, is_active?, is_featured?, sort_order? }`
- `PUT  /merchant/menu/items/{id}` — same fields (all optional)
- `DELETE /merchant/menu/items/{id}`
- `POST /merchant/menu/items/{id}/image` — multipart, field `image`
- `PUT  /merchant/menu/items/{id}/options` — **replaces the whole option tree**:
```json
{
  "groups": [
    {
      "name_ar": "الحجم", "min_select": 1, "max_select": 1,
      "options": [
        { "name_ar": "وسط", "price_delta": 0 },
        { "name_ar": "كبير", "price_delta": 5 }
      ]
    }
  ]
}
```
A group with `min_select > max_select` or `min_select >` option count is refused
with `422 OPTION_GROUP_INVALID` (and `group_index`).

---

## 7. Error format

Every error carries a stable `error_code`; **switch on the code, never the message**
(messages are localized).

```json
{ "message": "…localized…", "error_code": "SLOT_TAKEN" }
```

Codes the restaurant UI should handle:
| Code | When |
|---|---|
| `STORE_NOT_FOUND` | bad/unknown store token |
| `FULFILLMENT_UNAVAILABLE` | pickup/dine-in disabled for this store |
| `ORDER_NOT_PLACEABLE` | order rejected (empty cart, unavailable item, bad options) |
| `ORDER_NOT_CANCELLABLE` | cancel attempted after the kitchen accepted |
| `INVALID_ORDER_TRANSITION` | merchant sent an illegal status move |
| `OPTION_GROUP_INVALID` | saving an unfulfillable option group |
| `NOT_FOUND` | order/resource not owned by caller |

Validation errors return `422` with Laravel's `{ "message", "errors": { field: [..] } }`.

---

## 8. How to build the UI without backend code

1. **Point at a running API** — the developer sets the base URL to your dev/staging
   server (or you share a test build). They never need the PHP source.
2. **Auth** — give them one test customer token and one test merchant token
   (or the login endpoints). Everything else follows this contract.
3. **Mock while offline** — the JSON samples above are enough to stub responses
   (e.g. a local `json-server`, Postman mock, or hard-coded fixtures) so UI work
   proceeds even when the API is down.
4. **The golden rule** — the client sends *ids + quantities*; the server owns all
   prices, validation, and status. The UI must treat computed prices as display
   hints and always render the server's returned `total`/`status`.
