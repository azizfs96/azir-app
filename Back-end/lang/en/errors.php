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
    'branch_not_found' => 'That branch does not belong to this store. Please choose a branch again.',
    'order_store_closed' => 'The store is closed right now. You can order during opening hours.',
    'order_below_min_order' => 'The amount is below the delivery minimum.',
    'order_item_unavailable' => 'An item in your cart is currently unavailable.',
    'order_option_unavailable' => 'One of the chosen options is currently unavailable.',
    'order_out_of_delivery_range' => 'Your address is outside this branch\'s delivery range.',
    'order_already_taken' => 'Another driver already took this order.',
    'order_not_claimable' => 'This order is not available for delivery right now.',
    'order_not_assignable' => 'A driver cannot be assigned to this order.',
    'order_not_placeable' => 'Could not place the order. Check your cart and try again.',
    'order_not_cancellable' => 'The order can no longer be cancelled once the restaurant accepts it.',
];
