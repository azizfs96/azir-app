# Wasla — وصلة

**Architecture & Technical Specification (MVP)**

> One customer app · many independent merchants · each merchant has a QR code · scanning it opens that merchant directly.
> **Not a marketplace.** There is no discovery, search, or browse. The merchant brings the customer.

---

## 0. Document status

This is the design proposal required by §45 of the product brief. It covers the ten items requested
(architecture, ERD, API, Flutter, React, onboarding, customer flow, risks, open decisions) and closes
with a phased build plan. Implementation follows the phases; nothing significant is written until the
shape below is agreed.

| Layer | Stack | Directory |
|---|---|---|
| API | Laravel 13 · PHP 8.4 · MySQL 8.4 · Redis | `Back-end/` |
| Merchant dashboard + admin | React 19 · TypeScript · Vite · TanStack Query | `frond-end/` |
| Customer app | Flutter 3.47 · Riverpod · iOS + Android | `flutter/` |

---

## 1. The one architectural rule

> **A new merchant is created by data and configuration — never by code.**

Onboarding a merchant must not require a Flutter build, a React build, a backend deploy, a migration,
or a line of code. Only: create merchant → configure → generate QR.

Everything below is in service of that rule. The concrete consequence is that **the Flutter app has no
merchant-specific UI**. It renders a store from a configuration payload the API returns. If a merchant
disables staff selection, the staff screen does not exist for that merchant — not because of a build
flag, but because the payload said `staff_selection: false`.

---

## 2. Core Engine vs Business Engines

The platform splits in two. Getting this boundary right is what makes the Restaurant / Laundry / Clinic
engines additive later instead of a rewrite.

```
┌──────────────────────────── CORE ENGINE (shared, vertical-agnostic) ────────────────────────────┐
│  Identity · Merchants · Stores · Branches · Customers · MyStores · QR + deep links               │
│  Payments abstraction · Notifications · Settings · Multi-tenancy · Audit · Media                 │
└─────────────────────────────────────────┬───────────────────────────────────────────────────────┘
                                          │  BusinessEngine contract
        ┌─────────────────────────────────┼─────────────────────────────────┐
        ▼                                 ▼                                 ▼
┌──────────────────┐            ┌──────────────────┐            ┌──────────────────┐
│ BeautyWellness   │            │ Restaurant       │            │ Laundry          │
│ BookingEngine    │            │ OrderingEngine   │            │ ServiceEngine    │
│  ✅ MVP          │            │  ⛔ not built    │            │  ⛔ not built    │
└──────────────────┘            └──────────────────┘            └──────────────────┘
```

**Core owns** the noun `Store` and the verb `transact`. It does not know what a "service" or an
"appointment" is.

**An engine owns** its catalog shape, its fulfilment flow, its configuration schema, and its screen
sequence. It declares them; core executes them.

### 2.1 The contract

```php
interface BusinessEngine
{
    public function key(): string;                 // 'beauty_wellness' — stored in stores.business_type
    public function label(): array;                // ['ar' => …, 'en' => …] for onboarding step 2
    public function configurationSchema(): array;  // which toggles exist + types + defaults
    public function defaultConfiguration(): array;
    public function flow(Store $store): array;     // ordered step descriptors for the client
    public function catalog(Store $store): array;  // services / menu / items
}
```

Quoting and fulfilment (turning a validated selection into a `Booking`) deliberately live in the
Booking domain services rather than on this interface, because they need the availability engine and
the row-lock write path. **The engine's job is to *describe* the experience; core performs it.**

`Store.business_type` selects the engine at runtime via `BusinessEngineRegistry`. Adding a vertical =
one class + one registry entry + its own tables. Core tables are untouched.

### 2.2 What "flow" means

The engine returns the customer journey as data. Flutter walks it. This is what keeps merchant
variation out of the app binary:

```jsonc
// Merchant A — wants customers to pick their stylist, single branch, deposit required
"flow": [
  { "step": "service", "required": true,  "multi": false },
  { "step": "staff",   "required": true,  "allow_any": true },
  { "step": "date",    "required": true },
  { "step": "time",    "required": true },
  { "step": "notes",   "required": false },
  { "step": "payment", "required": true, "mode": "deposit", "deposit_percent": 25 },
  { "step": "confirm" }
]

// Merchant B — no staff choice, 3 branches, pay at store
"flow": [
  { "step": "branch",  "required": true },
  { "step": "service", "required": true,  "multi": false },
  { "step": "date",    "required": true },
  { "step": "time",    "required": true },
  { "step": "payment", "required": true, "mode": "pay_at_store" },
  { "step": "confirm" }
]
```

Flutter has one widget per **step type** (7 total), not one screen per merchant. The server decides
order and presence. Merchant B's customers never see a staff screen; the backend assigns staff itself.

---

## 3. Backend structure

Laravel, modular monolith. Domain-oriented, not layer-oriented — `app/Domain/*` groups by business
concept so an engine can be lifted out later.

```
Back-end/app/
├── Domain/
│   ├── Identity/          User, Customer, OtpCode, roles, guards
│   ├── Merchant/          Merchant, Store, Branch, MerchantSetting, onboarding state machine
│   ├── Catalog/           Service, ServiceCategory, Staff, StaffService  (beauty engine)
│   ├── Scheduling/        BranchSchedule, StaffSchedule, TimeOff
│   │                      AvailabilityEngine, SlotGenerator, StaffAssigner
│   ├── Booking/           Booking, BookingStatus (state machine), BookingSettings
│   │                      BookingService, RescheduleService, CancellationPolicy
│   ├── Payment/           Payment, PaymentService, PaymentProviderInterface, providers/
│   ├── Discovery/         QrCode, QrScan, CustomerStore ("My Stores"), DeepLinkAttribution
│   └── Notification/      Channels, templates, dispatcher
├── Engines/
│   ├── BusinessEngine.php            (contract)
│   ├── BusinessEngineRegistry.php
│   └── BeautyWellness/BeautyWellnessEngine.php
├── Http/
│   ├── Controllers/Api/V1/{Customer,Merchant,Admin,Public}/
│   ├── Requests/          form request validation only
│   ├── Resources/         API resources — the single response contract
│   └── Middleware/        ResolveTenant, EnsureMerchantApproved, LocaleFromHeader
├── Policies/              tenant isolation lives here
└── Support/               Money, TimeRange, Slug/TokenGenerator
```

**Controllers stay thin**: validate (Form Request) → call a service → return a Resource. All business
logic sits in `Domain/*/Services`. Jobs handle notifications, QR rendering, and reminder scheduling.

---

## 4. Multi-tenancy

**Model: single database, `merchant_id` discriminator, enforced in the authorization layer.**

Chosen over schema-per-tenant because the MVP has one vertical, cross-tenant admin reporting is
required, and thousands of small merchants make per-schema migration operationally painful.

Three layers, defence in depth:

1. **Never trust the client.** `merchant_id` is *never* read from a request body, query string, or
   header. It is derived once from `auth()->user()->merchant_id` by `ResolveTenant` middleware and
   stored in a request-scoped `TenantContext`.
2. **Global scope.** Every tenant-owned model uses a `BelongsToTenant` trait applying a global
   `where merchant_id = ?` scope, and auto-filling `merchant_id` on create. A query that forgets to
   filter still cannot leak.
3. **Policies.** Every merchant endpoint is `authorize()`d. Policies assert
   `$model->merchant_id === $tenant->id` — including on nested resources (a staff member reached
   through a branch, a booking reached through a service).

Customer endpoints are scoped by `customer_id` the same way. Admin uses a separate guard that
explicitly opts out of the global scope via `withoutTenancy()`, which is only callable from
`Admin\*` controllers.

> A tenant-isolation test suite asserts that merchant A receives 404 (not 403 — no existence leak) on
> every merchant resource belonging to merchant B. This runs in CI as a gate.

---

## 5. Database schema (ERD)

### 5.1 Relationship map

```
users ──1:1── customers
  │
  └──1:1── merchants ──1:N── stores ──1:N── branches
                │                │              │
                │                ├──1:1── qr_codes ──1:N── qr_scans
                │                ├──1:1── booking_settings
                │                └──1:N── service_categories ──1:N── services
                │                                                       │
                ├──1:N── staff ──N:M── services  (staff_services)        │
                │          │                                            │
                │          ├──1:N── staff_schedules                      │
                │          └──1:N── time_off                             │
                │                                                        │
                └──1:N── bookings ───────────────────────────────────────┘
                            │
                            ├──1:N── booking_status_history
                            └──1:N── payments

customers ──N:M── stores   (customer_stores  ← "My Stores", the ONLY discovery surface)
```

### 5.2 Tables

Only non-obvious columns are listed. All tables carry `id` (BIGINT UNSIGNED AUTO_INCREMENT),
`created_at`, `updated_at`. Money is `DECIMAL(10,2)` + a `currency` CHAR(3) defaulting to `SAR` —
never floats. All timestamps are stored **UTC**; see §5.4.

#### Identity

**`users`** — one table, role-discriminated.
`name`, `email` (nullable, unique), `phone` (unique, E.164), `phone_verified_at`, `password`
(nullable — customers have none), `role` ENUM(`customer`,`merchant_owner`,`merchant_staff`,`admin`),
`merchant_id` (nullable FK — set for merchant_owner/merchant_staff), `locale` ENUM(`ar`,`en`) default
`ar`, `is_active`, `last_login_at`.
Indexes: `unique(phone)`, `unique(email)`, `index(merchant_id, role)`.

**`customers`** — `user_id` FK unique, `first_name`, `last_name`, `gender` (nullable — relevant for
women-only/men-only salons), `date_of_birth` (nullable), `default_locale`, `marketing_opt_in`.

**`otp_codes`** — `phone`, `code_hash` (never store plaintext), `purpose` ENUM(`login`,`verify_phone`,
`merchant_login`), `attempts` TINYINT, `expires_at`, `consumed_at`.
Index: `index(phone, purpose, expires_at)`. Rate limited per phone and per IP.

#### Merchant

**`merchants`** — the tenant root.
`owner_user_id`, `legal_name`, `display_name`, `commercial_registration` (nullable), `vat_number`
(nullable — see §12 risk), `contact_phone`, `contact_email`, `status` ENUM(`pending`,`approved`,
`suspended`,`rejected`) default `pending`, `onboarding_step` TINYINT, `onboarded_at`, `approved_at`,
`suspended_at`, `suspension_reason`.
Index: `index(status)`.

**`stores`** — the customer-facing storefront. One per merchant in the MVP; the schema allows more.
`merchant_id`, `public_token` CHAR(8) **unique** (the `8F72K`-style id — see §8.2),
`business_type` VARCHAR (engine key, default `beauty_wellness`), `name_ar`, `name_en`,
`description_ar`, `description_en`, `logo_path`, `cover_path`, `brand_color` CHAR(7),
`timezone` default `Asia/Riyadh`, `phone`, `instagram`, `is_published`, `published_at`.
Indexes: `unique(public_token)`, `index(merchant_id)`.

**`branches`** — `merchant_id`, `store_id`, `name_ar`, `name_en`, `address_line`, `city`,
`latitude` DECIMAL(10,8), `longitude` DECIMAL(11,8), `phone`, `google_maps_url`,
`buffer_before_minutes` SMALLINT default 0, `buffer_after_minutes` SMALLINT default 0,
`slot_interval_minutes` SMALLINT default 15, `is_active`, `sort_order`.
Index: `index(store_id, is_active)`.
*Lat/long are for showing the customer where to go after booking — not for proximity search. There is
no "nearby" query anywhere in the system.*

**`merchant_settings`** — one row per merchant, JSON `settings` for advanced/rare options, so adding a
setting never needs a migration. Hot, frequently-queried flags stay as real columns on
`booking_settings`.

#### Catalog (Beauty & Wellness engine)

**`service_categories`** — `merchant_id`, `store_id`, `name_ar`, `name_en`, `icon`, `sort_order`,
`is_active`. (e.g. Hair, Nails, Facial, Massage)

**`services`** — `merchant_id`, `store_id`, `service_category_id` (nullable),
`name_ar`, `name_en`, `description_ar`, `description_en`, `image_path`,
`price` DECIMAL(10,2), `duration_minutes` SMALLINT, `buffer_after_minutes` SMALLINT default 0,
`is_active`, `sort_order`, `max_per_booking` default 1.
Indexes: `index(store_id, is_active)`, `index(service_category_id)`.

**`staff`** — optional per §15. `merchant_id`, `store_id`, `branch_id` (nullable),
`user_id` (nullable — only if the staff member logs into the dashboard),
`name`, `title_ar`/`title_en` (e.g. Senior Stylist), `avatar_path`, `gender`, `bio`,
`is_active`, `is_bookable`, `sort_order`.
Index: `index(branch_id, is_active, is_bookable)`.

**`staff_services`** — `staff_id`, `service_id`, optional `duration_override_minutes`,
`price_override`. Unique on (`staff_id`,`service_id`).
> **Rule (§15):** a staff member with **zero** rows here can perform **all** active services. This
> keeps setup fast for the common case and is handled explicitly in the availability engine.

#### Scheduling

**`branch_schedules`** — `branch_id`, `day_of_week` TINYINT 0–6, `opens_at` TIME, `closes_at` TIME,
`is_closed`. Supports split shifts (a Riyadh salon closing for Asr/Maghrib) via multiple rows per day.
Unique on (`branch_id`,`day_of_week`,`opens_at`).

**`staff_schedules`** — same shape, `staff_id` + `day_of_week` + `starts_at`/`ends_at` +
`break_starts_at`/`break_ends_at` (both nullable), `is_off`.

**`time_off`** — ad-hoc closures, works for both. `staff_id` (nullable) OR `branch_id` (nullable),
`starts_at` DATETIME, `ends_at` DATETIME, `reason`, `is_recurring_annual` (for Eid / National Day).
Index: `index(staff_id, starts_at, ends_at)`, `index(branch_id, starts_at, ends_at)`.

#### Booking

**`booking_settings`** — one row per store. The §10 toggles as real columns (queried on every store
open, so no JSON):
`store_id` unique, `staff_selection` BOOL, `branch_selection` BOOL, `payment_required` BOOL,
`deposit_required` BOOL, `deposit_type` ENUM(`percent`,`fixed`), `deposit_value` DECIMAL,
`allow_cancellation` BOOL, `cancellation_deadline_hours` SMALLINT default 4,
`refund_policy` ENUM(`full`,`deposit_forfeited`,`none`),
`allow_rescheduling` BOOL, `reschedule_deadline_hours` SMALLINT,
`customer_notes` BOOL, `guest_booking` BOOL,
`auto_confirm` BOOL default true, `min_lead_time_minutes` SMALLINT default 60,
`max_advance_days` SMALLINT default 60, `reminder_hours_before` SMALLINT default 24.

**`bookings`** — per §18.
`merchant_id`, `store_id`, `branch_id` (**nullable**), `customer_id` (**nullable** — guest booking),
`guest_name`/`guest_phone` (nullable), `service_id`, `staff_id` (**nullable** per §18),
`reference` CHAR(10) unique (human-readable, e.g. `WSL-4K7QX2`),
`starts_at` DATETIME (UTC), `ends_at` DATETIME (UTC),
`duration_minutes`, `price`, `deposit_amount`, `paid_amount`, `currency`,
`booking_status` ENUM (§19), `payment_status` ENUM(`unpaid`,`deposit_paid`,`paid`,`refunded`,
`partially_refunded`,`failed`),
`customer_notes` TEXT nullable, `merchant_notes` TEXT nullable,
`source` ENUM(`qr`,`app`,`dashboard`) — attribution for §25,
`cancelled_by` ENUM(`customer`,`merchant`,`system`) nullable, `cancelled_at`, `cancellation_reason`,
`rescheduled_from_booking_id` nullable, `checked_in_at`, `completed_at`,
`metadata` JSON.

Indexes — tuned for the availability query and the dashboard, per §28:
```sql
INDEX (staff_id, starts_at, ends_at)        -- availability: staff conflict scan (hottest)
INDEX (branch_id, starts_at)                -- availability: branch day load
INDEX (store_id, booking_status, starts_at) -- dashboard today/upcoming
INDEX (merchant_id, starts_at)              -- reports
INDEX (customer_id, starts_at DESC)         -- customer "my bookings"
UNIQUE (reference)
```

**`booking_status_history`** — append-only audit of the §19 state machine.
`booking_id`, `from_status`, `to_status`, `changed_by_user_id` (nullable — system),
`actor_type` ENUM(`customer`,`merchant`,`system`), `reason`, `created_at`.

#### Payment

**`payments`** — `merchant_id`, `booking_id`, `provider` VARCHAR, `provider_payment_id` VARCHAR,
`type` ENUM(`full`,`deposit`,`balance`,`refund`), `amount`, `currency`,
`status` ENUM(`pending`,`authorized`,`captured`,`failed`,`refunded`),
`method` ENUM(`mada`,`visa`,`mastercard`,`apple_pay`,`cash`) nullable,
`failure_reason`, `raw_response` JSON, `paid_at`, `refunded_at`,
`idempotency_key` unique.
Index: `index(booking_id)`, `index(provider, provider_payment_id)`.

#### Discovery (QR + My Stores)

**`qr_codes`** — `store_id` unique, `public_token` (mirrors store), `image_path`,
`scan_count` UNSIGNED, `last_scanned_at`, `version` (incremented if regenerated).

**`qr_scans`** — per §25. `store_id`, `customer_id` (**nullable** — pre-login scan),
`session_id` CHAR(36), `ip_hash` (hashed, not raw — privacy), `user_agent`, `platform`
ENUM(`ios`,`android`,`web`), `is_first_scan_for_customer` BOOL,
`resulted_in_booking_id` nullable, `scanned_at`.
Index: `index(store_id, scanned_at)`.

**`customer_stores`** — **"My Stores". This is the entire discovery model.**
`customer_id`, `store_id`, `added_via` ENUM(`qr`,`deep_link`,`booking`),
`first_added_at`, `last_visited_at`, `last_booking_at`, `is_hidden`.
Unique on (`customer_id`,`store_id`). Index: `index(customer_id, last_visited_at DESC)`.
> The customer app's home screen is `SELECT … FROM customer_stores WHERE customer_id = ?`. There is
> no query in the system that returns stores a customer has not personally added. This is enforced by
> the absence of any such endpoint — not by a filter that could be removed.

**`deep_link_attributions`** — solves the §7 "don't lose merchant context after install" requirement.
`store_public_token`, `fingerprint_hash`, `platform`, `ip_hash`, `user_agent`,
`claimed_by_customer_id` nullable, `claimed_at`, `expires_at` (1 hour), `created_at`.

#### Platform

**`notifications`** — `notifiable_type`/`notifiable_id`, `channel` ENUM(`push`,`email`,`sms`,
`whatsapp`), `template_key`, `payload` JSON, `locale`, `status` ENUM(`queued`,`sent`,`failed`,`read`),
`sent_at`, `read_at`, `provider_message_id`, `failure_reason`.

**`device_tokens`** — `user_id`, `token`, `platform`, `app_version`, `last_seen_at`.

**`audit_logs`** — §35. `merchant_id` nullable, `user_id`, `action`, `auditable_type`/`auditable_id`,
`old_values` JSON, `new_values` JSON, `ip_hash`, `created_at`.
Covers: price changes, booking status overrides, staff deactivation, settings changes, QR regeneration,
refunds, merchant approval/suspension.

### 5.3 Booking state machine (§19)

Arbitrary transitions are rejected at the model layer, not the controller.

```
                  ┌──────────────► cancelled  (terminal)
                  │                    ▲
   pending ───► confirmed ───► checked_in ───► completed  (terminal)
      │             │                │
      │             └────────────────┴──────► no_show     (terminal)
      └──────────► cancelled
```

| From | Allowed to | Who |
|---|---|---|
| `pending` | `confirmed`, `cancelled` | merchant, system (auto-confirm / payment success) |
| `confirmed` | `checked_in`, `cancelled`, `no_show` | merchant; customer may `cancel` within deadline |
| `checked_in` | `completed`, `no_show` | merchant |
| `completed` / `cancelled` / `no_show` | — | terminal |

Every transition writes `booking_status_history` and fires a domain event
(`BookingConfirmed`, `BookingCancelled`, …) which the notification layer listens to.

### 5.4 Time handling

Store `DATETIME` in **UTC**. Each store carries a `timezone` (default `Asia/Riyadh`). All availability
maths happens in store-local time, converted at the boundary. The API returns ISO-8601 with offset
(`2026-08-16T19:00:00+03:00`) plus a separate `timezone` field, so clients never guess. Saudi Arabia
has no DST, which removes the worst class of bug — but the engine is written DST-correct anyway so the
architecture survives expansion to markets that do have it.

---

## 6. The availability engine (§17)

The single most correctness-critical component. Given `(store, service, date, [branch], [staff])`
it returns bookable start times.

### 6.1 Algorithm

```
1. Resolve branch
     explicit → use it; else if store has exactly 1 active branch → use it (never ask the customer, §16)

2. Candidate staff set
     staff_id given          → [that staff]
     staff_selection off     → all active+bookable staff at branch
     filter by capability    → staff with ≥1 staff_services row must include this service
                               staff with ZERO rows can do everything (§15)
     no staff exist at all   → branch itself is the resource; skip to step 4 with branch hours

3. Per-staff free window for the date
     window  = branch_schedule[dow] ∩ staff_schedule[dow]      (both can be split shifts)
     window −= staff break
     window −= time_off overlapping the date (staff-level and branch-level)
     window −= existing bookings in (pending, confirmed, checked_in),
               each expanded by branch.buffer_before and service.buffer_after

4. Generate candidates
     grid   = branch.slot_interval_minutes (default 15)
     needed = service.duration (or staff override) + service.buffer_after
     offer start S  ⟺  [S, S + needed] ⊆ some free window

5. Apply booking policy
     drop S < now + min_lead_time_minutes
     drop date > today + max_advance_days

6. Union across staff
     a start time is offered if ≥1 candidate staff is free at it
     staff_selection on  → return the chosen staff_id with each slot
     staff_selection off → return times only; assignment happens at booking time (§9)
```

### 6.2 Worked example (§17)

Service *Hair Color*, 120 min. Sara works 10:00–22:00, break 14:00–15:00, and already has a booking
18:00–20:00. Grid 15 min.

Free windows: `10:00–14:00`, `15:00–18:00`, `20:00–22:00`.
120-minute fits: `10:00, 10:15, 10:30, …, 11:45` · `15:00, 15:15, 15:30, 15:45` · `20:00`.
`17:00` is **not** offered — it would run to 19:00 and collide. Correct.

### 6.3 Preventing double-booking

Availability is advisory; two customers can pass step 6 simultaneously. The write path is the guard:

```php
DB::transaction(function () use ($request) {
    // serialize all concurrent booking attempts for this staff member
    $staff = Staff::whereKey($staffId)->lockForUpdate()->first();

    // re-verify inside the lock — the read above may now be stale
    if (! $this->availability->isStillFree($staff, $startsAt, $endsAt)) {
        throw new SlotNoLongerAvailableException;
    }

    return Booking::create([...]);
});
```

MySQL has no exclusion constraints, so a row lock on the *staff* row is the serialization point.
For staff-less branch bookings the lock is taken on the branch row instead. Contention is per-staff
and held for milliseconds, so this scales fine at MVP volume. The API returns a clean
`409 SLOT_TAKEN` and the app re-fetches slots rather than showing a raw error.

### 6.4 Automatic staff assignment (§9, §15)

When `staff_selection` is off, `StaffAssigner` picks among free staff by: fewest bookings that day
(load balancing) → longest idle since last booking → lowest id (deterministic tiebreak). Deterministic
ordering matters so the same request under the lock always resolves the same way.

### 6.5 Performance

The hot query is "bookings for these staff on this date", served by `INDEX (staff_id, starts_at,
ends_at)`. Schedules and time-off for a store are cached in Redis (`store:{id}:schedule:v{n}`),
invalidated on any schedule write. Availability responses themselves are cached for 60 s keyed by
`(branch, service, staff, date)` and busted on booking write for that key. Target: **< 150 ms p95**.

---

## 7. API design (§36)

`/api/v1`, Sanctum bearer tokens, four namespaces with different guards.

Every response is a Laravel API Resource. Errors are uniform:

```jsonc
{ "message": "This slot is no longer available.",
  "error_code": "SLOT_TAKEN",
  "errors": { "starts_at": ["…"] } }   // 422 only
```

`error_code` is a stable machine-readable string; clients switch on it, never on the message (which is
localized).

### 7.1 Public — no auth

| Method | Path | Notes |
|---|---|---|
| `GET` | `/stores/{publicToken}` | **The QR resolution endpoint.** Returns the §31 payload. Records a `qr_scan`. |
| `GET` | `/stores/{publicToken}/services` | Catalog, grouped by category |
| `GET` | `/stores/{publicToken}/availability` | `?service_id=&date=&branch_id=&staff_id=` |
| `POST` | `/deep-link/attribute` | Deferred deep-link claim (§8.3) |

### 7.2 Auth

`POST /auth/otp/request` · `POST /auth/otp/verify` (customer) · `POST /auth/login` (merchant,
email+password) · `POST /auth/refresh` · `POST /auth/logout` · `GET /auth/me`

### 7.3 Customer — `auth:sanctum` + role `customer`

| Method | Path | Notes |
|---|---|---|
| `GET` | `/me/stores` | **My Stores — the home screen.** Includes next appointment / last visit. |
| `POST` | `/me/stores` | Adds a store by `public_token` (called on first scan) |
| `DELETE` | `/me/stores/{id}` | Hide a store |
| `POST` | `/bookings` | Idempotent via `Idempotency-Key` header |
| `GET` | `/bookings` | `?filter=upcoming\|past` |
| `GET` | `/bookings/{id}` | |
| `POST` | `/bookings/{id}/cancel` | 422 with policy detail if past deadline |
| `POST` | `/bookings/{id}/reschedule` | Re-checks availability (§22) |
| `GET/PATCH` | `/me/profile` · `POST /me/devices` | |

There is deliberately **no** `GET /stores`, no `/search`, no `/nearby`, no `/categories`. The absence
is the feature (§46).

### 7.4 Merchant — `auth:sanctum` + role `merchant_owner|merchant_staff` + `EnsureMerchantApproved`

`/merchant/dashboard` · `/merchant/bookings` (+ `/{id}/status`, `/{id}/reschedule`) ·
`/merchant/calendar` · CRUD for `/services`, `/service-categories`, `/staff` (+ `/schedule`),
`/branches` (+ `/schedule`), `/time-off` · `/merchant/customers` ·
`/merchant/qr` (+ `/download`, `/regenerate`) · `/merchant/payments` · `/merchant/reports/*` ·
`/merchant/settings/{booking|store|payment}` · `/merchant/onboarding/step/{n}`

No merchant endpoint accepts a `merchant_id`. Ever.

### 7.5 Admin — `auth:sanctum` + role `admin`

`/admin/merchants` (+ `/approve`, `/reject`, `/suspend`) · `/admin/customers` · `/admin/stores` ·
`/admin/bookings` · `/admin/metrics`

### 7.6 Rate limits

OTP request 3/5min per phone + 10/hour per IP · OTP verify 5 attempts then invalidate ·
public store resolution 60/min per IP · booking create 10/min per customer · authenticated 120/min.

---

## 8. QR, deep links, and the install gap (§7, §24, §38)

### 8.1 Domains

`wasla.sa` (landing + deep link) · `api.wasla.sa` · `merchant.wasla.sa` (React) · `admin.wasla.sa`

### 8.2 The token

`public_token` is **8 characters** from a 30-symbol Crockford-style alphabet with `0 1 I L O U`
removed (no visual ambiguity when a customer reads a printed code aloud). That is 30⁸ ≈ **6.6 × 10¹¹**
combinations, and the brief's `8F72K` shape is preserved.

Generated with a CSPRNG, uniqueness-checked on insert. It is **not** derived from the database id, is
not sequential, and is not enumerable at any useful rate given the 60/min public rate limit. Internal
ids never appear in a URL (§24).

### 8.3 The install gap — the hard part

Scanning when the app is installed is easy (Universal Links / App Links). The requirement that
**merchant context survives an App Store round-trip** (§7) is the real work. Google's Firebase Dynamic
Links shut down in August 2025, so this is built in-house:

```
Scan wasla.sa/s/8F72K
        │
   ┌────┴─────────────────────────────┐
   │ App installed?                   │
   ├──────────────┬───────────────────┤
   │ YES          │ NO                │
   ▼              ▼
Universal Link   Landing page at wasla.sa/s/8F72K
opens app        · shows the real store (name, logo, services) — proves the link works
directly to      · POSTs a fingerprint {platform, ip_hash, ua, screen} → deep_link_attributions
the store        · redirects to App Store / Play
                          │
                     user installs, opens Wasla
                          │
                     app POSTs its own fingerprint to /deep-link/attribute
                          │
                     match within 1h window → returns 8F72K
                          │
                     app adds store to My Stores and opens it ✅
```

Belt and braces, because probabilistic fingerprint matching is not 100%:

- **Android** gets it exactly right for free via Play Install Referrer — the token rides in the
  install referrer, so no guessing.
- **iOS** uses the fingerprint match, plus a visible fallback: the landing page shows the code
  (`8F72K`) and the app's first screen has an "Enter store code" field. When matching fails, the
  customer types 5 characters. Never a dead end.
- Attribution rows expire after 1 hour and are deleted after being claimed.

This is a stated risk (§12) — it is the least deterministic part of the system and warrants explicit
QA on both platforms.

---

## 9. Flutter architecture (§30)

Feature-first clean architecture. **Riverpod** for state (compile-safe DI, testable, good async
primitives), **go_router** for routing with deep-link handling, **dio** for HTTP, **freezed** +
`json_serializable` for models.

```
flutter/lib/
├── core/
│   ├── config/          env, endpoints, flavors
│   ├── network/         dio client, auth interceptor, error mapping, retry
│   ├── storage/         secure token store, My Stores cache
│   ├── theme/           colors, typography (Arabic + Latin), spacing, components
│   ├── localization/    ARB files: ar (default), en — RTL/LTR (§33)
│   ├── router/          go_router + Universal/App Link intake
│   └── error/           Failure types, user-facing messages
├── features/
│   ├── auth/            phone → OTP → session
│   ├── home/            My Stores (§5). The whole home screen.
│   ├── qr_scanner/      mobile_scanner, permission flow, token resolution
│   ├── stores/          dynamic storefront rendered from configuration (§31)
│   ├── booking/
│   │   ├── flow/        BookingFlowController — walks the server-provided step list
│   │   └── steps/       ServiceStep · StaffStep · BranchStep · DateStep · TimeStep
│   │                    · NotesStep · PaymentStep · ConfirmStep
│   ├── payments/        provider SDK boundary
│   ├── notifications/   FCM/APNs registration, in-app inbox
│   └── profile/
└── shared/              widgets, formatters, extensions
```

Each feature is `data/` (DTOs, remote source, repository impl) → `domain/` (entities, repository
contract) → `presentation/` (providers, screens, widgets).

### 9.1 The rendering rule

`BookingFlowController` holds the step list from the API and an answers map. It knows nothing about
salons. Adding a step type later = one widget + one enum case, and it lights up for every merchant
whose config requests it — with no app update for the merchant.

```dart
// Not: if (merchant == 'glow_beauty') showStaffPicker();
final step = flow.steps[currentIndex];
return switch (step.type) {
  StepType.service => ServiceStep(step: step, onAnswer: _advance),
  StepType.staff   => StaffStep(step: step, onAnswer: _advance),
  StepType.branch  => BranchStep(step: step, onAnswer: _advance),
  ...
};
```

### 9.2 Localization & RTL (§33)

Arabic is the default locale and the design baseline; English is the secondary. Zero hard-coded
strings — everything through ARB. `Directionality` flips the whole tree; all padding uses
`EdgeInsetsDirectional` and all icons that imply direction are mirrored. Arabic numerals are
configurable per locale. **The app is laid out RTL-first and checked LTR**, not the reverse — that
ordering catches the bugs that a translated-afterwards app ships with.

---

## 10. React dashboard architecture (§29)

Vite · React 19 · TypeScript strict · TanStack Query (server state) · Zustand (the little UI state
that exists) · React Hook Form + Zod (validation shared with API contracts) · Tailwind + Radix
primitives · FullCalendar for the calendar.

```
frond-end/src/
├── app/            router, providers, guards
├── api/            typed client, generated types, query keys, hooks per resource
├── components/
│   ├── ui/         Button, Input, Select, Badge, Card, Sheet, Tooltip …
│   └── shared/     DataTable · Modal · Drawer · Form · DatePicker · TimePicker
│                   · StatusBadge · ConfirmDialog · EmptyState · PageHeader
├── features/       dashboard · calendar · bookings · services · staff · branches
│                   · customers · qr · payments · reports · settings · onboarding
├── admin/          the §39 admin panel (separate route tree + guard)
├── lib/            date/tz helpers, money, permissions
└── locales/        ar / en — RTL via `dir` attribute + Tailwind logical properties
```

Every feature folder: `routes/` · `components/` · `hooks/` · `schemas/`. No component over ~200 lines;
tables, forms, and modals compose from `components/shared` (§29).

**Design direction (§32):** one neutral gray scale, one accent, semantic status colors, and generous
whitespace. Flat surfaces with hairline borders — not stacked drop-shadow cards. No gradients. Type
hierarchy does the work. The reference points are Linear and Stripe, not a bootstrap admin template.

---

## 11. The two flows

### 11.1 Merchant onboarding (§11, §42) — target: under 10 minutes

```
Register (email + password + phone OTP)
   ↓
1. Business info      name, phone, city
2. Business type      Beauty & Wellness  ← only option in MVP, but a real choice point
3. Add branch         name, address, working hours (sensible defaults pre-filled)
4. Add services       name, price, duration     ← starter templates: Hair Cut / Color / Facial …
5. Add staff          OPTIONAL — skippable in one tap
6. Booking settings   6 plain-language toggles, not 50 (§11)
7. Payment settings   pay at store / online / deposit
8. Generate QR        preview + download + print sheet
9. Publish            → admin approval → live
```

Progress is persisted per step (`merchants.onboarding_step`), so it resumes after a drop-off. Steps 5
and 7 are skippable; a merchant can reach a working QR with **name → branch → one service → publish**.
The other 40 settings live under Settings, discovered later.

### 11.2 Customer (§41) — target: under 60 seconds

```
Scan QR → Wasla opens → Glow Beauty → Service → [Staff] → Date → Time → [Payment] → Confirmed
```

First-ever use inserts exactly one extra step: phone + OTP, *after* slot selection and before
confirmation — so the customer sees value before being asked for anything. Returning customers to a
known store skip straight to the storefront. Bracketed steps appear only if the merchant enabled them.

---

## 12. Architectural risks (§45.9)

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | **Double-booking under concurrency** | High | `lockForUpdate` on staff/branch + re-verify inside the transaction (§6.3). Load-tested with concurrent writers before launch. |
| 2 | **iOS deferred deep link is probabilistic** | High | Play Install Referrer on Android (exact); fingerprint + visible "enter code" fallback on iOS (§8.3). Must be QA'd on real devices, not simulators. |
| 3 | **Availability query cost as merchants grow** | Medium | Composite indexes (§5.2), Redis schedule cache, 60 s slot cache. Watch p95; the fallback is a materialized availability table. |
| 4 | ~~ZATCA e-invoicing compliance~~ | **Closed** | **Descoped 2026-08-15.** No online payment in the MVP, so no VAT handling and no Fatoora integration. Becomes live again the moment `payments.online_enabled` is flipped — see §13. |
| 5 | ~~Payment provider lock-in~~ | **Closed** | **Descoped 2026-08-15.** Pay-at-store only. `PaymentProviderInterface` and the `payments` table remain as the seam (spec §20 asks for extensibility), but no provider is integrated. |
| 6 | **Timezone / DST correctness** | Medium | UTC storage, store-local computation, offset-carrying ISO strings. KSA has no DST, so bugs stay latent until expansion — the engine is written DST-correct now. |
| 7 | **Tenant leakage** | High | Three layers (§4) + a CI test suite asserting cross-tenant 404s on every endpoint. |
| 8 | **"Just add search"** | High — product | Discovery endpoints do not exist. Re-adding one is a visible new route in review, not a config flag. The absence is load-bearing (§46). |
| 9 | **Split shifts / prayer-time closures** | Medium | Multiple schedule rows per day from day one — retrofitting this later would be a painful migration. |
| 10 | **Gendered salons** | Medium | Saudi salons are commonly women-only or men-only. `stores.gender_policy` + staff gender exist so the wrong customer isn't shown a booking they cannot attend. |
| 11 | **No full Xcode on this machine** | Low — local | Only Command Line Tools are installed, so iOS device/simulator builds are unavailable until Xcode is installed (§14). Android and all backend/dashboard work proceed unblocked. |
| 12 | **Notification cost/deliverability** | Low | Push first (free), SMS only for OTP and day-of reminders. Channel abstraction lets WhatsApp land later without touching booking code. |

---

## 13. Decisions needed from you (§45.10)

Implementation is not blocked on these — each has a stated default I will build against and can be
swapped later without rework. But they need real answers before launch.

| # | Decision | Default I'll build |
|---|---|---|
| 1 | ~~Payment provider~~ | ✅ **Decided 2026-08-15 — not in the MVP.** Pay-at-store only. |
| 2 | **SMS/OTP provider** — Unifonic · Msegat · Taqnyat · Twilio | **Interim (2026-08-15): OTP is fixed at `1111`**, code written to the log, no SMS sent. `SmsSender` interface ready. ⚠️ `OtpService` throws if the fixed code is still set when `APP_ENV=production` — a fixed OTP means a phone number alone is enough to impersonate anyone. |
| 3 | ~~ZATCA e-invoicing scope~~ | ✅ **Decided 2026-08-15 — not in the MVP.** Follows from #1; revisit together. |
| 4 | **Do merchant staff get dashboard logins?** | Schema supports it (`staff.user_id`); MVP ships owner-only |
| 5 | **Deposit default** | 25%, merchant-editable |
| 6 | **Guest booking without OTP?** | Off — phone verification always, since it powers reminders and no-show tracking |
| 7 | **Cancellation refund policy default** | Deposit forfeited inside the deadline, full refund outside |
| 8 | **Does `wasla.sa` exist / is it registered?** | Assumed yes — Universal Links need it live with an AASA file before iOS deep linking can be tested |
| 9 | **One store per merchant, or several?** | Schema allows many; UI ships one-per-merchant |
| 10 | **Arabic name/brand assets** | Placeholder brand tokens; swap when you have real ones |

---

## 14. Local environment — what got installed

`sudo` requires your password, so everything is installed **user-local** and needs no admin rights.

| Tool | Version | Location |
|---|---|---|
| Node | 24.19.0 LTS | `~/.nvm` (via nvm 0.40.3) |
| PHP | 8.4.8 | `~/.local/bin/php` — static build, all Laravel extensions incl. `pdo_mysql`, `redis`, `gd`, `zip` |
| Composer | 2.10.2 | `~/.local/bin/composer` (signature-verified) |
| MySQL | 8.4.11 LTS | `~/.local/opt/mysql` — runs from your home dir, no admin rights |
| Flutter | 3.47.0 stable | `~/development/flutter` |

`PATH` is wired in `~/.zshrc`. **Open a new terminal** for it to take effect.

**Two gaps that need your password — you'll have to run these yourself:**

- **Xcode** (for iOS builds) — Command Line Tools only. Install Xcode from the App Store, then
  `sudo xcodebuild -license accept`. Android and backend work are unaffected.
- **Redis** (optional for MVP) — Laravel will use the `database` queue/cache driver until it's there.

---

## 15. Build phases

Each phase ends in something runnable and verified before the next begins (§45).

| Phase | Deliverable | Status |
|---|---|---|
| **0** | Toolchain installed, three projects scaffolded, DB running | ✅ **done** |
| **1** | Core schema + models + tenancy + policies + tenant-isolation tests | ✅ **done** |
| **2** | Auth (customer OTP, merchant password), roles, rate limits | ✅ **done** |
| **3** | Merchant domain: stores, branches, services, staff, schedules + CRUD API | ✅ **done** |
| **4** | **Availability engine** + booking state machine + concurrency guard, unit-tested hard | ✅ **done** |
| **5** | QR generation, `public_token`, store resolution, My Stores, deep-link attribution | ✅ **done** |
| ~~**6**~~ | ~~Payment abstraction + providers~~ — **descoped**, pay-at-store only | ➖ |
| **7** | Notifications (push + in-app), reminder jobs | ✅ **done** |
| **8** | React dashboard: shell, auth, dashboard, bookings, services, QR, settings | ✅ **done** |
| **9** | React: staff, branches, customers | ✅ **done** (calendar + reports deferred) |
| **10** | Flutter: shell, auth, My Stores home, QR scanner, deep links | ✅ **done** |
| **11** | Flutter: dynamic storefront + configurable booking flow + confirmation | ✅ **done** |
| **12** | Admin panel, audit logs, platform metrics | ✅ **done** |
| **13** | Arabic/English pass, RTL audit, seeders, E2E of the full QR→booking journey | ⬜ |

**Phase 4 is the one to get right.** It is the hardest correctness problem in the system and
everything customer-facing depends on it.
