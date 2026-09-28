<?php

/*
 * Notification templates (spec §23, §33).
 * Stored as template_key + payload, rendered per reader's locale.
 */
return [
    'booking_confirmed' => [
        'title' => 'Booking confirmed',
        'body' => 'Your appointment at :store_name is confirmed for :date at :time.',
    ],
    'booking_cancelled' => [
        'title' => 'Booking cancelled',
        'body' => 'Your appointment at :store_name on :date has been cancelled.',
    ],
    'booking_rescheduled' => [
        'title' => 'Booking moved',
        'body' => 'Your appointment at :store_name is now :date at :time.',
    ],
    'booking_reminder' => [
        'title' => 'Appointment reminder',
        'body' => 'See you at :store_name at :time for :service_name.',
    ],
    'booking_completed' => [
        'title' => 'Thanks for visiting',
        'body' => 'Thanks for visiting :store_name. See you next time.',
    ],

    // Restaurant orders (§23)
    'order_accepted' => [
        'title' => 'Order accepted',
        'body' => ':store_name accepted your order :reference and will start preparing it.',
    ],
    'order_preparing' => [
        'title' => 'Preparing your order',
        'body' => ':store_name has started preparing order :reference.',
    ],
    'order_ready' => [
        'title' => 'Your order is ready',
        'body' => 'Order :reference is ready at :store_name.',
    ],
    'order_completed' => [
        'title' => 'Order delivered',
        'body' => 'Order :reference is complete. Thanks for ordering from :store_name.',
    ],
    'order_rejected' => [
        'title' => "Order couldn't be accepted",
        'body' => "Sorry, :store_name couldn't accept order :reference.",
    ],
    'order_cancelled' => [
        'title' => 'Order cancelled',
        'body' => 'Order :reference at :store_name has been cancelled.',
    ],
];
