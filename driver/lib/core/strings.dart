import 'package:flutter/widgets.dart';

/// Localization. Arabic is the default and the design baseline; English is
/// secondary. A plain class rather than generated ARB: the dictionary is small
/// and stays readable in one file.
class Strings {
  const Strings(this.locale);

  final Locale locale;

  bool get isArabic => locale.languageCode == 'ar';

  static const supported = [Locale('ar'), Locale('en')];

  static Strings of(BuildContext context) => Strings(Localizations.localeOf(context));

  String _(String ar, String en) => isArabic ? ar : en;

  // Brand
  String get appName => _('Easy App Driver', 'Easy App Driver');
  String get tagline => _('توصيل طلبات متجرك', 'Deliveries for your store');

  // Sign-in
  String get signInTitle => _('تسجيل دخول السائق', 'Driver sign-in');
  String get signInHint => _(
    'استخدم رقم الجوال وكلمة المرور التي أعطاك إياها المتجر.',
    'Use the phone and password your store gave you.',
  );
  String get phone => _('رقم الجوال', 'Phone number');
  String get password => _('كلمة المرور', 'Password');
  String get signIn => _('دخول', 'Sign in');
  String get signInFailed => _('رقم الجوال أو كلمة المرور غير صحيحة.', 'Wrong phone or password.');
  String get accountDisabled =>
      _('حسابك موقوف. تواصل مع المتجر.', 'Your account is disabled. Contact the store.');

  // Board
  String get board => _('الطلبات', 'Orders');
  String get tabAvailable => _('متاحة', 'Available');
  String get tabMine => _('طلباتي', 'Mine');
  String get tabPast => _('السابقة', 'Past');
  String get emptyAvailable => _('لا توجد طلبات توصيل الآن', 'No deliveries right now');
  String get emptyAvailableHint => _(
    'ستظهر هنا طلبات التوصيل التي قبلها المتجر.',
    'Delivery orders accepted by the store will appear here.',
  );
  String get emptyMine => _('لا توجد طلبات مسندة إليك', 'Nothing assigned to you');
  String get emptyMineHint => _('استلم طلباً من قائمة "متاحة".', 'Claim one from "Available".');
  String get emptyPast => _('لا توجد توصيلات سابقة', 'No past deliveries');
  String get refresh => _('تحديث', 'Refresh');
  String get retry => _('إعادة المحاولة', 'Retry');
  String get genericError => _('حدث خطأ. حاول مرة أخرى.', 'Something went wrong. Try again.');
  String get offlineError => _('لا يوجد اتصال بالإنترنت.', 'No internet connection.');

  // Order
  String orderNumber(String ref) => _('طلب #$ref', 'Order #$ref');
  String get customer => _('العميل', 'Customer');
  String get address => _('العنوان', 'Address');
  String get pickupFrom => _('الاستلام من', 'Pick up from');
  String get items => _('الأصناف', 'Items');
  String get total => _('الإجمالي', 'Total');
  String get deliveryFee => _('رسوم التوصيل', 'Delivery fee');
  String get notes => _('ملاحظات العميل', 'Customer notes');
  String get currency => _('ر.س', 'SAR');
  String km(double v) => _('${v.toStringAsFixed(1)} كم', '${v.toStringAsFixed(1)} km');
  String get callCustomer => _('اتصال بالعميل', 'Call customer');
  String get openInMaps => _('افتح في خرائط قوقل', 'Open in Google Maps');
  String get noPin => _('لا يوجد موقع محدد لهذا العنوان.', 'This address has no map pin.');

  // Status (driver's view)
  String status(String s) => switch (s) {
    'placed' => _('جديد', 'New'),
    'accepted' || 'preparing' => _('قيد التجهيز', 'Being prepared'),
    'ready' => _('جاهز للاستلام', 'Ready for pickup'),
    'out_for_delivery' => _('في الطريق', 'On the way'),
    'completed' => _('تم التسليم', 'Delivered'),
    'cancelled' => _('ملغي', 'Cancelled'),
    'rejected' => _('مرفوض', 'Rejected'),
    _ => s,
  };

  // Actions
  String get claim => _('استلام هذا الطلب', 'Take this order');
  String get claimed => _('أصبح الطلب لك', 'The order is yours');
  String get takenByOther => _('استلمه سائق آخر قبلك.', 'Another driver took it first.');
  String get waitingKitchen => _(
    'المطبخ يجهّز الطلب — سنخبرك عند الجاهزية',
    'The kitchen is preparing it — you will be told when it is ready',
  );
  String get pickUp => _('استلمت الطلب، انطلق', 'Picked up, go');
  String get delivered => _('تم التسليم للعميل', 'Delivered to the customer');
  String get deliveredConfirmTitle => _('تأكيد التسليم', 'Confirm delivery');
  String get deliveredConfirmBody => _(
    'هل سلّمت الطلب للعميل؟ لا يمكن التراجع.',
    'Did you hand the order to the customer? This cannot be undone.',
  );
  String get confirm => _('تأكيد', 'Confirm');
  String get cancel => _('إلغاء', 'Cancel');
  String get trackingOn => _('مشاركة موقعك مفعّلة أثناء التوصيل', 'Your location is shared while delivering');

  // Location
  String get locationNeededTitle => _('نحتاج موقعك', 'Location needed');
  String get locationNeededBody => _(
    'يُشارك موقعك مع المتجر والعميل أثناء التوصيل فقط.',
    'Your location is shared with the store and customer only while delivering.',
  );
  String get locationDenied => _(
    'صلاحية الموقع مرفوضة — فعّلها من الإعدادات لمتابعة التوصيل.',
    'Location permission denied — enable it in Settings to deliver.',
  );
  String get locationOff => _('خدمة الموقع مغلقة على الجهاز.', 'Location services are off.');
  String get openSettings => _('فتح الإعدادات', 'Open Settings');
  String get allow => _('السماح', 'Allow');

  // Profile
  String get profile => _('حسابي', 'Account');
  String get store => _('المتجر', 'Store');
  String get vehicle => _('المركبة', 'Vehicle');
  String get signOut => _('تسجيل الخروج', 'Sign out');
  String get signOutConfirm => _('هل تريد تسجيل الخروج؟', 'Sign out?');
  String get language => _('اللغة', 'Language');
}
