# Wasla — وصلة

> امسح، وادخل مباشرة. — *Scan, and enter directly.*

A shared digital platform that lets local businesses offer their own branded booking
experience without building a mobile app. Customers reach each business through a unique
QR code inside one universal app.

**Wasla is not a marketplace.** There is no discovery, search, or browse — the merchant
brings the customer. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full design.

| Folder | What | Stack |
|---|---|---|
| [`Back-end/`](Back-end) | API | Laravel 13 · PHP 8.4 · MySQL 8.4 |
| [`frond-end/`](frond-end) | Merchant dashboard + admin | React 19 · TypeScript · Vite |
| [`flutter/`](flutter) | Customer app | Flutter 3.47 · iOS + Android |

---

## First-time setup

Everything is installed **user-local** — no admin rights, nothing in `/usr/local`.
`~/.zshrc` already has the `PATH` wiring, so **open a new terminal** before starting.

### Start MySQL

MySQL runs from your home directory. It is not a system service, so start it per session:

```bash
mysqld --defaults-file="$HOME/.local/etc/my.cnf" --daemonize
```

Stop it with:

```bash
mysqladmin --defaults-file="$HOME/.local/etc/my.cnf" -u root shutdown
```

### Run the API

```bash
cd Back-end && php artisan serve
```

Check it: <http://localhost:8000/api/v1/health>

### Run the dashboard

```bash
cd frond-end && npm run dev
```

### Run the customer app

```bash
cd flutter && flutter run
```

---

## Tests

The tenant-isolation suite is a **release gate** — it asserts that one merchant can never
see another's data. If it fails, do not deploy.

```bash
cd Back-end && php artisan test
```

---

## Installed toolchain

| Tool | Version | Location |
|---|---|---|
| PHP | 8.4.8 | `~/.local/bin/php` |
| Composer | 2.10.2 | `~/.local/bin/composer` |
| MySQL | 8.4.11 | `~/.local/opt/mysql` |
| Node | 24.19.0 | `~/.nvm` |
| Flutter | 3.47.0 | `~/development/flutter` |

### Two things still need your password

Both require `sudo`, so you'll have to run them yourself:

- **Xcode** — only Command Line Tools are installed, so iOS builds aren't possible yet.
  Install Xcode from the App Store, then `sudo xcodebuild -license accept`.
  Android and all backend/dashboard work are unaffected.
- **Redis** — optional. Laravel uses the `database` cache/queue driver until it exists.

---

## Database credentials (local dev)

```
host      127.0.0.1:3306
database  wasla         (tests use wasla_test)
username  wasla
password  wasla_dev
```
