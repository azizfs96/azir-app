# Azir — Deployment (Ubuntu + Nginx + MySQL)

Two hosts on one Ubuntu server, served by Nginx (independent of your Kubernetes
services):

| Host              | What            | Root                        |
|-------------------|-----------------|-----------------------------|
| `api.azir.sa`     | Laravel API     | `/var/www/azir/api/public`  |
| `portal.azir.sa`  | Merchant portal | `/var/www/azir/portal`      |

DNS: point `api.azir.sa` and `portal.azir.sa` (A/AAAA) at the server.

---

## 0. Server packages

> The app needs **PHP 8.4** (Laravel 13 / Symfony 8). Ubuntu ships 8.3, so add
> the ondrej PPA first:
> ```bash
> sudo add-apt-repository -y ppa:ondrej/php && sudo apt update
> ```

```bash
sudo apt update
sudo apt install -y nginx mysql-server php8.4-fpm php8.4-cli php8.4-mysql \
  php8.4-mbstring php8.4-xml php8.4-curl php8.4-gd php8.4-zip php8.4-bcmath \
  unzip git certbot python3-certbot-nginx
sudo update-alternatives --set php /usr/bin/php8.4   # make 8.4 the CLI default
# Composer
curl -sS https://getcomposer.org/installer | php && sudo mv composer.phar /usr/local/bin/composer
# Node 20 (to build the portal — can also be built on your laptop)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install -y nodejs
```

## 1. Database

```bash
sudo mysql <<'SQL'
CREATE DATABASE azir CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'azir'@'127.0.0.1' IDENTIFIED BY 'change-me-strong-password';
GRANT ALL PRIVILEGES ON azir.* TO 'azir'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
```

## 2. Get the code

```bash
sudo mkdir -p /var/www/azir && sudo chown -R $USER:$USER /var/www/azir
git clone https://github.com/azizfs96/azir-app.git /var/www/azir/src
ln -s /var/www/azir/src/Back-end /var/www/azir/api
```

## 3. Backend (api.azir.sa)

```bash
cd /var/www/azir/api
composer install --no-dev --optimize-autoloader
cp .env.production.example .env
# Edit .env: DB_PASSWORD, SEED_OWNER_PASSWORD, FCM_CREDENTIALS path, etc.
php artisan key:generate
php artisan migrate --seed --force      # creates schema + seeds the Azir store
php artisan storage:link                # exposes /storage (menu images, banner)
php artisan config:cache && php artisan route:cache

# Firebase push: upload the service account (NOT in git) to the path in .env
#   scp service-account.json server:/var/www/azir/api/storage/app/firebase/
mkdir -p storage/app/firebase

# Permissions
sudo chown -R www-data:www-data storage bootstrap/cache
```

Queue worker (delivers order notifications + FCM push):

```bash
sudo cp /var/www/azir/src/deploy/systemd/azir-queue.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now azir-queue
```

## 4. Frontend (portal.azir.sa)

`.env.production` already points at `https://api.azir.sa`. Build (on the server
or your laptop) and publish the static files:

```bash
cd /var/www/azir/src/frond-end
npm ci
npm run build                            # outputs dist/
sudo mkdir -p /var/www/azir/portal
sudo cp -r dist/* /var/www/azir/portal/
```

## 4b. Customer web app (azir.sa)

The same Flutter customer app, built for the web, so a customer can order from
`azir.sa/s/<token>` without installing anything. Zero backend changes (same API);
CORS already allows `azir.sa`.

```bash
cd /var/www/azir/src/flutter
flutter build web --release --dart-define=WASLA_API_BASE=https://api.azir.sa/api/v1
sudo mkdir -p /var/www/azir/web
sudo cp -r build/web/* /var/www/azir/web/
```

## 4c. Marketing landing page (azir.sa/)

The marketing landing (`landing/index.html`) is served at the **exact root** of
`azir.sa`; every other path — `azir.sa/s/<token>`, deep links, app assets — stays
the customer web app, so the QR links are unaffected. The landing is a single,
self-contained file (inline + data-URI assets), so there is nothing else to copy.

```bash
sudo mkdir -p /var/www/azir/landing
sudo cp /var/www/azir/src/landing/index.html /var/www/azir/landing/index.html
```

## 5. Nginx + SSL

```bash
sudo cp /var/www/azir/src/deploy/nginx/api.azir.sa.conf    /etc/nginx/sites-available/
sudo cp /var/www/azir/src/deploy/nginx/portal.azir.sa.conf /etc/nginx/sites-available/
sudo cp /var/www/azir/src/deploy/nginx/azir.sa.conf        /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/api.azir.sa.conf    /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/portal.azir.sa.conf /etc/nginx/sites-enabled/
sudo ln -sf /etc/nginx/sites-available/azir.sa.conf        /etc/nginx/sites-enabled/
# Verify the PHP-FPM socket path in api.azir.sa.conf matches: ls /run/php/
# Issue certs per host (standalone, nginx stopped) — see the notes if port 80 busy.
sudo certbot --nginx -d api.azir.sa -d portal.azir.sa -d azir.sa -d www.azir.sa
sudo nginx -t && sudo systemctl reload nginx
```

## 6. Flutter customer app

Build pointing at production and ship to the stores (bundle id `sa.azir.app`):

```bash
cd /var/www/azir/src/flutter   # or on your Mac
flutter build ios   --release --dart-define=WASLA_API_BASE=https://api.azir.sa/api/v1
flutter build apk   --release --dart-define=WASLA_API_BASE=https://api.azir.sa/api/v1
```

---

## Seeded data

`php artisan migrate --seed` creates the **Azir / برجر بلد** restaurant complete:
merchant + owner (`owner@azir.sa`, password = `SEED_OWNER_PASSWORD`), the logo
and banner, VAT/ZATCA invoicing settings, fulfilment config, and the full menu
(6 categories, 11 dishes with images). Nothing needs re-entering after deploy.

## Redeploy

```bash
cd /var/www/azir/src && git pull
cd Back-end && composer install --no-dev -o && php artisan migrate --force \
  && php artisan config:cache && php artisan route:cache && php artisan queue:restart
cd ../frond-end && npm ci && npm run build && sudo cp -r dist/* /var/www/azir/portal/
```

> Never commit `.env` or `storage/app/firebase/service-account.json` — both are gitignored.
