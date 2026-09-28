<?php

/*
 * قوالب الإشعارات (المواصفة §23، §33)
 */
return [
    'booking_confirmed' => [
        'title' => 'تم تأكيد الحجز',
        'body' => 'تم تأكيد موعدك في :store_name يوم :date الساعة :time.',
    ],
    'booking_cancelled' => [
        'title' => 'تم إلغاء الحجز',
        'body' => 'تم إلغاء موعدك في :store_name يوم :date.',
    ],
    'booking_rescheduled' => [
        'title' => 'تم تغيير الموعد',
        'body' => 'موعدك في :store_name أصبح يوم :date الساعة :time.',
    ],
    'booking_reminder' => [
        'title' => 'تذكير بموعدك',
        'body' => 'نراك في :store_name الساعة :time لخدمة :service_name.',
    ],
    'booking_completed' => [
        'title' => 'شكراً لزيارتك',
        'body' => 'شكراً لزيارتك :store_name. نتطلع لرؤيتك مرة أخرى.',
    ],

    // طلبات المطاعم (§23)
    'order_accepted' => [
        'title' => 'تم قبول طلبك',
        'body' => 'قبل :store_name طلبك رقم :reference وسيبدأ التحضير.',
    ],
    'order_preparing' => [
        'title' => 'جاري تحضير طلبك',
        'body' => 'بدأ :store_name بتحضير طلبك رقم :reference.',
    ],
    'order_ready' => [
        'title' => 'طلبك جاهز',
        'body' => 'طلبك رقم :reference جاهز في :store_name.',
    ],
    'order_completed' => [
        'title' => 'تم تسليم طلبك',
        'body' => 'تم تسليم طلبك رقم :reference. شكراً لطلبك من :store_name.',
    ],
    'order_rejected' => [
        'title' => 'تعذّر قبول طلبك',
        'body' => 'نعتذر، لم يتمكن :store_name من قبول طلبك رقم :reference.',
    ],
    'order_cancelled' => [
        'title' => 'تم إلغاء طلبك',
        'body' => 'تم إلغاء طلبك رقم :reference في :store_name.',
    ],
];
