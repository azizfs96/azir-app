import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../stores/data/store_repository.dart';
import 'cart_controller.dart';

/// Rebuild a past order into the cart, ready to check out (reorder).
///
/// The store's live menu is the source of truth: a dish that has since been
/// removed, or an option that no longer exists, is silently dropped rather than
/// carried into an order the server would reject. Returns true if at least one
/// line survived — false means nothing on that order is still orderable.
Future<bool> reorderIntoCart(WidgetRef ref, OrderResult order) async {
  final token = order.storeToken;
  if (token == null) return false;

  final storefront = await ref.read(storefrontProvider(token).future);
  final menu = storefront.menu;
  if (menu == null) return false;

  final byId = {for (final item in menu.allItems) item.id: item};

  final lines = <CartLine>[];
  for (final line in order.items) {
    final item = line.itemId == null ? null : byId[line.itemId];
    if (item == null) continue;

    // Keep only option ids the item still offers.
    final valid = <int>{
      for (final group in item.optionGroups)
        for (final option in group.options)
          if (line.optionIds.contains(option.id)) option.id,
    };

    lines.add(CartLine(item: item, selectedOptionIds: valid, quantity: line.quantity));
  }

  if (lines.isEmpty) return false;

  ref.read(cartProvider.notifier).replaceAll(token, lines);
  return true;
}

/// ============================================================================
/// PLACING AND TRACKING ORDERS (RestaurantEngine, R3)
///
/// The client sends only intents — item id, chosen option ids, quantity — and
/// the server prices and validates authoritatively. The `total` the app shows
/// is display-only; the response carries the real, server-computed figure.
/// ============================================================================
class OrderRepository {
  const OrderRepository(this._api);

  final ApiClient _api;

  Future<OrderResult> place({
    required String storeToken,
    required String fulfillmentType,
    required List<CartLine> lines,
    String? notes,
    String? tableNumber,
    int? addressId,
    int? carId,
    int? branchId,
  }) async {
    final json = await _api.post('/orders', body: {
      'store_token': storeToken,
      'fulfillment_type': fulfillmentType,
      if (tableNumber != null && tableNumber.trim().isNotEmpty) 'table_number': tableNumber.trim(),
      'address_id': ?addressId,
      'car_id': ?carId,
      'branch_id': ?branchId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'items': [
        for (final line in lines)
          {
            'item_id': line.item.id,
            'quantity': line.quantity,
            'option_ids': line.selectedOptionIds.toList(),
          },
      ],
    });

    return OrderResult.fromJson(json);
  }

  Future<OrderResult> get(int id) async {
    final json = await _api.get('/orders/$id');
    return OrderResult.fromJson(json);
  }

  /// The customer's own orders. filter = 'active' | 'past'.
  Future<List<OrderResult>> myOrders(String filter) async {
    final json = await _api.get('/orders?filter=$filter');
    final data = (json['data'] as List?) ?? const [];
    return [for (final o in data) OrderResult.fromJson(o as Map<String, dynamic>)];
  }

  Future<OrderResult> cancel(int id) async {
    final json = await _api.post('/orders/$id/cancel');
    return OrderResult.fromJson(json);
  }
}

/// An order as the app tracks it.
/// A ZATCA simplified tax invoice — the seller's VAT details and the Base64 TLV
/// the app renders as the compliance QR.
class OrderInvoice {
  const OrderInvoice({
    this.number,
    this.sellerName,
    this.taxNumber,
    this.commercialRegistration,
    this.nationalAddress,
    this.logo,
    this.taxRate = 0,
    this.qr,
    this.issuedAt,
  });

  factory OrderInvoice.fromJson(Map<String, dynamic> json) => OrderInvoice(
        number: json['number'] as String?,
        sellerName: json['seller_name'] as String?,
        taxNumber: json['tax_number'] as String?,
        commercialRegistration: json['commercial_registration'] as String?,
        nationalAddress: json['national_address'] as String?,
        logo: json['logo'] as String?,
        taxRate: (json['tax_rate'] as num?)?.toDouble() ?? 0,
        qr: json['qr'] as String?,
        issuedAt: DateTime.tryParse(json['issued_at'] as String? ?? ''),
      );

  final String? number;
  final String? sellerName;
  final String? taxNumber;
  final String? commercialRegistration;
  final String? nationalAddress;

  /// Store logo path (the client builds the URL).
  final String? logo;
  final double taxRate;

  /// Base64 TLV; the QR image is rendered from this exact string.
  final String? qr;
  final DateTime? issuedAt;
}

class OrderResult {
  const OrderResult({
    required this.id,
    required this.reference,
    required this.status,
    required this.total,
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.taxAmount = 0,
    this.invoice,
    this.fulfillmentType = 'pickup',
    this.prepMinutes,
    this.storeName,
    this.storeToken,
    this.createdAt,
    this.acceptedAt,
    this.readyAt,
    this.items = const [],
    this.deliveryAddress,
    this.customerName,
    this.customerPhone,
  });

  factory OrderResult.fromJson(Map<String, dynamic> json) => OrderResult(
        id: json['id'] as int,
        reference: json['reference'] as String? ?? '',
        status: json['status'] as String? ?? 'placed',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
        deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0,
        taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
        invoice: json['invoice'] is Map<String, dynamic>
            ? OrderInvoice.fromJson(json['invoice'] as Map<String, dynamic>)
            : null,
        fulfillmentType: json['fulfillment_type'] as String? ?? 'pickup',
        prepMinutes: json['prep_minutes'] as int?,
        storeName: (json['store'] as Map<String, dynamic>?)?['name'] as String?,
        storeToken: (json['store'] as Map<String, dynamic>?)?['token'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        acceptedAt: DateTime.tryParse(json['accepted_at'] as String? ?? ''),
        readyAt: DateTime.tryParse(json['ready_at'] as String? ?? ''),
        deliveryAddress: (json['delivery'] as Map<String, dynamic>?)?['address'] as String?,
        customerName: (json['customer'] as Map<String, dynamic>?)?['name'] as String?,
        customerPhone: (json['customer'] as Map<String, dynamic>?)?['phone'] as String?,
        items: [
          for (final it in (json['items'] as List?) ?? const [])
            OrderLineResult.fromJson(it as Map<String, dynamic>),
        ],
      );

  final int id;
  final String reference;
  final String status;
  final double total;
  final double subtotal;
  final double deliveryFee;
  final double taxAmount;

  /// The ZATCA tax invoice — present only when the order was taxed.
  final OrderInvoice? invoice;
  final String fulfillmentType;
  final int? prepMinutes;
  final String? storeName;
  final String? storeToken;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? readyAt;
  final List<OrderLineResult> items;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;

  /// A short human pickup code shown at the counter/curbside (Jahez-style).
  String get pickupCode => (id % 100).toString().padLeft(2, '0');
}

/// One line of a placed order (snapshot), for the detail/tracking screens.
class OrderLineResult {
  const OrderLineResult({
    required this.name,
    required this.quantity,
    required this.lineTotal,
    this.itemId,
    this.image,
    this.options = const [],
    this.optionIds = const [],
  });

  factory OrderLineResult.fromJson(Map<String, dynamic> json) => OrderLineResult(
        name: json['name'] as String? ?? '',
        quantity: json['quantity'] as int? ?? 1,
        lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
        itemId: json['item_id'] as int?,
        image: json['image'] as String?,
        options: [
          for (final o in (json['options'] as List?) ?? const [])
            (o as Map<String, dynamic>)['name'] as String? ?? '',
        ],
        optionIds: [
          for (final o in (json['options'] as List?) ?? const [])
            if ((o as Map<String, dynamic>)['option_id'] != null) o['option_id'] as int,
        ],
      );

  final String name;
  final int quantity;
  final double lineTotal;

  /// Menu ids for rebuilding this line into the cart on reorder.
  final int? itemId;
  final String? image;
  final List<String> options;
  final List<int> optionIds;
}

final orderRepositoryProvider =
    Provider<OrderRepository>((ref) => OrderRepository(ref.watch(apiClientProvider)));

/// Live view of one order, for the tracking screen (polled/refetched).
final orderProvider = FutureProvider.family<OrderResult, int>(
  (ref, id) => ref.watch(orderRepositoryProvider).get(id),
);

/// The customer's orders, by filter ('active' | 'past').
final myOrdersProvider = FutureProvider.family<List<OrderResult>, String>(
  (ref, filter) => ref.watch(orderRepositoryProvider).myOrders(filter),
);
