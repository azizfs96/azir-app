import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// A saved delivery address (central, per customer). Managed once in the app and
/// reused at every store; the order snapshots the chosen one server-side.
class CustomerAddress {
  const CustomerAddress({
    required this.id,
    required this.label,
    required this.addressText,
    this.details,
    this.isDefault = false,
  });

  factory CustomerAddress.fromJson(Map<String, dynamic> json) => CustomerAddress(
        id: json['id'] as int,
        label: json['label'] as String? ?? 'home',
        addressText: json['address_text'] as String? ?? '',
        details: json['details'] as String?,
        isDefault: json['is_default'] as bool? ?? false,
      );

  final int id;
  final String label;
  final String addressText;
  final String? details;
  final bool isDefault;
}

class AddressRepository {
  const AddressRepository(this._api);

  final ApiClient _api;

  Future<List<CustomerAddress>> list() async {
    final json = await _api.get('/me/addresses');
    final data = (json['data'] as List?) ?? const [];
    return [for (final a in data) CustomerAddress.fromJson(a as Map<String, dynamic>)];
  }

  Future<void> add({
    required String label,
    required String addressText,
    String? details,
    double? latitude,
    double? longitude,
    bool isDefault = false,
  }) =>
      _api.post('/me/addresses', body: {
        'label': label,
        'address_text': addressText,
        if (details != null && details.isNotEmpty) 'details': details,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'is_default': isDefault,
      });

  Future<void> remove(int id) => _api.delete('/me/addresses/$id');
}

final addressRepositoryProvider =
    Provider<AddressRepository>((ref) => AddressRepository(ref.watch(apiClientProvider)));

/// The customer's saved addresses (default first).
final addressesProvider =
    FutureProvider<List<CustomerAddress>>((ref) => ref.watch(addressRepositoryProvider).list());
