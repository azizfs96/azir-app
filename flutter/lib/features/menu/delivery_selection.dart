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

/// Which pickup branch the customer chose. Null = the store's default (first).
final selectedBranchIdProvider = NotifierProvider<SelectedId, int?>(SelectedId.new);
