/// ============================================================================
/// THE DYNAMIC MERCHANT EXPERIENCE (spec §8, §31, §43)
///
/// These models mirror GET /stores/{token}. Everything the app renders for a
/// merchant comes from here — there is no merchant-specific code, no per-store
/// screens, and no build-time configuration.
///
///   "Creating a new merchant must NOT require a new Flutter build."
/// ============================================================================
library;

import 'menu.dart';

/// One step in the customer journey, as the SERVER ordered it.
///
/// The app has one widget per step TYPE (7 total), not one screen per merchant.
/// Merchant A gets service → staff → date → time; Merchant B gets branch →
/// service → date → time. Same binary.
class FlowStep {
  const FlowStep({
    required this.type,
    required this.required,
    this.mode,
    this.allowAny = false,
    this.depositType,
    this.depositValue,
  });

  factory FlowStep.fromJson(Map<String, dynamic> json) => FlowStep(
        type: FlowStepType.parse(json['step'] as String?),
        required: json['required'] as bool? ?? true,
        mode: json['mode'] as String?,
        allowAny: json['allow_any'] as bool? ?? false,
        depositType: json['deposit_type'] as String?,
        depositValue: (json['deposit_value'] as num?)?.toDouble(),
      );

  final FlowStepType type;
  final bool required;

  /// Payment step only: 'pay_at_store' | 'deposit' | 'full'.
  final String? mode;
  final bool allowAny;
  final String? depositType;
  final double? depositValue;
}

enum FlowStepType {
  branch,
  service,
  staff,
  date,
  time,
  notes,
  payment,
  confirm,
  unknown;

  /// Unknown steps are SKIPPED, never fatal.
  ///
  /// A future engine may introduce a step this build does not know about. The
  /// app must degrade rather than crash on a payload from a newer server.
  static FlowStepType parse(String? value) => switch (value) {
        'branch' => FlowStepType.branch,
        'service' => FlowStepType.service,
        'staff' => FlowStepType.staff,
        'date' => FlowStepType.date,
        'time' => FlowStepType.time,
        'notes' => FlowStepType.notes,
        'payment' => FlowStepType.payment,
        'confirm' => FlowStepType.confirm,
        _ => FlowStepType.unknown,
      };
}

class StoreConfiguration {
  const StoreConfiguration({
    this.staffSelection = false,
    this.branchSelection = false,
    this.paymentRequired = false,
    this.depositRequired = false,
    this.allowCancellation = true,
    this.allowRescheduling = true,
    this.customerNotes = true,
    this.guestBooking = false,
    // Restaurant order toggles (the merchant controls each from the dashboard).
    this.orderPickup = true,
    this.orderDineIn = true,
    this.orderDelivery = false,
    this.orderCurbside = false,
    this.deliveryFee = 0,
    this.deliveryMinOrder = 0,
    this.defaultPrepMinutes = 20,
  });

  factory StoreConfiguration.fromJson(Map<String, dynamic> json) => StoreConfiguration(
        staffSelection: json['staff_selection'] as bool? ?? false,
        branchSelection: json['branch_selection'] as bool? ?? false,
        paymentRequired: json['payment_required'] as bool? ?? false,
        depositRequired: json['deposit_required'] as bool? ?? false,
        allowCancellation: json['allow_cancellation'] as bool? ?? true,
        allowRescheduling: json['allow_rescheduling'] as bool? ?? true,
        customerNotes: json['customer_notes'] as bool? ?? true,
        guestBooking: json['guest_booking'] as bool? ?? false,
        orderPickup: json['order_pickup'] as bool? ?? true,
        orderDineIn: json['order_dine_in'] as bool? ?? true,
        orderDelivery: json['order_delivery'] as bool? ?? false,
        orderCurbside: json['order_curbside'] as bool? ?? false,
        deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0,
        deliveryMinOrder: (json['delivery_min_order'] as num?)?.toDouble() ?? 0,
        defaultPrepMinutes: json['default_prep_minutes'] as int? ?? 20,
      );

  final bool staffSelection;
  final bool branchSelection;
  final bool paymentRequired;
  final bool depositRequired;
  final bool allowCancellation;
  final bool allowRescheduling;
  final bool customerNotes;
  final bool guestBooking;

  final bool orderPickup;
  final bool orderDineIn;
  final bool orderDelivery;
  final bool orderCurbside;
  final double deliveryFee;
  final double deliveryMinOrder;
  final int defaultPrepMinutes;
}

class StoreService {
  const StoreService({
    required this.id,
    required this.name,
    required this.price,
    required this.durationMinutes,
    this.description,
    this.categoryId,
  });

  factory StoreService.fromJson(Map<String, dynamic> json) => StoreService(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        durationMinutes: json['duration_minutes'] as int? ?? 0,
        description: json['description'] as String?,
        categoryId: json['category_id'] as int?,
      );

  final int id;
  final String name;
  final double price;
  final int durationMinutes;
  final String? description;
  final int? categoryId;
}

/// A group of services within one store — الشعر / البشرة / المساج (spec §14).
///
/// NOT a marketplace taxonomy: these never span merchants and nothing browses
/// them globally (§46). They exist so a salon with twenty services is scannable
/// instead of an undifferentiated wall.
class StoreServiceCategory {
  const StoreServiceCategory({
    required this.id,
    required this.name,
    required this.services,
  });

  factory StoreServiceCategory.fromJson(Map<String, dynamic> json) => StoreServiceCategory(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        services: ((json['services'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(StoreService.fromJson)
            .toList(),
      );

  final int id;
  final String name;
  final List<StoreService> services;
}

class StoreStaff {
  const StoreStaff({required this.id, required this.name, this.title});

  factory StoreStaff.fromJson(Map<String, dynamic> json) => StoreStaff(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        title: json['title'] as String?,
      );

  final int id;
  final String name;
  final String? title;
}

class StoreBranch {
  const StoreBranch({
    required this.id,
    required this.name,
    this.address,
    this.city,
    this.mapsUrl,
    this.latitude,
    this.longitude,
  });

  factory StoreBranch.fromJson(Map<String, dynamic> json) => StoreBranch(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        address: json['address'] as String?,
        city: json['city'] as String?,
        mapsUrl: json['google_maps_url'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  final int id;
  final String name;
  final String? address;
  final String? city;
  final String? mapsUrl;

  /// From the dashboard's map picker — the most precise fallback when the
  /// merchant never pasted a share link.
  final double? latitude;
  final double? longitude;
}

/// Opening hours, summarised by the server so every client shows identical text.
class OpeningHours {
  const OpeningHours({required this.days, required this.hours, required this.isOpenNow});

  factory OpeningHours.fromJson(Map<String, dynamic> json) => OpeningHours(
        days: json['days'] as String? ?? '',
        hours: json['hours'] as String? ?? '',
        isOpenNow: json['is_open_now'] as bool? ?? false,
      );

  final String days;
  final String hours;
  final bool isOpenNow;
}

class StoreLocation {
  const StoreLocation({this.city, this.address, this.mapsUrl});

  factory StoreLocation.fromJson(Map<String, dynamic> json) => StoreLocation(
        city: json['city'] as String?,
        address: json['address'] as String?,
        mapsUrl: json['maps_url'] as String?,
      );

  final String? city;
  final String? address;
  final String? mapsUrl;

  bool get hasAny => (city ?? address ?? mapsUrl) != null;
}

class CancellationPolicy {
  const CancellationPolicy({required this.allowed, required this.deadlineHours, this.text});

  factory CancellationPolicy.fromJson(Map<String, dynamic> json) => CancellationPolicy(
        allowed: json['allowed'] as bool? ?? false,
        deadlineHours: json['deadline_hours'] as int? ?? 0,
        text: json['text'] as String?,
      );

  final bool allowed;
  final int deadlineHours;

  /// Pre-rendered by the server so the app never reassembles a sentence from
  /// booleans, and shows it BEFORE the customer confirms (spec §21).
  final String? text;
}

/// The whole storefront.
class Storefront {
  const Storefront({
    required this.token,
    required this.name,
    required this.configuration,
    required this.flow,
    required this.services,
    required this.branches,
    required this.staff,
    required this.timezone,
    required this.currency,
    this.description,
    this.logo,
    this.cover,
    this.brandColor,
    this.phone,
    this.deepLink,
    this.requiresBranchSelection = false,
    this.cancellationPolicy,
    this.isVerified = false,
    this.genderPolicy = 'all',
    this.openingHours,
    this.location,
    this.categories = const [],
    this.maxAdvanceDays = defaultMaxAdvanceDays,
    this.minLeadTimeMinutes = 0,
    this.type = 'beauty_wellness',
    this.menu,
  });

  /// Used only when the server sends no booking window (a store with no
  /// settings row). Deliberately conservative: offering days the merchant has
  /// not agreed to is worse than offering too few.
  static const defaultMaxAdvanceDays = 30;

  factory Storefront.fromJson(Map<String, dynamic> json) {
    final store = (json['store'] as Map<String, dynamic>?) ?? const {};
    final policies = (json['policies'] as Map<String, dynamic>?) ?? const {};
    final bookingWindow = (policies['booking_window'] as Map<String, dynamic>?) ?? const {};

    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) build) =>
        (raw as List?)?.whereType<Map<String, dynamic>>().map(build).toList() ?? <T>[];

    // Services can arrive flat or nested under categories; flatten both so the
    // service step has one list to render.
    final flatServices = list(json['services'], StoreService.fromJson);
    final categorised = ((json['categories'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .expand((category) => list(category['services'], StoreService.fromJson))
        .toList();

    final services = flatServices.isNotEmpty ? flatServices : categorised;

    // Keep the grouping too, so the service step can section a long menu.
    final categories = ((json['categories'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StoreServiceCategory.fromJson)
        .where((category) => category.services.isNotEmpty)
        .toList();

    return Storefront(
      token: store['token'] as String? ?? '',
      name: store['name'] as String? ?? '',
      type: store['type'] as String? ?? 'beauty_wellness',
      menu: json['menu'] is Map<String, dynamic>
          ? Menu.fromJson(json['menu'] as Map<String, dynamic>)
          : null,
      description: store['description'] as String?,
      logo: store['logo'] as String?,
      cover: store['cover'] as String?,
      brandColor: store['brand_color'] as String?,
      phone: store['phone'] as String?,
      deepLink: store['deep_link'] as String?,
      timezone: store['timezone'] as String? ?? 'Asia/Riyadh',
      currency: store['currency'] as String? ?? 'SAR',
      configuration: StoreConfiguration.fromJson(
        (json['configuration'] as Map<String, dynamic>?) ?? const {},
      ),
      flow: ((json['flow'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FlowStep.fromJson)
          .where((step) => step.type != FlowStepType.unknown)
          .toList(),
      services: services,
      branches: list(json['branches'], StoreBranch.fromJson),
      staff: list(json['staff'], StoreStaff.fromJson),
      requiresBranchSelection: json['requires_branch_selection'] as bool? ?? false,
      isVerified: store['is_verified'] as bool? ?? false,
      genderPolicy: store['gender_policy'] as String? ?? 'all',
      openingHours: json['hours'] is Map<String, dynamic>
          ? OpeningHours.fromJson(json['hours'] as Map<String, dynamic>)
          : null,
      location: json['location'] is Map<String, dynamic>
          ? StoreLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
      categories: categories,
      // How far ahead THIS merchant takes bookings. Hard-coding 30 in the date
      // widgets hid days 31-60 from every store on the default setting, and
      // offered unbookable days to any store configured below 30.
      maxAdvanceDays: ((bookingWindow['max_advance_days'] as num?)?.toInt() ??
              defaultMaxAdvanceDays)
          .clamp(1, 365),
      // How much notice this merchant needs. The engine already refuses slots
      // inside the window; reading it here keeps the app from OFFERING days
      // the engine will always answer with an empty list.
      minLeadTimeMinutes:
          ((bookingWindow['min_lead_time_minutes'] as num?)?.toInt() ?? 0)
              .clamp(0, 60 * 24 * 30),
      cancellationPolicy: policies['cancellation'] is Map<String, dynamic>
          ? CancellationPolicy.fromJson(policies['cancellation'] as Map<String, dynamic>)
          : null,
    );
  }

  final String token;
  final String name;
  final String? description;
  final String? logo;
  final String? cover;
  final String? brandColor;
  final String? phone;
  final String? deepLink;
  final String timezone;
  final String currency;
  final StoreConfiguration configuration;
  final List<FlowStep> flow;
  final List<StoreService> services;
  final List<StoreBranch> branches;
  final List<StoreStaff> staff;
  final bool requiresBranchSelection;
  final CancellationPolicy? cancellationPolicy;

  /// The platform vouching for a merchant an admin approved (spec §39).
  final bool isVerified;
  final String genderPolicy;
  final OpeningHours? openingHours;
  final StoreLocation? location;

  /// Populated only when the merchant actually grouped their services.
  final List<StoreServiceCategory> categories;

  /// The last bookable day, as days from today (spec §17 booking window).
  final int maxAdvanceDays;

  /// Minimum notice before a booking may start (spec §17). Zero when the
  /// server sends no booking window.
  final int minLeadTimeMinutes;

  /// The engine this store runs on — 'beauty_wellness' or 'restaurant'.
  final String type;

  /// The menu tree, present only for restaurant storefronts.
  final Menu? menu;

  bool get isRestaurant => type == 'restaurant';

  /// Worth sectioning the list? One category is the same as none.
  bool get hasCategories => categories.length > 1;
}
