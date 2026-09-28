#!/bin/zsh
#
# Run the Wasla customer app on a connected iPhone.
#
# WHY THIS SCRIPT EXISTS: the app's default API base is 127.0.0.1, which on a
# phone means THE PHONE ITSELF. Running `flutter run` directly gives you an app
# that cannot reach the Mac. The API address is compile-time (--dart-define), so
# it has to be passed at launch.

set -e

ROOT="${0:A:h}"

export PATH="$HOME/development/flutter/bin:$HOME/.local/bin:$HOME/.gem/ruby/2.6.0/bin:$PATH"
export LANG=en_US.UTF-8

# Auto-detect the Mac's LAN address. Hotspot and wifi hand out different
# subnets, so hardcoding one guarantees a broken run later.
if [ -z "$MAC_IP" ]; then
  for iface in $(ifconfig -l); do
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    # Skip link-local (169.254.x) — the phone cannot route to it.
    case "$ip" in
      ""|169.254.*) continue ;;
      *) MAC_IP="$ip"; break ;;
    esac
  done
fi

if [ -z "$MAC_IP" ]; then
  echo "✗ No usable LAN address found. Connect to wifi or the iPhone hotspot."
  exit 1
fi

API="http://$MAC_IP:8000/api/v1"
echo "▸ Mac LAN address : $MAC_IP"
echo "▸ API for phone   : $API"

# The API must listen on 0.0.0.0, not just localhost, or the phone cannot reach
# it even with the right address.
if ! curl -s -o /dev/null --max-time 3 "$API/health"; then
  echo "▸ Starting Laravel on 0.0.0.0:8000 …"
  # The static dev PHP build is unstable in multi-worker mode, so run the
  # plain single-process server (≈80ms/request, fast enough for dev). The
  # real cure for "slow store open" is the app-side storefront PREFETCH
  # and the server-side image DOWNSCALING, both of which are always on.
  (cd "$ROOT/Back-end" && nohup php artisan serve --host=0.0.0.0 --port=8000 >/tmp/wasla_api.log 2>&1 &)
  sleep 3
fi

STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "$API/health" || echo "000")
echo "▸ API health      : $STATUS"

if [ "$STATUS" != "200" ]; then
  echo "✗ The phone will not be able to reach the API. Check that Back-end is running."
  exit 1
fi

echo "▸ Store codes you can scan or type into the app:"
(cd "$ROOT/Back-end" && php artisan tinker --execute='
foreach (App\Models\Store::withoutGlobalScopes()->with("merchant")->get() as $s) {
  if ($s->is_published && $s->merchant->status === "approved") {
    echo "    ".$s->public_token."  ".($s->name_en ?: $s->name_ar)."\n";
  }
}' 2>/dev/null | grep -E '^\s{4}[A-Z0-9]{8}') || true

cd "$ROOT/flutter"
exec flutter run -d "${1:-00008110-000478490E7A401E}" --dart-define=WASLA_API_BASE="$API"
