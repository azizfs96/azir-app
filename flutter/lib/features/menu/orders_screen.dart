import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/riyal_price.dart';
import '../stores/presentation/store_avatar.dart';
import 'order_repository.dart';
import 'reorder_action.dart';

/// ============================================================================
/// MY ORDERS (RestaurantEngine) — the Jahez orders list: a card per order with
/// its status, date, number and total, and an action (track for a live order,
/// reorder for a finished one).
/// ============================================================================
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final active = ref.watch(myOrdersProvider('active'));
    final past = ref.watch(myOrdersProvider('past'));

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(s.myOrders),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myOrdersProvider('active'));
          ref.invalidate(myOrdersProvider('past'));
        },
        child: (active.isLoading || past.isLoading)
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Builder(
                builder: (_) {
                  final orders = [...?active.value, ...?past.value];
                  if (orders.isEmpty) return _empty(s);
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _OrderCard(order: orders[i], s: s),
                  );
                },
              ),
      ),
    );
  }

  Widget _empty(Strings s) => ListView(
        children: [
          const SizedBox(height: 160),
          const Icon(Icons.receipt_long_rounded, size: 44, color: AppColors.ink300),
          const SizedBox(height: 14),
          Text(s.noOrders,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink900)),
        ],
      );
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, required this.s});
  final OrderResult order;
  final Strings s;

  bool get _active => const ['placed', 'accepted', 'preparing', 'ready'].contains(order.status);

  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    final ampm = l.hour < 12 ? 'ص' : 'م';
    return '${l.day} ${_months[l.month - 1]} ${l.year} · $h:$m $ampm';
  }

  // Jahez shows every order's state in green; only a rejected/cancelled order
  // reads as an error.
  ({String label, Color fg, Color bg}) _badge() {
    if (order.status == 'rejected') {
      return (label: s.orderStatusRejected, fg: AppColors.bad, bg: AppColors.badSoft);
    }
    if (order.status == 'cancelled') {
      return (label: s.orderStatusCancelled, fg: AppColors.bad, bg: AppColors.badSoft);
    }
    final label = switch (order.status) {
      'completed' => order.fulfillmentType == 'delivery' ? s.orderDelivered : s.orderReceived,
      'ready' => s.orderStatusReady,
      _ => s.orderPreparing,
    };
    return (label: label, fg: AppColors.ok, bg: AppColors.okSoft);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = _badge();
    final date = _formatDate(order.createdAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: badge.bg, borderRadius: BorderRadius.circular(20)),
                child: Text(badge.label,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: badge.fg)),
              ),
              const Spacer(),
              Text(date, style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.ink100),
          ),
          Row(
            children: [
              _Thumbs(items: order.items),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.orderReference(order.reference),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
                  const SizedBox(height: 4),
                  RiyalPrice(amount: order.total, size: 15),
                ],
              ),
              const Spacer(),
              _action(context, ref),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, WidgetRef ref) {
    if (_active) {
      return _btn(context, s.track, filled: false, onTap: () => context.push('/orders/${order.id}'));
    }
    return _btn(context, s.reorder, filled: true, onTap: () => reorderAndOpenCart(context, ref, order, s));
  }

  Widget _btn(BuildContext context, String label, {required bool filled, required VoidCallback onTap}) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: filled ? AppColors.ink900 : AppColors.ink100,
        foregroundColor: filled ? Colors.white : AppColors.ink900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// Up to two dish thumbnails with a "+N" badge for the rest — the reference's
/// order-card imagery.
class _Thumbs extends StatelessWidget {
  const _Thumbs({required this.items});
  final List<OrderLineResult> items;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(2).toList();
    final extra = items.length - shown.length;

    return SizedBox(
      width: shown.length > 1 ? 84 : 52,
      height: 52,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            PositionedDirectional(
              start: i * 32.0,
              child: _thumb(shown[i].image),
            ),
          if (extra > 0)
            PositionedDirectional(
              start: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.ink900, borderRadius: BorderRadius.circular(10)),
                child: Text('+$extra',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumb(String? path) {
    final url = logoUrlOf(path);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.restaurant_rounded, size: 20, color: AppColors.ink300))
          : const Icon(Icons.restaurant_rounded, size: 20, color: AppColors.ink300),
    );
  }
}
