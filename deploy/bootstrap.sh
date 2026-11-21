#!/usr/bin/env bash
# ============================================================================
# Azir — rebuild a production server from NOTHING (Ubuntu 22.04/24.04).
#
#   curl -fsSL https://raw.githubusercontent.com/azizfs96/azir-app/main/deploy/bootstrap.sh -o bootstrap.sh
#   sudo DB_PASSWORD='...' SEED_OWNER_PASSWORD='...' CERT_EMAIL='you@azir.sa' bash bootstrap.sh
#
# Idempotent: safe to re-run (it skips what already exists). It installs the
# packages, MySQL database, the code at /var/www/azir, the Laravel .env, the
# queue worker, the portal + customer web + landing builds, Nginx and SSL.
#
# What it CANNOT recover from a deleted server (restore these yourself):
#   - the old database (merchants, customers, orders)  -> restore a dump with
#       mysql azir < dump.sql   BEFORE running `migrate`, or start fresh (seed)
#   - uploaded images under storage/app/public          -> copy them back
#   - storage/app/firebase/service-account.json          -> re-download from
#       the Firebase console (project azir-b7af7) and scp it to that path
# ============================================================================
set -euo pipefail

REPO="${REPO:-https://github.com/azizfs96/azir-app.git}"
BRANCH="${BRANCH:-main}"
ROOT=/var/www/azir
DB_PASSWORD="${DB_PASSWORD:-}"
SEED_OWNER_PASSWORD="${SEED_OWNER_PASSWORD:-}"
CERT_EMAIL="${CERT_EMAIL:-}"
SEED="${SEED:-yes}"            # SEED=no when restoring a database dump
BUILD_WEB="${BUILD_WEB:-no}"   # the Flutter web build needs the Flutter SDK; do it from a laptop instead
DEPLOY_USER="${SUDO_USER:-$USER}"

say() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run with sudo"
[ -n "$DB_PASSWORD" ] || die "set DB_PASSWORD='...' (MySQL password for the azir user)"
[ -n "$SEED_OWNER_PASSWORD" ] || die "set SEED_OWNER_PASSWORD='...' (dashboard password for the seeded owners)"
[ -n "$CERT_EMAIL" ] || die "set CERT_EMAIL='...' (Let's Encrypt contact)"

# ---------------------------------------------------------------------------
say "1/8 Packages (PHP 8.4, Nginx, MySQL, Node 20, Composer)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq software-properties-common ca-certificates curl gnupg >/dev/null
add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || true
apt-get update -qq
apt-get install -y -qq nginx mysql-server git unzip certbot python3-certbot-nginx \
  php8.4-fpm php8.4-cli php8.4-mysql php8.4-mbstring php8.4-xml php8.4-curl \
  php8.4-gd php8.4-zip php8.4-bcmath php8.4-intl >/dev/null
update-alternatives --set php /usr/bin/php8.4 >/dev/null 2>&1 || true
if ! command -v composer >/dev/null; then
  curl -sS https://getcomposer.org/installer | php -- --quiet && mv composer.phar /usr/local/bin/composer
fi
if ! command -v node >/dev/null || [ "$(node -v | cut -c2-3)" -lt 20 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null && apt-get install -y -qq nodejs >/dev/null
fi
systemctl enable --now php8.4-fpm mysql nginx >/dev/null

# ---------------------------------------------------------------------------
say "2/8 MySQL database + user"
mysql <<SQL
CREATE DATABASE IF NOT EXISTS azir CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'azir'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'azir'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON azir.* TO 'azir'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

# ---------------------------------------------------------------------------
say "3/8 Code at $ROOT"
mkdir -p "$ROOT" /var/www/certbot
if [ -d "$ROOT/src/.git" ]; then
  git -C "$ROOT/src" fetch --quiet origin && git -C "$ROOT/src" checkout --quiet "$BRANCH" && git -C "$ROOT/src" pull --quiet --ff-only
else
  git clone --quiet --branch "$BRANCH" "$REPO" "$ROOT/src"
fi
ln -sfn "$ROOT/src/Back-end" "$ROOT/api"
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$ROOT/src"

# ---------------------------------------------------------------------------
say "4/8 Backend (api.azir.sa)"
cd "$ROOT/api"
sudo -u "$DEPLOY_USER" composer install --no-dev --optimize-autoloader --no-interaction --quiet
if [ ! -f .env ]; then
  cp .env.production.example .env
  sed -i "s#^DB_PASSWORD=.*#DB_PASSWORD=${DB_PASSWORD}#" .env
  sed -i "s#^SEED_OWNER_PASSWORD=.*#SEED_OWNER_PASSWORD=${SEED_OWNER_PASSWORD}#" .env
  php artisan key:generate --force --quiet
  echo "    wrote .env (new APP_KEY — every old session/token is invalid, customers sign in again)"
else
  echo "    .env exists — kept"
fi
mkdir -p storage/app/firebase storage/app/public
php artisan storage:link --quiet || true
if [ "$SEED" = "yes" ]; then
  php artisan migrate --seed --force
else
  php artisan migrate --force
fi
php artisan config:cache --quiet && php artisan route:cache --quiet && php artisan view:clear --quiet
chown -R www-data:www-data storage bootstrap/cache
chmod -R ug+rwX storage bootstrap/cache

say "    queue worker (notifications + push)"
cp "$ROOT/src/deploy/systemd/azir-queue.service" /etc/systemd/system/azir-queue.service
systemctl daemon-reload && systemctl enable --now azir-queue >/dev/null && systemctl restart azir-queue

# ---------------------------------------------------------------------------
say "5/8 Merchant portal (portal.azir.sa)"
cd "$ROOT/src/frond-end"
sudo -u "$DEPLOY_USER" npm ci --silent
sudo -u "$DEPLOY_USER" npm run build --silent
mkdir -p "$ROOT/portal" && rm -rf "$ROOT/portal"/* && cp -r dist/* "$ROOT/portal/"

# ---------------------------------------------------------------------------
say "6/8 Landing pages (azir.sa)"
mkdir -p "$ROOT/landing" "$ROOT/web"
cp "$ROOT/src/landing/index.html" "$ROOT/landing/index.html"
cp "$ROOT"/src/landing/promo*.html "$ROOT"/src/landing/merchants*.html "$ROOT/landing/" 2>/dev/null || true
if [ "$BUILD_WEB" = "yes" ] && command -v flutter >/dev/null; then
  (cd "$ROOT/src/flutter" && sudo -u "$DEPLOY_USER" flutter build web --release --dart-define=WASLA_API_BASE=https://api.azir.sa/api/v1 && cp -r build/web/* "$ROOT/web/")
elif [ ! -f "$ROOT/web/index.html" ]; then
  echo "    customer web app not built here — from your Mac: flutter build web ... then scp build/web/* to $ROOT/web/"
fi

# ---------------------------------------------------------------------------
say "7/8 Nginx"
for h in api.azir.sa portal.azir.sa azir.sa; do
  cp "$ROOT/src/deploy/nginx/$h.conf" "/etc/nginx/sites-available/$h.conf"
  ln -sf "/etc/nginx/sites-available/$h.conf" "/etc/nginx/sites-enabled/$h.conf"
done
rm -f /etc/nginx/sites-enabled/default
# The site files reference the certificates; serve plain HTTP until they exist.
if [ ! -d /etc/letsencrypt/live/api.azir.sa ]; then
  say "    SSL certificates (Let's Encrypt) — DNS for api/portal/azir.sa must already point here"
  systemctl stop nginx
  certbot certonly --standalone --non-interactive --agree-tos -m "$CERT_EMAIL" \
    -d api.azir.sa -d portal.azir.sa -d azir.sa -d www.azir.sa \
    --cert-name api.azir.sa || die "certbot failed — check DNS, then re-run this script"
  # One certificate covers all hosts; point every site file at it.
  for h in portal.azir.sa azir.sa; do
    sed -i "s#/etc/letsencrypt/live/$h/#/etc/letsencrypt/live/api.azir.sa/#g" "/etc/nginx/sites-available/$h.conf"
  done
  systemctl start nginx
fi
nginx -t && systemctl reload nginx

# ---------------------------------------------------------------------------
say "8/8 Done"
cat <<EOF

  API     https://api.azir.sa/api/v1/health
  Portal  https://portal.azir.sa      (seeded owners: owner@azir.sa / owner@astrof.sa / owner@market.sa)
  Landing https://azir.sa

  Still to do by hand:
   - Firebase push: scp service-account.json to $ROOT/api/storage/app/firebase/  (then: systemctl restart azir-queue)
   - Customer web app: build on your Mac and copy to $ROOT/web/ (see deploy/DEPLOY.md §4b)
   - Branch coordinates + real images for each store from the dashboard
   - If you restored a database dump: php artisan migrate --force was applied on top of it

  Future deploys (one line):
   cd $ROOT/src && git pull && cd Back-end && php artisan migrate --force && php artisan config:cache && php artisan route:cache && php artisan queue:restart && cd ../frond-end && npm ci && npm run build && sudo cp -r dist/* $ROOT/portal/
EOF
