/// A delivery order as the driver sees it (the API's OrderResource).
class DriverOrder {
  const DriverOrder({
    required this.id,
    required this.reference,
    required this.status,
    required this.total,
    required this.deliveryFee,
    required this.items,
    required this.customerName,
    required this.customerPhone,
    required this.customerNotes,
    required this.delivery,
    required this.branch,
    required this.driver,
    required this.createdAt,
    required this.assignedAt,
    required this.outForDeliveryAt,
    required this.completedAt,
  });

  final int id;
  final String reference;
  final String status;
  final double total;
  final double deliveryFee;
  final List<OrderLine> items;
  final String? customerName;
  final String? customerPhone;
  final String? customerNotes;
  final DeliveryInfo? delivery;
  final BranchInfo? branch;
  final DriverInfo? driver;
  final DateTime? createdAt;
  final DateTime? assignedAt;
  final DateTime? outForDeliveryAt;
  final DateTime? completedAt;

  static const _claimable = {'accepted', 'preparing', 'ready'};

  bool get isUnassigned => driver == null;

  bool get isClaimable => isUnassigned && _claimable.contains(status);

  bool get isTerminal => status == 'completed' || status == 'cancelled' || status == 'rejected';

  bool get isReadyForPickup => status == 'ready';

  bool get isOutForDelivery => status == 'out_for_delivery';

  bool get isBeingPrepared => status == 'accepted' || status == 'preparing';

  int get itemCount => items.fold(0, (sum, line) => sum + line.quantity);

  factory DriverOrder.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'];
    final delivery = json['delivery'];
    final branch = json['branch'];
    final driver = json['driver'];

    return DriverOrder(
      id: json['id'] as int,
      reference: (json['reference'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      total: _num(json['total']),
      deliveryFee: _num(json['delivery_fee']),
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OrderLine.fromJson)
          .toList(growable: false),
      customerName: customer is Map ? customer['name'] as String? : null,
      customerPhone: customer is Map ? customer['phone'] as String? : null,
      customerNotes: json['customer_notes'] as String?,
      delivery: delivery is Map<String, dynamic> ? DeliveryInfo.fromJson(delivery) : null,
      branch: branch is Map<String, dynamic> ? BranchInfo.fromJson(branch) : null,
      driver: driver is Map<String, dynamic> ? DriverInfo.fromJson(driver) : null,
      createdAt: _date(json['created_at']),
      assignedAt: _date(json['assigned_at']),
      outForDeliveryAt: _date(json['out_for_delivery_at']),
      completedAt: _date(json['completed_at']),
    );
  }
}

class OrderLine {
  const OrderLine({required this.name, required this.quantity, required this.options});

  final String name;
  final int quantity;
  final List<String> options;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    name: (json['name'] ?? '').toString(),
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    options: ((json['options'] as List?) ?? const [])
        .whereType<Map>()
        .map((o) => (o['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList(growable: false),
  );
}

class DeliveryInfo {
  const DeliveryInfo({
    required this.address,
    required this.details,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
  });

  final String? address;
  final String? details;
  final double? latitude;
  final double? longitude;
  final double? distanceKm;

  bool get hasPin => latitude != null && longitude != null;

  factory DeliveryInfo.fromJson(Map<String, dynamic> json) => DeliveryInfo(
    address: json['address'] as String?,
    details: json['details'] as String?,
    latitude: _numOrNull(json['latitude']),
    longitude: _numOrNull(json['longitude']),
    distanceKm: _numOrNull(json['distance_km']),
  );
}

class BranchInfo {
  const BranchInfo({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;

  bool get hasPin => latitude != null && longitude != null;

  factory BranchInfo.fromJson(Map<String, dynamic> json) => BranchInfo(
    name: (json['name'] ?? '').toString(),
    address: json['address'] as String?,
    latitude: _numOrNull(json['latitude']),
    longitude: _numOrNull(json['longitude']),
  );
}

class DriverInfo {
  const DriverInfo({required this.id, required this.name});

  final int id;
  final String name;

  factory DriverInfo.fromJson(Map<String, dynamic> json) =>
      DriverInfo(id: json['id'] as int, name: (json['name'] ?? '').toString());
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

double? _numOrNull(Object? v) => v == null ? null : _num(v);

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
