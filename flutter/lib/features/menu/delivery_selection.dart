import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which saved address / car the customer chose for THIS order. Null means "use
/// the default" (the first in the list). Kept in providers so the cart's picker
/// and the checkout agree.
class SelectedId extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? id) => state = id;
}

final selectedAddressIdProvider = NotifierProvider<SelectedId, int?>(SelectedId.new);
final selectedCarIdProvider = NotifierProvider<SelectedId, int?>(SelectedId.new);

/// Which pickup branch the customer chose at THIS store (keyed by store
/// token). Null = nothing chosen yet. Keyed per store so a branch picked at
/// one store can never satisfy — or be sent for — another store's order.
class SelectedBranch extends Notifier<int?> {
  SelectedBranch(this.token);
  final String token;

  @override
  int? build() => null;

  void set(int? id) => state = id;
}

final selectedBranchIdProvider =
    NotifierProvider.family<SelectedBranch, int?, String>(SelectedBranch.new);

/// How many people a dine-in order is for. Required before a dine-in order can
/// be placed; null until the customer chooses.
final partySizeProvider = NotifierProvider<SelectedId, int?>(SelectedId.new);
