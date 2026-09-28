# Wasla — Restaurant UI Handoff (Flutter)

> For the UI developer extending the **restaurant template** in the customer app.
> You work **only** inside the `flutter/` folder. You do **not** need — and will
> not be given — the `Back-end/` source. You build against the running API using
> the contract in `restaurant-api-contract.md`.

---

## 1. What you receive

- The `flutter/` folder (self-contained Flutter app — it has its own `pubspec.yaml`).
- `restaurant-api-contract.md` — every endpoint, request/response shape, error code.
- An **API base URL** (dev/staging) and two test tokens (one customer, one merchant).

You do **not** receive: `Back-end/`, `frond-end/` (that's the merchant web dashboard),
any database, or any `.env`.

---

## 2. Run the app against the API (no backend on your machine)

```bash
cd flutter
flutter pub get
flutter run --dart-define=WASLA_API_BASE=https://<staging-host>/api/v1
```

- The API address is a **compile-time flag** (`--dart-define`), never hard-coded.
  Point it at whatever host we give you.
- Default (if the flag is omitted) is `http://127.0.0.1:8000/api/v1` — only useful
  if you also run a local API, which you don't need to.
- To scan/enter a store, use a restaurant store token we provide (e.g. from the
  storefront the QR opens).

---

## 3. Where the restaurant UI lives — edit only these

All of it is under `flutter/lib/features/`:

| File | Screen / piece |
|---|---|
| `stores/presentation/storefront_screen.dart` | store page; branches to the **menu** when `store.isRestaurant` |
| `menu/menu_view.dart` | the menu itself — category chips, "الأكثر مبيعاً", grid/large cards, view toggle |
| `menu/item_sheet.dart` | the dish sheet — option groups, quantity, live price, add-to-cart |
| `menu/cart_screen.dart` | cart + checkout footer (fulfillment, notes, place order) |
| `menu/order_status_screen.dart` | order tracking timeline |
| `menu/cart_controller.dart` | cart state (Riverpod) + price maths |
| `menu/order_repository.dart` | the HTTP calls for orders |
| `stores/domain/menu.dart` | the menu data models (parse the API JSON) |
| `core/localization/strings.dart` | Arabic/English text (add new strings here) |
| `core/theme/app_theme.dart` | colors, typography (`AppColors`, text styles) |

**Do not touch** anything under `booking/` (that's the beauty vertical), `auth/`,
`core/network/` (the shared HTTP client), or `core/router/` unless you add a new
screen route.

---

## 4. The rules that keep you and the backend in sync

These are contract guarantees — build to them and nothing breaks:

1. **The client sends intents, not prices.** When placing an order you send
   `{ item_id, quantity, option_ids }` only. The server returns the authoritative
   `total` and `status`. Show those — never your own computed total as truth.
   (Computing a price locally for a live preview is fine; just don't treat it as final.)
2. **Switch on `error_code`, never on the message.** Messages are localized by the
   server; codes are stable. (See the contract's error table.)
3. **Images** are relative paths; build the URL with the existing helper
   `logoUrlOf(path)` in `stores/presentation/store_avatar.dart`.
4. **Availability & option rules** come from the data: `is_available`, and each
   group's `min_select`/`max_select`. The server re-validates, but the UI should
   enforce them too so the customer isn't rejected after tapping "add".
5. **Money is display-only** until the server confirms.

---

## 5. Adding a screen (if you need one)

1. Build the widget under `features/menu/` (or a new folder).
2. Add its route in `core/router/app_router.dart` next to `/orders/:id`.
3. Add any text to `core/localization/strings.dart` (both `ar` and `en`).
4. Fetch data through a `Repository` + Riverpod provider (copy the pattern in
   `order_repository.dart`), using the shared `apiClientProvider` — do not create
   a second HTTP client.

---

## 6. Before you hand work back

```bash
cd flutter
flutter analyze     # must be clean
flutter test        # the existing suite must stay green
```

There is a widget/unit test suite covering the menu, cart, checkout and tracking
(`test/menu_*.dart`, `test/order_*.dart`, `test/booking_*.dart`). If you change
behaviour, update or add tests — don't delete them. A green `flutter analyze` and
`flutter test` is the definition of "done" for a change.

---

## 7. What you cannot change from here

The menu structure, order lifecycle, pricing, and validation are the server's.
If you need a new field, a new status, or a different rule, that's a **backend**
change — request it; don't work around it in the UI. The contract is the boundary.
