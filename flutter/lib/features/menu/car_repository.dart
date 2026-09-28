import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// A car a customer saved for curbside pickup ("من السيارة"), central per
/// customer and reused at every store; the order snapshots it server-side.
class CustomerCar {
  const CustomerCar({
    required this.id,
    required this.brand,
    required this.color,
    required this.plateLetters,
    required this.plateNumbers,
    this.isDefault = false,
  });

  factory CustomerCar.fromJson(Map<String, dynamic> json) => CustomerCar(
        id: json['id'] as int,
        brand: json['brand'] as String? ?? '',
        color: json['color'] as String? ?? '',
        plateLetters: json['plate_letters'] as String? ?? '',
        plateNumbers: json['plate_numbers'] as String? ?? '',
        isDefault: json['is_default'] as bool? ?? false,
      );

  final int id;
  final String brand;
  final String color;
  final String plateLetters;
  final String plateNumbers;
  final bool isDefault;

  String get label => '$brand $color · $plateLetters $plateNumbers';
}

class CarRepository {
  const CarRepository(this._api);

  final ApiClient _api;

  Future<List<CustomerCar>> list() async {
    final json = await _api.get('/me/cars');
    final data = (json['data'] as List?) ?? const [];
    return [for (final c in data) CustomerCar.fromJson(c as Map<String, dynamic>)];
  }

  Future<void> add({
    required String brand,
    required String color,
    required String plateLetters,
    required String plateNumbers,
  }) =>
      _api.post('/me/cars', body: {
        'brand': brand,
        'color': color,
        'plate_letters': plateLetters,
        'plate_numbers': plateNumbers,
      });

  Future<void> remove(int id) => _api.delete('/me/cars/$id');
}

final carRepositoryProvider =
    Provider<CarRepository>((ref) => CarRepository(ref.watch(apiClientProvider)));

final carsProvider =
    FutureProvider<List<CustomerCar>>((ref) => ref.watch(carRepositoryProvider).list());
