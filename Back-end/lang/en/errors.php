<?php

/*
 * API error messages (spec §33 — nothing hard-coded in code paths).
 * Clients switch on `error_code`, never on these strings.
 */
return [
    'unauthenticated' => 'You need to sign in to continue.',
    'forbidden' => 'You do not have permission to do that.',
    'not_found' => 'Not found.',
    'account_disabled' => 'This account has been disabled.',

    'no_merchant_context' => 'This account is not linked to a business.',
    'merchant_not_active' => 'This business is not active yet.',

    'invalid_status_transition' => 'This booking cannot be changed to that status.',
    'slot_taken' => 'Sorry, that time was just booked. Please choose another.',
    'slot_unavailable' => 'That time is not available.',
    'cancellation_deadline_passed' => 'It is too late to cancel this booking.',
    'reschedule_deadline_passed' => 'It is too late to reschedule this booking.',
    'cancellation_not_allowed' => 'This business does not allow online cancellation.',
    'reschedule_not_allowed' => 'This business does not allow online rescheduling.',

    'store_unavailable' => 'This store is not available right now.',
    'invalid_store_code' => 'We could not find a store with that code.',

    'otp_invalid' => 'That code is not correct.',
    'otp_expired' => 'That code has expired. Please request a new one.',
    'otp_throttled' => 'Too many attempts. Please try again shortly.',
    'fulfillment_unavailable' => 'That order method is currently unavailable.',
    'order_not_placeable' => 'Could not place the order. Check your cart and try again.',
    'order_not_cancellable' => 'The order can no longer be cancelled once the restaurant accepts it.',
];
