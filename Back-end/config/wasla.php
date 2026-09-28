<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Locale & regional defaults
    |--------------------------------------------------------------------------
    | Arabic-first (spec §32, §33). Saudi Arabia observes no DST, but every
    | calculation is written DST-correct so expansion does not break it.
    */

    'default_timezone' => env('WASLA_DEFAULT_TIMEZONE', 'Asia/Riyadh'),
    'default_currency' => env('WASLA_DEFAULT_CURRENCY', 'SAR'),
    'supported_locales' => ['ar', 'en'],

    /*
    |--------------------------------------------------------------------------
    | Deep links & QR (spec §7, §24, §38)
    |--------------------------------------------------------------------------
    | A store's QR encodes {web_url}{store_link_path}/{public_token},
    | e.g. https://wasla.sa/s/8F72K
    */

    'web_url' => env('WASLA_WEB_URL', 'https://wasla.sa'),
    'store_link_path' => env('WASLA_STORE_LINK_PATH', '/s'),

    'ios_app_id' => env('WASLA_IOS_APP_ID', ''),
    'android_package' => env('WASLA_ANDROID_PACKAGE', 'sa.wasla.app'),

    // How long a deferred deep-link fingerprint stays claimable (§8.3).
    'attribution_ttl_minutes' => (int) env('WASLA_ATTRIBUTION_TTL_MINUTES', 60),

    /*
    |--------------------------------------------------------------------------
    | OTP (spec §34)
    |--------------------------------------------------------------------------
    */

    'otp' => [
        'length' => (int) env('WASLA_OTP_LENGTH', 4),
        'ttl_seconds' => (int) env('WASLA_OTP_TTL_SECONDS', 300),
        'max_attempts' => (int) env('WASLA_OTP_MAX_ATTEMPTS', 5),

        // 'log' writes the code to the log instead of sending an SMS. Swap for a
        // real provider (Unifonic / Msegat / Taqnyat) when one is chosen.
        'driver' => env('SMS_DRIVER', 'log'),

        /*
        |----------------------------------------------------------------------
        | Fixed development code
        |----------------------------------------------------------------------
        |
        | While no SMS provider is integrated, every OTP is this code so the
        | apps can be driven end to end without a real message being sent.
        |
        | ⚠️  THIS MUST BE NULL IN PRODUCTION. A fixed code means anyone who
        |     knows a phone number can sign in as that person. OtpService
        |     refuses to use it when app.env is production — see the guard
        |     there — but set WASLA_OTP_FIXED_CODE=null explicitly anyway.
        |
        | Set to null to restore random codes.
        */
        'fixed_code' => env('WASLA_OTP_FIXED_CODE', '1111'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Booking engine defaults (spec §17)
    |--------------------------------------------------------------------------
    */

    'booking' => [
        'slot_interval_minutes' => (int) env('WASLA_SLOT_INTERVAL_MINUTES', 15),
        'availability_cache_seconds' => (int) env('WASLA_AVAILABILITY_CACHE_SECONDS', 60),
    ],

    /*
    |--------------------------------------------------------------------------
    | Payments (spec §20) — ONLINE PAYMENT IS OUT OF SCOPE FOR THE MVP
    |--------------------------------------------------------------------------
    |
    | Decision (2026-08-15): no payment provider and no ZATCA e-invoicing for
    | now. Every booking is pay-at-store.
    |
    | `online_enabled` is a platform kill switch, not a merchant setting. While
    | it is false the booking engine forces every flow to 'pay_at_store' even if
    | a store row has payment_required = true — because a toggle with no
    | implementation behind it is a trap, not a feature.
    |
    | The payments table, Payment model and PaymentProviderInterface stay in
    | place; spec §20 asks for an extensible architecture, and keeping the seam
    | costs nothing. Turning this on later means writing one provider class and
    | flipping this flag.
    |
    | NOTE: enabling this in Saudi Arabia also requires 15% VAT handling and
    | ZATCA Phase 2 e-invoicing (cryptographic stamping + Fatoora). That is a
    | subsystem, not a line item — budget for it before flipping the switch.
    */

    'payments' => [
        'online_enabled' => env('PAYMENT_ONLINE_ENABLED', false),
        'driver' => env('PAYMENT_DRIVER', 'manual'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Business engines (ARCHITECTURE.md §2)
    |--------------------------------------------------------------------------
    | Only Beauty & Wellness ships in the MVP. Future verticals register here;
    | no core table or code changes (spec §44).
    */

    'engines' => [
        'beauty_wellness' => \App\Engines\BeautyWellness\BeautyWellnessEngine::class,
        'restaurant' => \App\Engines\Restaurant\RestaurantEngine::class,
    ],

    'default_engine' => 'beauty_wellness',

];
