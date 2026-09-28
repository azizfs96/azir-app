<?php

/*
 * CORS (spec §37).
 *
 * Needed so the Flutter WEB build and the React dashboard can call the API from
 * a different origin during development. Native iOS/Android builds are not
 * subject to CORS at all.
 *
 * Tighten allowed_origins to the real dashboard host before production.
 */
return [
    'paths' => ['api/*'],
    'allowed_methods' => ['*'],
    'allowed_origins' => [env('CORS_ALLOWED_ORIGINS', '*')],
    'allowed_origins_patterns' => [],
    'allowed_headers' => ['*'],
    'exposed_headers' => [],
    'max_age' => 0,
    'supports_credentials' => false,
];
