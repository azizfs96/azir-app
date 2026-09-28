import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/strings.dart';
import 'order_repository.dart';

/// Reorder: rebuild a past order into the cart and drop the customer straight on
/// the cart, ready to check out — no re-picking items. If nothing on the order
/// is still orderable, fall back to the store menu with a short note.
Future<void> reorderAndOpenCart(
  BuildContext context,
  WidgetRef ref,
  OrderResult order,
  Strings s,
) async {
  final token = order.storeToken;
  if (token == null) return;

  final ok = await reorderIntoCart(ref, order);
  if (!context.mounted) return;

  if (ok) {
    context.push('/s/$token/cart');
  } else {
    context.push('/s/$token');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.reorderUnavailable), behavior: SnackBarBehavior.floating),
    );
  }
}
