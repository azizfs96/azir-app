import 'package:flutter/widgets.dart';

/// Localization (spec §33).
///
///   "Do not hard-code text directly inside components. Use localization."
///
/// Arabic is the default and the design baseline; English is secondary.
/// A plain class rather than generated ARB: the string set is small, and this
/// keeps the whole dictionary readable in one file during the MVP.
class Strings {
  const Strings(this.locale);

  final Locale locale;

  bool get isArabic => locale.languageCode == 'ar';

  static const supported = [Locale('ar'), Locale('en')];

  static Strings of(BuildContext context) =>
      Strings(Localizations.localeOf(context));

  String _(String ar, String en) => isArabic ? ar : en;

  // Brand
  String get appName => _('وصلة', 'Wasla');
  String get tagline => _('امسح، وادخل مباشرة', 'Scan, and enter directly');

  // Home (spec §5)
  /// Falls back to a nameless greeting rather than leaving a dangling comma,
  /// which is what a signed-out customer would otherwise see.
  String greeting(String? name) => (name == null || name.trim().isEmpty)
      ? _('صباح الخير', 'Good morning')
      : _('صباح الخير، $name', 'Good morning, $name');
  String get myStores => _('متاجري', 'My Stores');
  String get noStoresTitle => _('لا توجد متاجر بعد', 'No stores yet');
  String get noStoresHint => _(
        'امسح رمز QR الخاص بالمتجر\nلإضافة أول متجر لك.',
        'Scan a merchant QR code\nto add your first store.',
      );
  String get nextAppointment => _('الموعد القادم', 'Next appointment');
  String get lastVisit => _('آخر زيارة', 'Last visit');
  String get viewStore => _('عرض المتجر', 'View Store');
  String get bookAgain => _('احجز مرة أخرى', 'Book Again');
  String get scanQr => _('مسح رمز QR', 'Scan QR');

  // QR scanner (spec §6)
  String get scanTitle => _('امسح رمز المتجر', 'Scan store code');
  String get scanHint => _(
        'وجّه الكاميرا نحو رمز QR الخاص بالمتجر',
        'Point your camera at the store QR code',
      );
  String get enterCode => _('إدخال الرمز يدوياً', 'Enter code manually');
  String get storeCode => _('رمز المتجر', 'Store code');
  String get searchMenu => _('ابحث في المنيو', 'Search the menu');
  String get noResults => _('لا توجد نتائج', 'No results');
  String get invalidCode => _('لم نتمكن من العثور على متجر بهذا الرمز', 'No store found with that code');
  String get cannotReachServer => _('تعذّر الاتصال بالخادم', 'Cannot reach the server');
  String get cannotReachServerHint => _(
        'تحقق من اتصالك بالإنترنت ثم أعد المحاولة.',
        'Check your connection and try again.',
      );
  String get cameraPermission => _('نحتاج إذن الكاميرا للمسح', 'Camera access is needed to scan');

  // Auth (spec §34)
  String get phoneNumber => _('رقم الجوال', 'Mobile number');
  String get sendCode => _('إرسال الرمز', 'Send code');
  String get verifyCode => _('رمز التحقق', 'Verification code');
  String get verify => _('تحقق', 'Verify');
  String codeSentTo(String phone) => _('أرسلنا رمزاً إلى $phone', 'We sent a code to $phone');
  String get devCodeHint => _('وضع التجربة: الرمز 1111', 'Test mode: the code is 1111');
  String get resend => _('إعادة الإرسال', 'Resend');

  // Booking flow (spec §41)
  String get chooseService => _('اختر الخدمة', 'Choose a service');
  String get chooseServiceHint =>
      _('اختر الخدمة التي تريد حجزها', 'Pick the service you want to book');
  String get allServices => _('الكل', 'All');
  String get chooseStaff => _('اختر الموظف', 'Choose a staff member');
  String get chooseStaffHint =>
      _('اختر من يقدّم لك الخدمة', 'Pick who will serve you');
  String get orChooseSpecific => _('أو اختر موظفاً محدداً', 'or pick someone specific');
  String get recommended => _('الأسرع', 'Fastest');
  String get anyStaffHint =>
      _('أقرب موعد متاح', 'Gets you the earliest appointment');
  String get chooseBranch => _('اختر الفرع', 'Choose a branch');
  String get chooseDate => _('اختر التاريخ', 'Choose a date');
  String get chooseDateTime => _('اختر الموعد', 'Choose a time');
  String get tryAnotherDay => _('جرّب يوماً آخر', 'Try another day');
  String get chooseTime => _('اختر الوقت', 'Choose a time');
  String slotsAvailable(int n) => _('$n موعد متاح', '$n times available');
  String get morning => _('صباحاً', 'Morning');
  String get afternoon => _('ظهراً', 'Afternoon');
  String get evening => _('مساءً', 'Evening');
  String get today => _('اليوم', 'Today');
  String get tomorrow => _('غداً', 'Tomorrow');
  String get addNotes => _('ملاحظات (اختياري)', 'Notes (optional)');
  String get payment => _('الدفع', 'Payment');
  String get payAtStore => _('الدفع في الفرع', 'Pay at the store');
  String get payAtStoreHint => _(
        'ستدفع عند وصولك للفرع.',
        'You will pay when you arrive.',
      );
  String get confirmBooking => _('تأكيد الحجز', 'Confirm booking');
  String get serviceLabel => _('الخدمة', 'Service');
  String get staffLabel => _('الموظف', 'Staff');
  String get branchLabel => _('الفرع', 'Branch');
  String get notesLabel => _('ملاحظات', 'Notes');
  String get total => _('الإجمالي', 'Total');
  String get subtotal => _('المجموع الفرعي', 'Subtotal');
  String get deliveryFeeLabel => _('رسوم التوصيل', 'Delivery fee');
  String get vat => _('ضريبة القيمة المضافة', 'VAT');
  String get taxInvoice => _('الفاتورة الضريبية', 'Tax invoice');
  String get taxNumberLabel => _('الرقم الضريبي', 'VAT no.');
  String get simplifiedTaxInvoice => _('فاتورة ضريبية مبسطة', 'Simplified Tax Invoice');
  String get invoiceNo => _('رقم الفاتورة', 'Invoice no.');
  String get invoiceDate => _('تاريخ الفاتورة', 'Invoice date');
  String get crLabel => _('سجل تجاري رقم', 'CR no.');
  String get addressLabel => _('العنوان', 'Address');
  String get customerInfo => _('معلومات العميل', 'Customer information');
  String get fullName => _('الاسم الكامل', 'Full name');
  String get phone => _('الهاتف', 'Phone');
  String get productsInfo => _('معلومات المنتجات', 'Products');
  String get orderDetails => _('تفاصيل الطلب', 'Order details');
  String get totalExclVat => _('إجمالي المبلغ غير شامل الضريبة', 'Total (excl. VAT)');
  String get totalVat => _('إجمالي ضريبة القيمة المضافة', 'Total VAT');
  String get totalInclVat => _('إجمالي شامل القيمة المضافة', 'Total (incl. VAT)');
  String get sar => _('ر.س', 'SAR');
  String get paymentMethod => _('طريقة الدفع', 'Payment method');
  String get payOnPickup => _('الدفع عند الاستلام', 'Pay on pickup');
  String get productName => _('اسم المنتج', 'Product');
  String get qtyShort => _('الكمية', 'Qty');
  String get taxableAmount => _('المبلغ الخاضع للضريبة', 'Taxable amount');
  String get inclVat => _('شامل القيمة المضافة', 'Incl. VAT');
  String get viewInvoice => _('عرض الفاتورة', 'View invoice');
  String get discountCode => _('كود الخصم', 'Discount code');
  String get apply => _('تطبيق', 'Apply');
  String get change => _('تغيير', 'Change');
  String get addDeliveryAddress => _('أضف عنوان التوصيل من حسابك', 'Add a delivery address in your account');
  String get missingSlot => _(
        'لم يتم اختيار وقت. ارجع خطوة واختر موعداً.',
        'No time selected. Go back a step and pick one.',
      );
  String get anyStaff => _('أي موظف متاح', 'Any available staff');
  String get noSlots => _('لا توجد أوقات متاحة في هذا اليوم', 'No times available on this day');
  String get bookingConfirmed => _('تم تأكيد حجزك', 'Booking confirmed');
  String get bookingReference => _('رقم الحجز', 'Booking reference');
  String get slotTaken => _('عذراً، تم حجز هذا الوقت للتو. اختر وقتاً آخر.', 'Sorry, that time was just booked. Please choose another.');
  String get backToHome => _('العودة للرئيسية', 'Back to home');
  String get backToStore => _('العودة للمتجر', 'Back to store');

  /// Shown when the booking request fails for a reason the SERVER did not
  /// describe — a timeout, no connection, an unexpected exception. The raw
  /// text in those cases is English transport detail, or worse
  /// ("Instance of 'TypeError'"), which is not something to put in front of a
  /// customer.
  String get discardBookingTitle => _('إلغاء الحجز؟', 'Discard this booking?');
  String get discardBookingBody => _(
        'ستفقد ما اخترته حتى الآن.',
        "You'll lose what you've chosen so far.",
      );
  String get keepBooking => _('متابعة الحجز', 'Keep booking');
  String get discardBooking => _('خروج', 'Discard');

  String get bookingFailed => _(
        'تعذّر إتمام الحجز. تحقق من اتصالك وحاول مرة أخرى.',
        'Could not complete the booking. Check your connection and try again.',
      );

  // Storefront tabs
  String get servicesTab => _('الخدمات', 'Services');
  String get myBookingsTab => _('حجوزاتي', 'My bookings');
  String get noBookingsHere => _('لا توجد حجوزات في هذا المتجر', 'No bookings at this store yet');
  String get noBookingsHereHint => _(
        'اختر خدمة من الأعلى لحجز أول موعد لك.',
        'Pick a service above to book your first appointment.',
      );
  String get upcomingSection => _('القادمة', 'Upcoming');
  String get pastSection => _('السابقة', 'Past');
  String get bookNow => _('احجز الآن', 'Book now');
  String get from => _('من', 'from');
  String get noServices => _('لا توجد خدمات متاحة حالياً', 'No services available right now');
  String get callStore => _('اتصل', 'Call');

  // Storefront header
  String get verified => _('موثّق', 'Verified');
  String get openNow => _('مفتوح الآن', 'Open now');
  String get closedNow => _('مغلق الآن', 'Closed');
  String get workingHours => _('أوقات العمل', 'Working hours');
  String get location => _('الموقع', 'Location');
  String get viewOnMap => _('عرض على الخريطة', 'View on map');
  String get branchesAndLocations => _('الفروع والمواقع', 'Branches & locations');
  String get openInMaps => _('فتح في الخرائط', 'Open in Maps');
  String get bookAppointment => _('احجز موعداً', 'Book Appointment');

  // Restaurant menu / cart (RestaurantEngine, R2)
  String get menuTab => _('المنيو', 'Menu');
  String get productsTitle => _('المنتجات', 'Products');
  String get menuSectionsTitle => _('أصناف القائمة', 'Menu');
  String caloriesLabel(int n) => _('$n سعرة', '$n cal');
  String get featuredSection => _('الأكثر مبيعاً', 'Best sellers');
  String get soldOut => _('نفد', 'Sold out');
  String get addToCart => _('أضف للسلة', 'Add to cart');
  String get cart => _('السلة', 'Cart');
  String get emptyCart => _('سلتك فارغة', 'Your cart is empty');
  String get emptyCartHint => _('تصفّح المنيو وأضف ما يعجبك.', 'Browse the menu and add what you like.');
  String get orderTotal => _('الإجمالي', 'Total');
  String get reviewOrder => _('مراجعة الطلب', 'Review order');
  String get required => _('إلزامي', 'Required');
  String get optional => _('اختياري', 'Optional');
  String chooseUpTo(int n) => _('اختر حتى $n', 'Choose up to $n');
  String chooseExactly(int n) => _('اختر $n', 'Choose $n');
  String get quantity => _('الكمية', 'Quantity');
  String addForPrice(String price) => _('أضف · $price', 'Add · $price');
  String get menuEmpty => _('لا يوجد منيو بعد', 'No menu yet');
  String get menuEmptyHint => _('لم يضِف المطعم أي أصناف حتى الآن.', 'This restaurant has not added any items yet.');
  String itemsInCart(int n) => _('$n في السلة', '$n in cart');
  String get remove => _('حذف', 'Remove');
  String get removeStore => _('إزالة', 'Remove');
  String get storeOpen => _('مفتوح', 'Open');
  String get storeClosed => _('مغلق', 'Closed');
  String get storeRemoved => _('تمت الإزالة من قائمتك', 'Removed from your list');
  String get placeOrder => _('إتمام الطلب', 'Place order');
  String get fulfillmentPickup => _('استلام', 'Pickup');
  String get fulfillmentDineIn => _('داخل المطعم', 'Dine-in');
  String get fulfillmentDelivery => _('توصيل', 'Delivery');
  String get fulfillmentCurbside => _('من السيارة', 'Curbside');
  String get pickupBranch => _('فرع الاستلام', 'Pickup branch');
  String get orderNow => _('اطلب الآن', 'Order now');
  String get storeGreeting => _('مرحباً بك 👋', 'Welcome 👋');
  String get orderCode => _('كود', 'Code');
  String get callRestaurant => _('اتصال', 'Call');
  String get orderMinutes => _('دقيقة', 'min');
  String fulfillmentLabel(String type) => switch (type) {
        'delivery' => _('توصيل', 'Delivery'),
        'curbside' => _('استلام من السيارة', 'Curbside pickup'),
        'dine_in' => _('داخل المطعم', 'Dine-in'),
        _ => _('استلام من الفرع', 'Pickup'),
      };
  String get tableNumber => _('رقم الطاولة', 'Table number');
  String get orderNotesHint => _('ملاحظات على الطلب (اختياري)', 'Order notes (optional)');
  String get orderPlaced => _('تم استلام طلبك', 'Order received');
  String orderReference(String ref) => _('رقم الطلب $ref', 'Order $ref');
  String get orderFailed => _('تعذّر إتمام الطلب. حاول مرة أخرى.', 'Could not place the order. Please try again.');
  String get trackOrder => _('تتبّع الطلب', 'Track order');
  String get track => _('تتبّع', 'Track');
  String get reorder => _('إعادة الطلب', 'Reorder');
  String get reorderUnavailable =>
      _('لم تعد أصناف هذا الطلب متوفرة', 'This order\'s items are no longer available');
  String get myOrders => _('طلباتي', 'My orders');
  String get noOrders => _('لا توجد طلبات بعد', 'No orders yet');
  String get orderAgain => _('اطلب نفس الطلب', 'Order the same');
  String get orderDelivered => _('تم التوصيل', 'Delivered');
  String get orderReceived => _('تم الاستلام', 'Received');
  String get orderPreparing => _('قيد التحضير', 'Preparing');
  String get myAccount => _('حسابي', 'My account');
  String get myAddresses => _('عناويني', 'My addresses');
  String get help => _('المساعدة', 'Help');
  String get signOut => _('تسجيل الخروج', 'Sign out');
  String get needHelp => _('تحتاج مساعدة؟', 'Need help?');
  String get helpBody => _('فريق المطعم جاهز للرد على استفساراتك.', 'The restaurant team is ready to help.');
  String get contactRestaurant => _('تواصل مع المطعم', 'Contact the restaurant');
  String get manageLocations => _('إدارة المواقع', 'Manage locations');
  String get noSavedLocations => _('لا توجد مواقع محفوظة', 'No saved locations');
  String get noSavedLocationsHint => _('أضف موقعك لتسهيل عملية التوصيل', 'Add your location to speed up delivery');
  String get addLocation => _('إضافة موقع جديد', 'Add a location');
  String get addressHint => _('العنوان (الحي، الشارع)', 'Address (district, street)');
  String get addressDetailsHint => _('تفاصيل إضافية: رقم المبنى، الدور، علامة مميزة', 'Building no., floor, landmark');
  String get save => _('حفظ', 'Save');
  String get labelHome => _('المنزل', 'Home');
  String get labelWork => _('العمل', 'Work');
  String get labelOther => _('آخر', 'Other');
  String get defaultLabel => _('افتراضي', 'Default');
  String get pinYourLocation => _('حدّد موقعك', 'Set your location');
  String get dragMapHint => _('اسحب الخريطة لتحديد الموقع بدقة', 'Drag the map to pinpoint your location');
  String get confirmLocation => _('تأكيد الموقع', 'Confirm location');
  String get locating => _('جاري تحديد العنوان…', 'Finding address…');
  String get homeTab => _('الرئيسية', 'Home');
  String get notifications => _('الإشعارات', 'Notifications');
  String get noNotifications => _('لا توجد إشعارات', 'No notifications');
  String get myCars => _('سياراتي', 'My cars');
  String get noCars => _('ما عندك سيارات محفوظة', 'No saved cars');
  String get noCarsHint => _('أضف سيارتك عشان نعرف كيف نطلع لك طلبك', 'Add your car so we can find you');
  String get addCar => _('إضافة سيارة جديدة', 'Add a car');
  String get chooseBrand => _('اختر الماركة', 'Choose the brand');
  String get carColorLabel => _('لون السيارة', 'Car colour');
  String get plateLettersLabel => _('حروف اللوحة', 'Plate letters');
  String get plateNumbersLabel => _('أرقام اللوحة', 'Plate numbers');
  String get saveCar => _('حفظ السيارة', 'Save the car');
  String get addCarForCurbside => _('أضف سيارة من حسابك للاستلام من السيارة', 'Add a car in your account for curbside');
  String prepTime(int minutes) => _('وقت التحضير المتوقع $minutes دقيقة', 'Estimated $minutes min');
  String get orderStatusPlaced => _('بانتظار قبول المطعم', 'Waiting for the restaurant');
  String get orderStatusAccepted => _('تم قبول طلبك', 'Order accepted');
  String get orderStatusPreparing => _('يُحضّر الآن', 'Being prepared');
  String get orderStatusReady => _('جاهز للاستلام', 'Ready for pickup');
  String get orderStatusCompleted => _('تم التسليم', 'Completed');
  String get orderStatusRejected => _('رُفض الطلب', 'Order rejected');
  String get orderStatusCancelled => _('أُلغي الطلب', 'Order cancelled');
  String get cancelOrder => _('إلغاء الطلب', 'Cancel order');
    String get orderComingSoon => _(
        'إتمام الطلب سيتوفر قريباً — هذه مراجعة لسلتك.',
        'Checkout is coming soon — this is a review of your cart.',
      );
  String get popularServices => _('الخدمات', 'Services');
  String get seeAll => _('عرض الكل', 'See All');
  String get share => _('مشاركة', 'Share');
  String get copied => _('تم نسخ الرابط', 'Link copied');
  String get womenOnly => _('نساء فقط', 'Women Only');
  String get menOnly => _('رجال فقط', 'Men Only');
  String get multipleBranches => _('عدة فروع', 'Multiple branches');
  String fromPrice(String amount) => _('من $amount', 'From $amount');

  // Bookings
  String get myBookings => _('حجوزاتي', 'My bookings');
  String get upcoming => _('القادمة', 'Upcoming');
  String get past => _('السابقة', 'Past');
  String get cancelBooking => _('إلغاء الحجز', 'Cancel booking');
  String get reschedule => _('تغيير الموعد', 'Reschedule');
  String get noBookings => _('لا توجد حجوزات', 'No bookings');

  // Common
  String get next => _('التالي', 'Next');
  String get back => _('رجوع', 'Back');
  String get cancel => _('إلغاء', 'Cancel');
  String get confirm => _('تأكيد', 'Confirm');
  String get retry => _('إعادة المحاولة', 'Retry');

  /// The availability request failed — named specifically so the customer
  /// knows the TIMES failed to load, not the store or their booking.
  String get availabilityError => _(
        'تعذّر تحميل الأوقات المتاحة. حاول مرة أخرى.',
        'Unable to load available times. Please try again.',
      );
  String get loading => _('جارٍ التحميل…', 'Loading…');
  String get error => _('حدث خطأ', 'Something went wrong');
  String get currency => _('ر.س', 'SAR');
  String minutes(int n) => _('$n دقيقة', '$n min');
  // Compact prep-time label for dish cards (Jahez-style): "15 د".
  String minShort(int n) => _('$n د', '$n min');
  String get close => _('إغلاق', 'Close');

  // Status (spec §19)
  String status(String value) => switch (value) {
        'pending' => _('بالانتظار', 'Pending'),
        'confirmed' => _('مؤكد', 'Confirmed'),
        'checked_in' => _('حضر', 'Checked in'),
        'completed' => _('مكتمل', 'Completed'),
        'cancelled' => _('ملغى', 'Cancelled'),
        'no_show' => _('لم يحضر', 'No-show'),
        _ => value,
      };
}
