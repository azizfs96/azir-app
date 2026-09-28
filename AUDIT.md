# Wasla — Production Readiness Audit

**Date:** 2026-08-15 · **Scope:** Laravel API · Flutter customer app · React merchant dashboard
**Method:** direct code inspection. Every finding below cites a file and line I actually read.
**Code changed during this audit:** none.

| Component | Files | Lines | Tests |
|---|---|---|---|
| Laravel API | 145 | 10,883 | 132 passing, 8 real test classes |
| Flutter app | 35 | 5,875 | 20 (logic only, **0 widget tests**) |
| React dashboard | 35 | 3,435 | **0** |
| CI pipeline | — | — | **none** |

---

## PRODUCTION READINESS SCORE: **48 / 100**

The domain core is genuinely strong — the availability engine, the booking state machine and the
tenant isolation layer are better than most MVPs and are backed by real tests. What is missing is
almost entirely the *operational* half: the booking lock has a hole, nothing is observable, the
scheduler and queue are not running, and two of three clients have no tests at all.

| Area | Score | Note |
|---|---|---|
| Domain logic & architecture | 78 | engine + state machine + tenancy are well built |
| Booking correctness | 45 | **the lock has a real gap — see C-1** |
| Security | 52 | strong tenancy, but IDOR + no token expiry + CORS `*` |
| Database | 72 | good indexes; missing a slot-level constraint |
| Flutter quality | 55 | no image cache, no crash reporting, no a11y |
| Performance | 50 | N+1 in the hottest query, dead cache |
| Testing | 40 | backend good; clients near zero |
| Observability | 15 | 3 log lines, no monitoring, no crash reporting |
| Production config | 30 | debug on, dev OTP, dev ATS exception, no CI |

---

# A. CRITICAL ISSUES

### C-1 · Double-booking is possible — the lock target is inconsistent
**File:** `Back-end/app/Domain/Booking/BookingService.php:87-92` and `:186-188`
**Affects:** correctness, data integrity, revenue, merchant trust

```php
// create()
if ($staff !== null) {
    Staff::whereKey($staff->id)->lockForUpdate()->first();   // locks a STAFF row
} else {
    Branch::whereKey($branch->id)->lockForUpdate()->first(); // locks a BRANCH row
    $staff = $this->staffAssigner->assign(...);              // ...then picks a staff
}
if (! $this->availability->isStillFree($staff, $branch, ...)) { throw; }
```

**Problem.** Two concurrent writers can end up holding *different* lock rows while checking and
writing against the *same* staff member:

| | Request A | Request B |
|---|---|---|
| Path | customer picked Sara explicitly | no staff picked → auto-assign |
| Lock acquired | `staff` row (Sara) | `branch` row |
| Availability checked for | Sara | Sara (assigner chose her) |
| Result | insert | insert |

Neither blocks the other. `isStillFree()` returns true for both, and **both bookings are written to
the same stylist at the same minute.**

This is reachable today:
- `reschedule()` locks the *staff* row (`:186`, because `$booking->staff` is always populated — the
  assigner sets it) while a concurrent `create()` on a `staff_selection = false` store locks the
  *branch* row. Different rows, same staff, no mutual exclusion.
- Any merchant who toggles `staff_selection` while bookings are in flight puts in-flight requests on
  both paths simultaneously.

The `AvailabilityEngineTest` and `BookingStateMachineTest` do **not** catch this: they run
sequentially in one process, so the second attempt always sees the first booking already committed.
The tests prove the *re-check* works; they prove nothing about the *lock*.

**Recommended solution — two layers:**

1. **Always lock the same row for a given resource.** Resolve the staff member *before* opening the
   transaction, then lock that staff row on every path. When the store genuinely has no staff, lock
   the branch — but then never lock a staff row for that store.
2. **Add a database-level backstop**, because a row lock is application discipline and the next
   contributor will not know about it:
   ```sql
   ALTER TABLE bookings
     ADD COLUMN slot_key VARCHAR(64)
       GENERATED ALWAYS AS (
         CASE WHEN booking_status IN ('pending','confirmed','checked_in')
              THEN CONCAT_WS('-', COALESCE(staff_id,0), branch_id, starts_at)
         END
       ) STORED,
     ADD UNIQUE KEY bookings_slot_unq (slot_key);
   ```
   MySQL ignores NULLs in unique keys, so cancelled/no-show rows release the slot automatically.
   This makes a double booking *impossible* rather than *unlikely*, and turns the race into a clean
   `QueryException` the service can convert to `409 SLOT_TAKEN`.

> This is the one finding that alone blocks launch. Everything else is recoverable after go-live.

---

### C-2 · The availability cache is never invalidated
**File:** `Back-end/app/Http/Controllers/Api/V1/PublicApi/AvailabilityController.php:136`
**Affects:** correctness, UX, conversion

```php
return Cache::remember($key, $ttl, fn () => $this->availability->slotsFor(...));
```

`grep -rn "Cache::" app/` returns exactly **one** call site. `BookingService` contains no cache
invalidation at all. After any booking, the 60-second cache keeps serving the slot that was just
taken, so the next customer selects it and receives `409 SLOT_TAKEN`.

At a busy salon this is not an edge case — it is the normal experience during peak hours, and it
looks like a broken app rather than a taken slot.

**Fix.** Bust the affected keys inside the booking transaction (or tag the cache by
`store:{id}:date:{ymd}` and flush the tag). Reduce the TTL to ~15s until then.

---

### C-3 · Queued notifications are never delivered
**File:** `Back-end/app/Listeners/SendBookingNotification.php:22` · `.env:38`

`SendBookingNotification implements ShouldQueue` with `QUEUE_CONNECTION=database`, and there is no
worker process, no Supervisor/Horizon config, and no deployment documentation for one.

Every booking confirmation, cancellation and reschedule notification is written to the `jobs` table
and **never runs**. `NotificationTest` passes only because `phpunit.xml` sets `QUEUE_CONNECTION=sync`
— the tests exercise a delivery path production does not use.

**Fix.** Ship a `php artisan queue:work` supervisor unit (or Horizon) and add a queue-depth alarm.
Add one test that asserts the listener is queued rather than executed inline.

---

### C-4 · Appointment reminders never fire
**File:** `Back-end/routes/console.php:15`

`Schedule::command('wasla:send-reminders')->everyFifteenMinutes()` requires either a system cron
entry running `schedule:run` or a `schedule:work` process. Neither exists, and neither is documented.

Reminders are the single highest-value notification in a booking product — they are what reduce
no-shows, which is the merchant's main pain. Currently the command is dead code.

**Fix.** Add the cron entry to deployment, and alert if `wasla:send-reminders` has not run in 30 min.

---

# B. HIGH PRIORITY

### H-1 · IDOR — `exists:` validation rules ignore the tenant scope
**File:** `Back-end/app/Http/Controllers/Api/V1/Merchant/ServiceController.php:74`,
`StaffController.php:145`
**Affects:** security, data integrity

```php
'service_category_id' => ['sometimes','nullable','integer','exists:service_categories,id'],
'branch_id'           => ['sometimes','nullable','integer','exists:branches,id'],
```

Laravel's `exists` rule queries the table through the presence verifier, which **does not apply
Eloquent global scopes**. `BelongsToTenant` therefore does not protect it. Merchant A can post
merchant B's `service_category_id` or `branch_id` and it validates.

The three-layer isolation model has a genuine gap here: layer 2 (global scope) does not reach
validation, and no policy runs on the referenced id.

**Fix.** Scope every cross-reference rule:
```php
Rule::exists('service_categories', 'id')->where('merchant_id', $this->tenant->idOrFail())
```

---

### H-2 · Sanctum tokens never expire
**File:** `Back-end/config/sanctum.php:53` — `'expiration' => null`

A stolen customer or merchant token is valid forever. There is no refresh mechanism, no rotation,
and no "sign out everywhere". Combined with H-3 (tokens in `localStorage`) a single XSS is permanent
account compromise.

**Fix.** Set an expiration (e.g. 30 days customer / 12 hours dashboard), add refresh, and prune with
`sanctum:prune-expired`.

---

### H-3 · Dashboard tokens live in `localStorage`
**File:** `frond-end/src/api/client.ts:17,31`

`localStorage` is readable by any script on the origin, so any XSS — including one introduced by a
future dependency — exfiltrates a non-expiring merchant token (H-2).

**Fix.** Move to an httpOnly, Secure, SameSite cookie, or accept the risk explicitly with a strict
CSP and short expiry. This is a deliberate trade-off, so record whichever you choose.

---

### H-4 · CORS allows every origin
**File:** `Back-end/config/cors.php:15` — `'allowed_origins' => [env('CORS_ALLOWED_ORIGINS', '*')]`

The default is `*`. `supports_credentials` is `false`, which limits the damage, but any site can
call the API with a token it has obtained and read the response.

**Fix.** Default to the known dashboard origin; never ship `*`.

---

### H-5 · N+1 in the hottest query in the system
**File:** `Back-end/app/Domain/Scheduling/AvailabilityEngine.php:158-181`

```php
foreach ($candidates as $staff) {
    $this->staffTimeOffBlockers($staff, ...);   // 1 query per staff
    $this->bookingBlockers(Booking::query()->where('staff_id', $staff->id), ...); // 1 more
}
```

**2 queries per staff member per day requested.** A 10-stylist salon costs 20 queries for one day;
the `days=1..14` multi-day parameter (`AvailabilityController.php:70`) multiplies that to **280
queries in one request.**

The architecture document targets p95 < 150 ms. This will not meet it under load, and
`preventLazyLoading` does not catch it because these are explicit queries, not lazy loads.

**Fix.** Fetch all bookings and time-off for the candidate set in two queries before the loop, then
group in memory by `staff_id`.

---

### H-6 · Uncached network images
**File:** `flutter/lib/features/stores/presentation/store_avatar.dart`,
`storefront_header.dart` — `Image.network(...)`; `cached_network_image` is not in `pubspec.yaml`

Every logo and cover re-downloads on each scroll and each screen entry. On mobile data — the normal
case for this product — this is wasted bandwidth, visible pop-in, and battery drain.

**Fix.** Adopt `cached_network_image` with a disk cache and a stable placeholder.

---

### H-7 · No crash reporting or global error handler anywhere
**Files:** `flutter/lib/main.dart` (no `runZonedGuarded`, no `FlutterError.onError`);
`Back-end/composer.json` (no Sentry/Bugsnag); `frond-end/src` (no ErrorBoundary)

Three log statements exist in the entire backend, all in dev drivers
(`LogSmsSender.php:19`, `LogPushChannel.php:33`, `NotificationDispatcher.php:114`).

**You will not know when production breaks.** A crash on a customer's phone is invisible; a 500 on
the API is invisible; a React render error blanks the merchant's dashboard with no report.

**Fix.** Sentry in all three, plus `FlutterError.onError` + `runZonedGuarded`, plus a React
`ErrorBoundary`, plus structured logging on booking create/cancel and every admin action.

---

### H-8 · Universal Links / App Links cannot work
**Files:** `Back-end/public/.well-known/` does not exist;
`flutter/ios/Runner/Runner.entitlements:17` declares `applinks:wasla.sa`

The iOS entitlement is present but the server serves no `apple-app-site-association` and no
`assetlinks.json`. Spec §7 calls the deep-link journey "extremely important" — as configured, every
scanned QR opens a browser instead of the app.

**Fix.** Serve both files (correct MIME, no redirect), then re-test on real devices.

---

### H-9 · Policy coverage is inconsistent
**Files:** `Merchant/CustomerController.php`, `DashboardController.php`, `MediaController.php`,
`QrController.php`, `SettingsController.php`, `Admin/*` — **0 `authorize()` calls**

Those controllers rely entirely on the global scope. That is defence-in-depth reduced to one layer,
and the admin controllers have no authorization beyond `role:admin` middleware — so any admin can act
on any merchant with no per-action policy, and `MerchantPolicy::approve()` (which returns `false`) is
never actually consulted.

**Fix.** Call `authorize()` on every state-changing merchant action; give admin actions real
policies rather than relying on the route guard.

---

# C. MEDIUM PRIORITY

| # | Finding | File:Line | Impact |
|---|---|---|---|
| M-1 | **`guest_booking` setting is not implemented.** The toggle, DB columns and validation exist; the endpoint always requires auth. A merchant can enable a feature that does nothing. | `Customer/BookingController.php` (no guest path) | maintainability, trust |
| M-2 | **QR funnel is broken.** `resulted_in_booking_id` is read by the dashboard but never written, so "bookings from QR" is permanently 0 — the core product metric. | `QrController.php:40`, `StoreResolver.php` | product analytics |
| M-3 | **`POST /bookings` is not idempotent.** No `Idempotency-Key` despite the architecture doc specifying it. A retry on a flaky mobile network creates a duplicate booking. | `routes/api.php:112` | correctness |
| M-4 | **No `Payment` domain.** `app/Domain/Payment/` does not exist; `PaymentProviderInterface` is documented but unbuilt. The `payments` table is dead weight. | doc/code mismatch | maintainability |
| M-5 | **Multi-day availability has no cap on cost.** `days` accepts up to 14, multiplying H-5 by 14. | `AvailabilityController.php:70` | performance |
| M-6 | **`TextEditingController` leaked.** Created in `_promptForCode` and never disposed. | `scanner_screen.dart:106` | memory |
| M-7 | **Async gaps outnumber `mounted` guards** (5 awaits in presentation vs 4 guards). | `flutter/lib/features/**` | crashes |
| M-8 | **React Query uses defaults** — no `retry`, `staleTime`, or offline handling; a flaky connection shows a hard error. | `frond-end/src/main.tsx` | UX |
| M-9 | **No React `ErrorBoundary`** — one render error blanks the dashboard. | `frond-end/src` | UX |
| M-10 | **Flutter tokens in `SharedPreferences`,** not Keychain/Keystore — readable on a jailbroken/rooted device. | `token_store.dart:14` | security |
| M-11 | **Dev ATS exception ships in `Info.plist`** — hardcoded `172.20.10.2` and `NSAllowsLocalNetworking`. Must not reach the App Store. | `ios/Runner/Info.plist:18-24` | security |
| M-12 | **Flutter default API base is `127.0.0.1`.** A release build without `--dart-define` silently points at the device itself. | `core/config/env.dart:11` | release safety |

---

# D. LOW PRIORITY

| # | Finding | File:Line |
|---|---|---|
| L-1 | **79 raw `fontSize` literals** — no typography scale, so type drifts per screen. | `flutter/lib/**` |
| L-2 | **Weekday/month names duplicated** in three files (`date_step.dart`, `confirm_step.dart`, `WeeklyHours.tsx`). | 3 files |
| L-3 | **`ExampleTest.php` scaffolding left** in both `Feature/` and `Unit/`. | `tests/` |
| L-4 | **Store `_money()` helper duplicated** across three widgets. | `service_step.dart`, `storefront_screen.dart`, … |
| L-5 | **`PickerStep` now serves only `branch`** — a generic abstraction with one caller. | `booking_flow_screen.dart:238` |
| L-6 | **`.env.example` lacks the Wasla keys** (`WASLA_OTP_FIXED_CODE`, `PAYMENT_ONLINE_ENABLED`, `CORS_ALLOWED_ORIGINS`) — a new environment starts misconfigured. | `.env.example` |
| L-7 | **`APP_ENV=local`, `APP_DEBUG=true`** committed in `.env`. Correct for dev; verify the deploy overrides both. | `.env:2-4` |

---

# E. MISSING TESTS

**Current:** 132 backend · 20 Flutter (logic only) · 0 React · 0 E2E · no CI.

### The gap that matters most

There is **no concurrency test**. C-1 exists precisely because every booking test runs sequentially.
A test that proves the lock works must run two writers in parallel — e.g. two processes hitting the
endpoint, or two DB connections in one test with a barrier between the read and the write.

### Test matrix

| Layer | Area | Now | Needed | Priority |
|---|---|---|---|---|
| **Backend** | Availability engine | ✅ 13 | edge: DST, split shift + time-off overlap, buffer at closing time | Medium |
| | Booking state machine | ✅ 17 | — | — |
| | Tenant isolation | ✅ 14 | **`exists:` rule IDOR (H-1)** | **High** |
| | **Concurrency** | ❌ | **parallel double-book, parallel reschedule vs create** | **Critical** |
| | Auth | ✅ 21 | token expiry, revoked-token replay | High |
| | Media upload | ❌ | oversize, wrong mime, path traversal, tenant isolation of files | High |
| | Admin | ✅ 13 | — | — |
| | Notifications | ✅ 12 | assert listener is **queued**, not inline | High |
| | Rate limiting | ❌ | 429 on each limited route | Medium |
| | Idempotency | ❌ | duplicate `POST /bookings` | Medium |
| **Flutter** | `BookingFlow` logic | ✅ 20 | — | — |
| | **Widget tests** | ❌ **0** | every step renders; empty/error/loading states | **High** |
| | Golden tests | ❌ | storefront + service step, ar **and** en, RTL/LTR | Medium |
| | Integration | ❌ | scan → book → confirm against a mock API | High |
| | Offline | ❌ | airplane mode on every screen | High |
| **React** | **Everything** | ❌ **0** | component tests for forms; MSW-mocked API tests | **High** |
| **E2E** | Full journey | ❌ | merchant registers → admin approves → customer books | High |
| **CI** | — | ❌ | run all suites + `flutter analyze` + `tsc` on every push | **Critical** |

---

# F. PERFORMANCE IMPROVEMENTS

1. **Fix the availability N+1** (H-5) — 280 → ~4 queries on a 14-day request. Biggest single win.
2. **Invalidate the availability cache on write** (C-2), then raise the TTL safely.
3. **Add `cached_network_image`** (H-6).
4. **Cache store resolution.** `StoreResolver::resolve()` eager-loads 6 relations on every QR scan
   (`StoreResolver.php:39-52`); the payload is near-static between merchant edits. Cache per
   `public_token`, bust on merchant write.
5. **`recordAccess()` writes on every storefront open** (`StoreResolver.php:74`) — a synchronous
   INSERT plus two UPDATEs in the request path. Move to a queued job.
6. **Paginate nothing-bounded lists.** `/merchant/staff` and `/merchant/branches` return everything.
7. **Flutter list performance** is currently fine (`ListView.separated`, small lists) but the
   service list will need `itemExtent` if merchants add 50+ services.

---

# G. SECURITY IMPROVEMENTS

**Priority order:**

1. **Scope the `exists:` rules** (H-1) — the only live IDOR found.
2. **Token expiry + rotation** (H-2), and reconsider `localStorage` (H-3).
3. **Lock CORS to known origins** (H-4).
4. **Strip the dev ATS exception and the fixed OTP before any store submission** (M-11).
   `OtpService::generateCode()` does throw in production, which is good — but verify the deploy sets
   `APP_ENV=production`, because that guard is the *only* thing standing between you and "any phone
   number logs in with 1111".
5. **Add `authorize()` to the uncovered controllers** (H-9), including admin.
6. **Test the upload endpoint adversarially.** The implementation looks right — mime allow-list,
   random filenames, tenant folders — and I verified a disguised `evil.php.png` is rejected. But it
   has **zero automated tests**, so nothing stops a regression.
7. **Audit log coverage is thin.** Only admin merchant actions are logged
   (`AuditLogger` has 4 call sites). Spec §35 also requires price changes, staff deactivation, QR
   regeneration and refunds.
8. **No account lockout** beyond rate limiting, and no password complexity rule
   (`OnboardingController.php:47` — `min:8` only).

**Verified as genuinely sound** (do not weaken these):
- Tenant global scope + auto-stamping, with 14 tests
- Cross-tenant reads return **404, not 403** — no existence leak
- OTP hashed, single-use, attempt-capped, previous codes invalidated
- Login does not reveal whether an email exists (timing-equalised)
- `merchant_id` is absent from every `$fillable`
- Public tokens are CSPRNG, non-sequential, not derived from ids
- IPs hashed, never stored raw

---

# H. ARCHITECTURE IMPROVEMENTS

1. **The BusinessEngine boundary is real and worth protecting.** `flow()` returning the step list as
   data is the best decision in this codebase — it is what makes §43 true. Keep quoting/fulfilment
   out of it.
2. **`AvailabilityEngine` is doing too much** (430 lines: resolution, window maths, querying, slot
   generation, union). Split the persistence lookups into a `ScheduleRepository` so the engine
   becomes pure and unit-testable without a database — which would also make the missing edge-case
   tests cheap to write.
3. **No repository layer anywhere.** Acceptable at this size, but `Booking::query()->withoutTenancy()`
   now appears in controllers (`Customer/BookingController.php:52`), which leaks a persistence
   concern into HTTP.
4. **The `payments` table and `Payment` model are dead** (M-4). Either build the seam or drop the
   table until it is needed; a dead table invites someone to "just add a column".
5. **Flutter has no repository interfaces** — providers depend on concrete classes, so widget tests
   cannot inject fakes. This is *why* there are zero widget tests. Fixing this unblocks the whole
   client test matrix.
6. **`booking_flow_screen.dart` is 430+ lines** with the step switch, submission, error recovery and
   back-navigation logic all in one widget. Extract a `BookingFlowController`.
7. **Three copies of date formatting.** Extract a shared `WaslaDateFormat`, ideally driven by
   `intl` (already a dependency but unused for this).

---

# Recommended sequence

**Before launch — non-negotiable**
1. C-1 booking lock + DB constraint, with a *parallel* test
2. C-2 cache invalidation
3. C-3 queue worker, C-4 scheduler
4. H-1 IDOR, H-2 token expiry, H-4 CORS
5. H-7 crash reporting — you cannot operate blind
6. CI running the existing 152 tests

**Before scale**
H-5 N+1 · H-6 image cache · M-3 idempotency · H-9 policies · widget + React tests

**Then**
H-8 deep links (blocks the core QR promise, but only once you own the domain) · M-1 guest booking ·
M-2 QR funnel · architecture items

---

## Closing note

I want to be precise about confidence. Findings C-1 through C-4, H-1, H-5, H-6, H-7, H-8 and every
M/L item were verified by reading the exact lines cited. **C-1 I reasoned about from the code paths
rather than reproducing** — a proving test needs true parallelism, which I did not run. I am
confident in the analysis, but the first thing I would write is the test that makes it undeniable.

The domain modelling here is genuinely good. The gap is operational maturity, not design.
