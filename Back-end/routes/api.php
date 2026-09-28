<?php

use App\Http\Controllers\Api\V1\Admin\MerchantController as AdminMerchantController;
use App\Http\Controllers\Api\V1\Admin\MetricsController;
use App\Http\Controllers\Api\V1\Auth\MerchantAuthController;
use App\Http\Controllers\Api\V1\Auth\OtpController;
use App\Http\Controllers\Api\V1\Customer\AddressController;
use App\Http\Controllers\Api\V1\Customer\BookingController;
use App\Http\Controllers\Api\V1\Customer\OrderController as CustomerOrderController;
use App\Http\Controllers\Api\V1\Customer\MyStoresController;
use App\Http\Controllers\Api\V1\Merchant\BookingController as MerchantBookingController;
use App\Http\Controllers\Api\V1\Merchant\OrderController as MerchantOrderController;
use App\Http\Controllers\Api\V1\Merchant\BranchController;
use App\Http\Controllers\Api\V1\Merchant\CustomerController;
use App\Http\Controllers\Api\V1\Merchant\DashboardController;
use App\Http\Controllers\Api\V1\Merchant\MediaController;
use App\Http\Controllers\Api\V1\Merchant\OnboardingController;
use App\Http\Controllers\Api\V1\Merchant\QrController;
use App\Http\Controllers\Api\V1\Merchant\ServiceCategoryController;
use App\Http\Controllers\Api\V1\Merchant\ServiceController;
use App\Http\Controllers\Api\V1\Merchant\SettingsController;
use App\Http\Controllers\Api\V1\Merchant\MenuCategoryController;
use App\Http\Controllers\Api\V1\Merchant\MenuItemController;
use App\Http\Controllers\Api\V1\Merchant\StaffController;
use App\Http\Controllers\Api\V1\Merchant\TimeOffController;
use App\Http\Controllers\Api\V1\PublicApi\AvailabilityController;
use App\Http\Controllers\Api\V1\PublicApi\DeepLinkController;
use App\Http\Controllers\Api\V1\PublicApi\StoreController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Wasla API v1  (prefix applied in bootstrap/app.php: /api/v1)
|--------------------------------------------------------------------------
|
| Namespaces and guards (ARCHITECTURE.md §7):
|
|   public    — no auth. Store resolution by public_token, availability.
|   auth      — OTP (customer) and password (merchant/admin).
|   customer  — role:customer. My Stores + bookings.
|   merchant  — role:merchant_owner,merchant_staff + tenant + approved.
|   admin     — role:admin.
|
| NOTE ON WHAT IS DELIBERATELY ABSENT (spec §46):
|   There is no GET /stores, no /search, no /nearby, no /categories, and no
|   /merchants listing for customers. Wasla is not a marketplace, and the
|   missing routes are the enforcement — not a filter someone can remove.
|
*/

Route::get('/health', fn () => response()->json([
    'status' => 'ok',
    'service' => 'wasla-api',
    'version' => 'v1',
]));

/*
|--------------------------------------------------------------------------
| Public — no authentication (spec §6, §7, §31)
|--------------------------------------------------------------------------
|
| Scanning a salon's window should show the storefront immediately. Signing in
| is required only to BOOK (spec §41).
|
| Rate limited per §7.6 so the 8-character token space cannot be enumerated.
*/

Route::middleware('throttle:60,1')->group(function (): void {
    // THE QR RESOLUTION ENDPOINT. This is what a scan hits.
    Route::get('/stores/{token}', [StoreController::class, 'show']);
    Route::get('/stores/{token}/services', [StoreController::class, 'services']);
    Route::get('/stores/{token}/availability', [AvailabilityController::class, 'index']);

    // Deferred deep linking — surviving the App Store round trip (§7).
    Route::post('/deep-link/record', [DeepLinkController::class, 'record']);
    Route::post('/deep-link/claim', [DeepLinkController::class, 'claim']);
});

/*
|--------------------------------------------------------------------------
| Authentication (spec §34)
|--------------------------------------------------------------------------
*/

Route::prefix('auth')->group(function (): void {
    // Customer: phone + OTP. No password anywhere in this flow.
    Route::post('/otp/request', [OtpController::class, 'request']);
    Route::post('/otp/verify', [OtpController::class, 'verify']);

    // Merchant / admin: email + password.
    Route::post('/login', [MerchantAuthController::class, 'login']);

    // Business registration (spec §11 step 1). Public.
    Route::post('/merchant/register', [OnboardingController::class, 'register'])
        ->middleware('throttle:5,60');

    Route::middleware('auth:sanctum')->group(function (): void {
        Route::get('/me', [MerchantAuthController::class, 'me']);
        Route::patch('/me/locale', [MerchantAuthController::class, 'updateLocale']);
        Route::post('/logout', [MerchantAuthController::class, 'logout']);
    });
});

/*
|--------------------------------------------------------------------------
| Customer  (Phase 5 — My Stores, bookings)
|--------------------------------------------------------------------------
*/

Route::middleware(['auth:sanctum', 'role:customer'])->group(function (): void {
    // My Stores — the home screen, and the ONLY discovery surface (§5, §46).
    Route::get('/me', [\App\Http\Controllers\Api\V1\Customer\ProfileController::class, 'me']);
    Route::get('/me/stores', [MyStoresController::class, 'index']);
    Route::post('/me/stores', [MyStoresController::class, 'store']);
    Route::delete('/me/stores/{token}', [MyStoresController::class, 'destroy']);

    // Central delivery addresses — managed once, reused at every store.
    Route::get('/me/addresses', [AddressController::class, 'index']);
    Route::post('/me/addresses', [AddressController::class, 'store']);
    Route::put('/me/addresses/{id}', [AddressController::class, 'update']);
    Route::delete('/me/addresses/{id}', [AddressController::class, 'destroy']);

    // Saved cars for curbside pickup ("من السيارة").
    Route::get('/me/cars', [\App\Http\Controllers\Api\V1\Customer\CarController::class, 'index']);
    Route::post('/me/cars', [\App\Http\Controllers\Api\V1\Customer\CarController::class, 'store']);
    Route::delete('/me/cars/{id}', [\App\Http\Controllers\Api\V1\Customer\CarController::class, 'destroy']);

    // The in-app inbox.
    Route::get('/me/notifications', [\App\Http\Controllers\Api\V1\Customer\NotificationController::class, 'index']);
    Route::post('/me/notifications/{id}/read', [\App\Http\Controllers\Api\V1\Customer\NotificationController::class, 'read']);

    // Push registrations (FCM).
    Route::post('/me/device-tokens', [\App\Http\Controllers\Api\V1\Customer\DeviceTokenController::class, 'store']);
    Route::delete('/me/device-tokens', [\App\Http\Controllers\Api\V1\Customer\DeviceTokenController::class, 'destroy']);

    Route::get('/bookings', [BookingController::class, 'index']);
    Route::get('/bookings/{id}', [BookingController::class, 'show']);
    Route::post('/bookings', [BookingController::class, 'store'])->middleware('throttle:10,1');
    Route::post('/bookings/{id}/cancel', [BookingController::class, 'cancel']);
    Route::post('/bookings/{id}/reschedule', [BookingController::class, 'reschedule']);

    // Restaurant orders (RestaurantEngine, R3).
    Route::get('/orders', [CustomerOrderController::class, 'index']);
    Route::get('/orders/{id}', [CustomerOrderController::class, 'show']);
    Route::post('/orders', [CustomerOrderController::class, 'store'])->middleware('throttle:10,1');
    Route::post('/orders/{id}/cancel', [CustomerOrderController::class, 'cancel']);
});

/*
|--------------------------------------------------------------------------
| Merchant  (Phase 3 — CRUD, dashboard)
|--------------------------------------------------------------------------
*/

/*
 * Onboarding sits OUTSIDE merchant.approved on purpose: a pending merchant must
 * be able to finish setup and submit for approval (spec §11, §39).
 */
Route::prefix('merchant')
    ->middleware(['auth:sanctum', 'role:merchant_owner,merchant_staff'])
    ->group(function (): void {
        Route::get('/onboarding', [OnboardingController::class, 'show']);
        Route::post('/onboarding/step/{step}', [OnboardingController::class, 'advance']);
        Route::post('/onboarding/publish', [OnboardingController::class, 'publish']);
    });

/*
 * Everything else requires an APPROVED, unsuspended merchant.
 */
Route::prefix('merchant')
    ->middleware(['auth:sanctum', 'role:merchant_owner,merchant_staff', 'merchant.approved'])
    ->group(function (): void {
        Route::get('/dashboard', [DashboardController::class, 'index']);

        Route::get('/customers', [CustomerController::class, 'index']);

        Route::get('/bookings', [MerchantBookingController::class, 'index']);
        Route::post('/bookings/{id}/status', [MerchantBookingController::class, 'updateStatus']);

        Route::get('/orders', [MerchantOrderController::class, 'index']);
        Route::post('/orders/{id}/status', [MerchantOrderController::class, 'updateStatus']);

        Route::apiResource('/services', ServiceController::class)->except(['show']);
        Route::apiResource('/service-categories', ServiceCategoryController::class)->except(['show']);

        // One-off blocked time for a stylist or a whole branch (spec §12).
        Route::get('/time-off', [TimeOffController::class, 'index']);
        Route::post('/time-off', [TimeOffController::class, 'store']);
        Route::delete('/time-off/{id}', [TimeOffController::class, 'destroy']);

        // Restaurant menu (RestaurantEngine) — same tenancy middleware stack.
        Route::apiResource('/menu/categories', MenuCategoryController::class)->except(['show']);
        Route::post('/menu/categories/{id}/image', [MenuCategoryController::class, 'image']);
        Route::apiResource('/menu/items', MenuItemController::class)->except(['show']);
        Route::put('/menu/items/{id}/options', [MenuItemController::class, 'options']);
        Route::post('/menu/items/{id}/image', [MenuItemController::class, 'image']);

        Route::apiResource('/staff', StaffController::class)->except(['show']);
        Route::put('/staff/{id}/schedule', [StaffController::class, 'schedule']);

        Route::apiResource('/branches', BranchController::class)->except(['show']);
        Route::put('/branches/{id}/schedule', [BranchController::class, 'schedule']);

        Route::get('/qr', [QrController::class, 'show']);
        Route::get('/qr/svg', [QrController::class, 'svg']);
        Route::post('/qr/regenerate', [QrController::class, 'regenerate']);

        Route::get('/settings/booking', [SettingsController::class, 'booking']);
        Route::patch('/settings/booking', [SettingsController::class, 'updateBooking']);
        Route::get('/settings/store', [SettingsController::class, 'store']);
        Route::patch('/settings/store', [SettingsController::class, 'updateStore']);

        // Logo and cover (spec §35 secure uploads).
        Route::post('/settings/media', [MediaController::class, 'upload']);
        Route::delete('/settings/media/{type}', [MediaController::class, 'destroy']);
    });

/*
|--------------------------------------------------------------------------
| Admin  (Phase 12)
|--------------------------------------------------------------------------
*/

Route::prefix('admin')
    ->middleware(['auth:sanctum', 'role:admin'])
    ->group(function (): void {
        Route::get('/metrics', [MetricsController::class, 'index']);

        // The approval queue (spec §39). Without this every merchant stays
        // pending forever and no store is ever reachable.
        Route::get('/merchants', [AdminMerchantController::class, 'index']);
        Route::get('/merchants/{id}', [AdminMerchantController::class, 'show']);
        Route::post('/merchants/{id}/approve', [AdminMerchantController::class, 'approve']);
        Route::post('/merchants/{id}/reject', [AdminMerchantController::class, 'reject']);
        Route::post('/merchants/{id}/suspend', [AdminMerchantController::class, 'suspend']);
        Route::post('/merchants/{id}/reinstate', [AdminMerchantController::class, 'reinstate']);
    });
