#!/bin/bash
# End-to-end order walkthrough against the local API. Prints PASS/FAIL per step.
API=http://127.0.0.1:8000/api/v1
BE=/Users/abdulazizalsuliman/Desktop/all-in/Back-end
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL  $1  -> $2"; }
# req METHOD PATH [TOKEN] [JSON] -> sets CODE and BODY
req(){ local m=$1 p=$2 t=$3 d=$4; local out
  if [ -n "$d" ]; then out=$(curl -s -o /tmp/e2e_body -w "%{http_code}" -X "$m" "$API$p" -H "Accept: application/json" -H "Content-Type: application/json" ${t:+-H "Authorization: Bearer $t"} --data "$d")
  else out=$(curl -s -o /tmp/e2e_body -w "%{http_code}" -X "$m" "$API$p" -H "Accept: application/json" ${t:+-H "Authorization: Bearer $t"}); fi
  CODE=$out; BODY=$(cat /tmp/e2e_body); }
j(){ echo "$BODY" | jq -r "$1" 2>/dev/null; }
expect(){ # expect CODE label
  if [ "$CODE" = "$1" ]; then ok "$2 [$CODE]"; else bad "$2 [got $CODE, want $1]" "$(echo "$BODY" | head -c 220)"; fi; }
tinker(){ (cd $BE && php artisan tinker --execute="$1" 2>/dev/null | tail -1); }

echo "== A. public storefront =="
req GET /stores/AZRBRGR2; expect 200 "GET store by token (guest)"
STORE_NAME=$(j '.store.name // .store.name_ar'); ITEMS=$(j '[.. | objects | select(has("price") and has("id")) | .id] | unique | length'); echo "       store=$STORE_NAME items_in_payload=$ITEMS"
req GET /stores/azrbrgr2; expect 200 "token case-insensitive (azrbrgr2)"
req GET /stores/ZZZZZZZZ; expect 404 "unknown token -> 404"
req GET /stores/ASTRFCAF; expect 200 "second store (Astrof)"
ASTROF_ITEM=$(j '[.. | objects | select(has("price") and has("id")) | .id] | first')

echo "== B. OTP sign-in =="
PH1="0500000101"; PH2="0500000102"
req POST /auth/otp/request "" "{\"phone\":\"$PH1\"}"; expect 200 "otp request"; echo "       development_mode=$(j .development_mode) masked=$(j .phone)"
req POST /auth/otp/verify "" "{\"phone\":\"$PH1\",\"code\":\"9999\"}"; expect 422 "wrong code refused"
req POST /auth/otp/verify "" "{\"phone\":\"$PH1\",\"code\":\"1111\",\"first_name\":\"اختبار\"}"; expect 200 "fixed code accepted"; T1=$(j .token)
req POST /auth/otp/request "" "{\"phone\":\"$PH2\"}"; req POST /auth/otp/verify "" "{\"phone\":\"$PH2\",\"code\":\"1111\"}"; T2=$(j .token)
[ -n "$T1" ] && [ -n "$T2" ] && ok "two customer tokens" || bad "tokens" "$BODY"
req GET /me "$T1"; expect 200 "GET /me as customer"
req GET /orders "" ; expect 401 "orders without token -> 401"

echo "== C. placing orders =="
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":1,"quantity":2},{"item_id":8,"quantity":1}]}'
expect 201 "pickup order"; O1=$(j .id); echo "       id=$O1 status=$(j .status) subtotal=$(j .subtotal) tax=$(j .tax_amount // .tax) delivery=$(j .delivery_fee) total=$(j .total) number=$(j .order_number // .number)"
SUB=$(j .subtotal); TOT=$(j .total); TAX=$(j '.tax_amount // .tax // 0')
python3 - "$SUB" "$TAX" "$TOT" <<'PY'
import sys; s,t,x=[float(v or 0) for v in sys.argv[1:4]]
print("       math: subtotal", s, "(expect 84.00)", "| tax", t, "| total", x, "=> consistent" if abs(s+t-x)<0.011 or abs(s-x)<0.011 else "=> MISMATCH")
PY
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"dine_in","table_number":"12","items":[{"item_id":2,"quantity":1}]}'
expect 422 "dine_in without party_size refused"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"dine_in","table_number":"12","party_size":3,"items":[{"item_id":2,"quantity":1}]}'
expect 201 "dine_in with party_size"; O2=$(j .id); echo "       party_size in response=$(j .party_size) table=$(j .table_number)"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"delivery","items":[{"item_id":3,"quantity":1}]}'
expect 422 "delivery without address refused"
req POST /me/addresses "$T1" '{"label":"home","address_text":"شارع التحلية، الرياض","details":"شقة 3","latitude":24.7,"longitude":46.7}'; echo "       address create [$CODE] $(echo "$BODY" | head -c 160)"
ADDR=$(j '.id // .data.id')
if [ -n "$ADDR" ] && [ "$ADDR" != "null" ]; then
  req POST /orders "$T1" "{\"store_token\":\"AZRBRGR2\",\"fulfillment_type\":\"delivery\",\"address_id\":$ADDR,\"items\":[{\"item_id\":3,\"quantity\":1}]}"
  expect 201 "delivery order"; O3=$(j .id); echo "       delivery_fee=$(j .delivery_fee) total=$(j .total) (item 44 + fee 15 ± tax)"
  req POST /orders "$T2" "{\"store_token\":\"AZRBRGR2\",\"fulfillment_type\":\"delivery\",\"address_id\":$ADDR,\"items\":[{\"item_id\":3,\"quantity\":1}]}"
  expect 422 "customer B cannot use customer A's address"
else bad "address create" "$BODY"; fi
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"curbside","items":[{"item_id":4,"quantity":1}]}'
expect 422 "curbside without car refused"
req POST /me/cars "$T1" '{"brand":"Toyota Camry","color":"أبيض","plate_letters":"أ ب ج","plate_numbers":"1234"}'; echo "       car create [$CODE] $(echo "$BODY" | head -c 160)"
CAR=$(j '.id // .data.id')
if [ -n "$CAR" ] && [ "$CAR" != "null" ]; then
  req POST /orders "$T1" "{\"store_token\":\"AZRBRGR2\",\"fulfillment_type\":\"curbside\",\"car_id\":$CAR,\"items\":[{\"item_id\":4,\"quantity\":1}]}"; expect 201 "curbside order"; O4=$(j .id)
fi

(cd $BE && php artisan cache:clear >/dev/null 2>&1)
echo "== D. validation / tampering =="
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":999999,"quantity":1}]}'; expect 422 "unknown item id"; echo "       error_code=$(j .error_code)"
req POST /orders "$T1" "{\"store_token\":\"AZRBRGR2\",\"fulfillment_type\":\"pickup\",\"items\":[{\"item_id\":$ASTROF_ITEM,\"quantity\":1}]}"; expect 422 "item from ANOTHER store (Astrof id $ASTROF_ITEM)"; echo "       error_code=$(j .error_code)"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":1,"quantity":0}]}'; expect 422 "quantity 0"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":1,"quantity":51}]}'; expect 422 "quantity 51"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[]}'; expect 422 "empty items"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":1,"quantity":1,"price":0.01}]}'; expect 201 "client-sent price ignored"; echo "       total=$(j .total) (must be 34 ± tax, not 0.01)"; OX=$(j .id)
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":1,"quantity":1,"option_ids":[999999]}]}'; echo "       bogus option id -> [$CODE] $(j .error_code)"; [ "$CODE" = "422" ] && ok "bogus option refused" || bad "bogus option NOT refused" "$CODE"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","branch_id":999999,"items":[{"item_id":1,"quantity":1}]}'; echo "       foreign branch_id -> [$CODE] branch=$(j '.branch.name // .branch_id // .branch')"; [ "$CODE" = "201" ] && echo "       NOTE: silently fell back to the default branch (logic issue if branch must be chosen explicitly)"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","party_size":4,"items":[{"item_id":1,"quantity":1}]}'; echo "       party_size on pickup -> [$CODE] party_size=$(j .party_size)"

(cd $BE && php artisan cache:clear >/dev/null 2>&1)
echo "== E. merchant-side switches =="
tinker 'App\Models\BookingSettings::where("store_id",1)->update(["order_curbside"=>false]);' >/dev/null
req POST /orders "$T1" "{\"store_token\":\"AZRBRGR2\",\"fulfillment_type\":\"curbside\",\"car_id\":${CAR:-1},\"items\":[{\"item_id\":4,\"quantity\":1}]}"; expect 422 "curbside disabled by merchant"; echo "       error_code=$(j .error_code)"
tinker 'App\Models\BookingSettings::where("store_id",1)->update(["order_curbside"=>true]);' >/dev/null
tinker 'App\Models\MenuItem::whereKey(1)->update(["is_available"=>false]);' >/dev/null
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":1,"quantity":1}]}'; expect 422 "unavailable (sold-out) item refused"; echo "       error_code=$(j .error_code)"
tinker 'App\Models\MenuItem::whereKey(1)->update(["is_available"=>true]);' >/dev/null
DOW=$(date -u +%w)
tinker "App\Models\BranchSchedule::where('branch_id',1)->where('day_of_week',$DOW)->update(['is_closed'=>true]);" >/dev/null
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":1,"quantity":1}]}'; echo "       store CLOSED today -> [$CODE] $(j .error_code)"; [ "$CODE" = "422" ] && ok "closed store refuses orders" || bad "closed store still accepts orders" "$CODE"
tinker "App\Models\BranchSchedule::where('branch_id',1)->where('day_of_week',$DOW)->update(['is_closed'=>false]);" >/dev/null
req GET /stores/AZRBRGR2; echo "       is_open now=$(j '.store.is_open')"
tinker 'App\Models\Store::whereKey(1)->update(["is_published"=>false]);' >/dev/null
req GET /stores/AZRBRGR2; expect 404 "unpublished store hidden"
req POST /orders "$T1" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":1,"quantity":1}]}'; expect 404 "order to unpublished store refused"
tinker 'App\Models\Store::whereKey(1)->update(["is_published"=>true]);' >/dev/null

(cd $BE && php artisan cache:clear >/dev/null 2>&1)
echo "== F. reading / isolation / cancel =="
req GET "/orders?filter=active" "$T1"; expect 200 "active orders list"; echo "       count=$(j '.data | length') first_status=$(j '.data[0].status')"
req GET "/orders/$O3" "$T1"; echo "       pending order exposes invoice? $(j '.invoice != null')  prep_minutes=$(j .prep_minutes)"
req GET "/orders/$O1" "$T1"; expect 200 "GET own order (unwrapped)"; [ "$(j .id)" = "$O1" ] && ok "unwrapped shape (.id present)" || bad "shape" "$(echo "$BODY" | head -c 120)"
req GET "/orders/$O1" "$T2"; expect 404 "customer B cannot read A's order"
req POST "/orders/$O1/cancel" "$T2"; expect 404 "customer B cannot cancel A's order"
req POST "/orders/$O4/cancel" "$T1"; expect 200 "customer cancels pending order"; echo "       status=$(j .status)"
req POST "/orders/$O4/cancel" "$T1"; expect 422 "cancel twice refused"

echo "== G. merchant lifecycle =="
PW=$(cd $BE && php -r 'require "vendor/autoload.php"; $d=Dotenv\Dotenv::createImmutable(".")->safeLoad(); echo $_ENV["SEED_OWNER_PASSWORD"] ?? "password";')
req POST /auth/login "" "{\"email\":\"owner@azir.sa\",\"password\":\"$PW\"}"; expect 200 "merchant login"; TM=$(j .token)
req GET "/merchant/orders?filter=active" "$TM"; expect 200 "merchant active queue"; echo "       count=$(j '.data | length') contains O1? $(j "[.data[].id] | index($O1) != null")"
req POST "/merchant/orders/$O1/status" "$TM" '{"status":"ready"}'; expect 422 "pending -> ready illegal"
req POST "/merchant/orders/$O1/status" "$TM" '{"status":"accepted","prep_minutes":15}'; expect 200 "accept with prep 15"; echo "       status=$(j .order.status) prep=$(j .order.prep_minutes) accepted_at=$(j .order.accepted_at) ready_at=$(j .order.ready_at) allowed=$(j '.allowed_transitions|join(",")')"
req POST "/orders/$O1/cancel" "$T1"; expect 422 "customer cannot cancel after accept"
req POST "/merchant/orders/$O1/status" "$TM" '{"status":"preparing"}'; expect 200 "accepted -> preparing"
req POST "/merchant/orders/$O1/status" "$TM" '{"status":"ready"}'; expect 200 "preparing -> ready"
req POST "/merchant/orders/$O1/status" "$TM" '{"status":"completed"}'; expect 200 "ready -> completed"
req POST "/merchant/orders/$O1/status" "$TM" '{"status":"accepted"}'; expect 422 "completed -> accepted illegal"
req POST "/merchant/orders/$O4/status" "$TM" '{"status":"accepted"}'; expect 422 "accept a cancelled order illegal"
req POST "/merchant/orders/$O2/status" "$TM" '{"status":"rejected","reason":"نفاد المخزون"}'; expect 200 "reject with reason"; echo "       status=$(j .order.status) reason=$(j .order.rejection_reason)"
req GET "/orders/$O1" "$T1"; echo "       customer sees O1 status=$(j .status) invoice=$(j '.invoice // .invoice_url // "n/a"' | head -c 40)"
req GET "/orders?filter=past" "$T1"; echo "       past list count=$(j '.data | length')"
# cross-tenant: Astrof's owner must not touch Azir's order
PW2=$(cd $BE && grep -o "env('ASTROF_OWNER_PASSWORD', '[^']*')" database/seeders/AstrofRoasterySeeder.php | sed "s/.*, '\(.*\)')/\1/")
req POST /auth/login "" "{\"email\":\"owner@astrof.sa\",\"password\":\"${PW2:-password}\"}"; echo "       astrof login [$CODE]"; TA=$(j .token)
if [ -n "$TA" ] && [ "$TA" != "null" ]; then req POST "/merchant/orders/$O3/status" "$TM2$TA" '{"status":"accepted"}'; [ "$CODE" = "403" ] || [ "$CODE" = "404" ] && ok "other merchant cannot act on this order [$CODE]" || bad "TENANT LEAK: other merchant acted on order" "$CODE $BODY"; fi

echo "== H. notifications (queue) =="
(cd $BE && php artisan queue:work --stop-when-empty 2>&1 | grep -c "DONE" | sed 's/^/       jobs processed: /')
req GET /me/notifications "$T1"; expect 200 "customer inbox"; echo "       count=$(j '.data | length') latest=$(j '.data[0].title // .data[0].type // .data[0].body' | head -c 80)"

(cd $BE && php artisan cache:clear >/dev/null 2>&1)
echo "== I. double submit (same payload twice, in parallel) =="
B='{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":9,"quantity":1}]}'
curl -s -o /tmp/e2e_d1 -w "%{http_code}\n" -X POST "$API/orders" -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $T1" --data "$B" &
curl -s -o /tmp/e2e_d2 -w "%{http_code}\n" -X POST "$API/orders" -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $T1" --data "$B" &
wait; echo "       ids: $(jq -r .id /tmp/e2e_d1) / $(jq -r .id /tmp/e2e_d2)  (two orders = expected without an idempotency key; the app reconciles client-side)"

(cd $BE && php artisan cache:clear >/dev/null 2>&1)
echo "== J. rate limit (10/min on POST /orders) =="
C429=0; for i in $(seq 1 12); do req POST /orders "$T2" '{"store_token":"AZRBRGR2","fulfillment_type":"pickup","items":[{"item_id":10,"quantity":1}]}'; [ "$CODE" = "429" ] && C429=$((C429+1)); done; [ $C429 -gt 0 ] && ok "throttle kicks in (429 x$C429 of 12)" || bad "no 429 after 12 rapid orders" ""


(cd $BE && php artisan cache:clear >/dev/null 2>&1)
echo "== K. delivery pricing by distance =="
# Local fixtures: pin the Azir branch, switch the store to per-km pricing with a 25 km radius.
tinker "\$s=App\Models\Store::withoutGlobalScopes()->where('public_token','AZRBRGR2')->first(); \$s->branches()->update(['latitude'=>24.8120,'longitude'=>46.7580]); App\Models\BookingSettings::withoutGlobalScopes()->where('store_id',\$s->id)->update(['delivery_pricing_mode'=>'per_km','delivery_base_fee'=>5,'delivery_fee_per_km'=>2,'delivery_max_distance_km'=>25,'delivery_road_factor'=>1.3]); echo 'ok';" >/dev/null
req GET "/stores/AZRBRGR2"; [ "$(j .configuration.delivery_pricing_mode)" = "per_km" ] && ok "storefront exposes pricing mode per_km" || bad "storefront pricing mode" "$(j .configuration.delivery_pricing_mode)"
req GET "/me/delivery-quote?store_token=AZRBRGR2&address_id=$ADDR" "$T1"; expect 200 "quote for a nearby address"
QFEE=$(j .fee); QKM=$(j .distance_km); echo "       allowed=$(j .allowed) mode=$(j .mode) distance_km=$QKM fee=$QFEE"
[ "$(j .allowed)" = "true" ] && ok "nearby address is allowed" || bad "nearby address refused" "$BODY"
req POST /me/addresses "$T1" '{"label":"other","address_text":"الخرج","latitude":24.15,"longitude":47.30}'; FAR=$(j '.id // .data.id')
req GET "/me/delivery-quote?store_token=AZRBRGR2&address_id=$FAR" "$T1"; expect 200 "quote for a far address"
[ "$(j .allowed)" = "false" ] && [ "$(j .reason)" = "OUT_OF_RANGE" ] && ok "far address reported out of range ($(j .distance_km) km > $(j .max_distance_km))" || bad "far address not refused" "$BODY"
req POST /orders "$T1" "{\"store_token\":\"AZRBRGR2\",\"fulfillment_type\":\"delivery\",\"address_id\":$FAR,\"items\":[{\"item_id\":3,\"quantity\":1}]}"; expect 422 "ordering to the far address refused"; echo "       code=$(j .error_code)"
req POST /orders "$T1" "{\"store_token\":\"AZRBRGR2\",\"fulfillment_type\":\"delivery\",\"address_id\":$ADDR,\"items\":[{\"item_id\":3,\"quantity\":1}]}"; expect 201 "delivery order to the nearby address"; OD=$(j .id)
[ "$(j .delivery_fee)" = "$QFEE" ] && ok "order fee equals the quote ($QFEE)" || bad "fee mismatch" "order=$(j .delivery_fee) quote=$QFEE"
[ "$(j .delivery.distance_km)" = "$QKM" ] && ok "distance snapshotted on the order ($QKM km)" || bad "distance not snapshotted" "$(j .delivery)"
req DELETE "/me/addresses/$FAR" "$T1" >/dev/null 2>&1

echo "== L. driver app =="
tinker "App\Models\Driver::withoutTenancy()->where('phone','like','+96655999000%')->get()->each(function(\$d){ \$d->user?->delete(); \$d->delete(); }); echo 'ok';" >/dev/null
req POST /merchant/drivers "$TM" '{"name":"سعد السائق","phone":"0559990001","password":"driver-pass-1","vehicle":"دراجة"}'; expect 201 "merchant creates driver 1"; D1=$(j .id)
req POST /merchant/drivers "$TM" '{"name":"فهد السائق","phone":"0559990002","password":"driver-pass-2"}'; expect 201 "merchant creates driver 2"; D2=$(j .id)
req POST /merchant/drivers "$TM" '{"name":"مكرر","phone":"0559990001","password":"driver-pass-3"}'; expect 422 "duplicate driver phone refused"
req GET /merchant/drivers "$TM"; expect 200 "merchant lists drivers"; echo "       count=$(j '.data|length')"
req POST /auth/driver/login "" '{"phone":"0559990001","password":"nope"}'; expect 422 "driver wrong password"
req POST /auth/driver/login "" '{"phone":"0559990001","password":"driver-pass-1","device_name":"e2e"}'; expect 200 "driver 1 login"; TD1=$(j .token)
req POST /auth/driver/login "" '{"phone":"0559990002","password":"driver-pass-2"}'; expect 200 "driver 2 login"; TD2=$(j .token)
req POST /auth/login "" '{"email":"'"$(tinker "echo App\Models\Driver::withoutTenancy()->find($D1)->user->email;")"'","password":"driver-pass-1"}'; expect 422 "driver cannot use the dashboard login"
req GET /merchant/orders "$TD1"; expect 403 "driver token blocked from merchant routes"
req GET /driver/me "$TD1"; expect 200 "driver profile"; echo "       store=$(j .store.name) driver=$(j .driver.name)"
req GET "/driver/orders?filter=available" "$TD1"; [ "$(j "[.data[].id] | index($OD)")" = "null" ] && ok "placed order not yet on the driver board" || bad "placed order visible to drivers" ""
req POST "/driver/orders/$OD/claim" "$TD1"; expect 422 "claim before acceptance refused"
req POST "/merchant/orders/$OD/status" "$TM" '{"status":"accepted","prep_minutes":10}'; expect 200 "merchant accepts the delivery order"
req GET "/driver/orders?filter=available" "$TD1"; [ "$(j "[.data[].id] | index($OD)")" != "null" ] && ok "accepted order on the driver board (customer=$(j '.data[0].customer.name // "?"') lat=$(j '.data[0].delivery.latitude'))" || bad "accepted order missing from board" "$BODY"
req POST "/driver/orders/$OD/claim" "$TD1"; expect 200 "driver 1 claims"; echo "       driver=$(j .driver.name) assigned_at=$(j .assigned_at)"
req POST "/driver/orders/$OD/claim" "$TD2"; expect 409 "driver 2 claim refused (already taken)"
req GET "/driver/orders/$OD" "$TD2"; expect 404 "driver 2 cannot open driver 1's order"
req POST "/driver/orders/$OD/status" "$TD1" '{"status":"out_for_delivery"}'; expect 422 "pickup before ready is illegal"
req GET "/orders/$OD/tracking" "$T1"; expect 200 "customer tracking (assigned, not moving)"; echo "       driver=$(j .driver.name) location=$(j .driver_location)"
req POST "/merchant/orders/$OD/status" "$TM" '{"status":"ready"}'; expect 200 "kitchen marks ready"
req POST "/driver/orders/$OD/status" "$TD1" '{"status":"out_for_delivery"}'; expect 200 "driver picks up -> out_for_delivery"
req POST /driver/location "$TD1" '{"latitude":24.80,"longitude":46.75,"heading":120,"speed_kmh":35}'; expect 200 "driver heartbeat"
req GET "/orders/$OD/tracking" "$T1"; expect 200 "customer tracking while moving"
[ "$(j .driver_location.latitude)" = "24.8" ] && ok "customer sees the driver's position (eta=$(j .eta_minutes) min, fresh=$(j .driver_location.fresh))" || bad "no driver position for customer" "$BODY"
req GET "/merchant/orders/$OD/tracking" "$TM"; expect 200 "merchant tracking"
req GET "/orders/$OD/tracking" "$T2"; expect 404 "another customer cannot track this order"
if [ -n "$TA" ] && [ "$TA" != "null" ]; then req GET "/merchant/orders/$OD/tracking" "$TA"; [ "$CODE" = "403" ] || [ "$CODE" = "404" ] && ok "other merchant cannot track this order [$CODE]" || bad "TENANT LEAK: other merchant tracked order" "$CODE"; fi
req POST "/driver/orders/$OD/status" "$TD1" '{"status":"completed"}'; expect 200 "driver hands over -> completed"
req GET "/orders/$OD/tracking" "$T1"; [ "$(j .driver_location)" = "null" ] && [ "$(j .status)" = "completed" ] && ok "position hidden after completion" || bad "position still exposed" "$BODY"
req GET "/driver/orders?filter=past" "$TD1"; [ "$(j "[.data[].id] | index($OD)")" != "null" ] && ok "run listed under driver's past" || bad "run missing from past" ""
req PUT "/merchant/drivers/$D2" "$TM" '{"is_active":false}'; expect 200 "merchant deactivates driver 2"
req GET /driver/me "$TD2"; expect 401 "deactivated driver's token revoked"
req DELETE "/merchant/drivers/$D1" "$TM"; expect 200 "merchant deletes driver 1"
req GET "/orders/$OD" "$T1"; [ "$(j .status)" = "completed" ] && ok "order history survives driver deletion" || bad "order lost" ""
(cd $BE && php artisan queue:work --stop-when-empty 2>&1 | grep -c "DONE" | sed 's/^/       jobs processed: /')
req GET /me/notifications "$T1"; [ "$(j '[.data[].title] | index("طلبك في الطريق")')" != "null" ] && ok "customer got the on-its-way notification" || bad "no on-its-way notification" "$(j '[.data[].title]')"
# restore the store's pricing for the next run
tinker "\$s=App\Models\Store::withoutGlobalScopes()->where('public_token','AZRBRGR2')->first(); App\Models\BookingSettings::withoutGlobalScopes()->where('store_id',\$s->id)->update(['delivery_pricing_mode'=>'fixed','delivery_max_distance_km'=>0]); echo 'ok';" >/dev/null

echo; echo "RESULT: $PASS passed, $FAIL failed"
