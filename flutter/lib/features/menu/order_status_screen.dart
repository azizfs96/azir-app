import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/riyal_price.dart';
import 'order_repository.dart';
import 'reorder_action.dart';

/// ============================================================================
/// ORDER TRACKING (RestaurantEngine) — the Jahez tracking screen: a status hero
/// with the ETA, the restaurant/pickup-code card, and a timed step timeline.
/// The status is authoritative on the server; the screen refetches rather than
/// guessing.
/// ============================================================================
class OrderStatusScreen extends ConsumerStatefulWidget {
  const OrderStatusScreen({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

/// The forward-only lifecycle the tracker draws as a timeline.
const _orderSteps = ['placed', 'accepted', 'preparing', 'ready', 'completed'];

class _OrderStatusScreenState extends ConsumerState<OrderStatusScreen> with WidgetsBindingObserver {
  static const _terminal = {'completed', 'rejected', 'cancelled'};

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The status is authoritative on the server and changes from the merchant's
    // dashboard, so the tracker refetches while the order is still in flight —
    // the push tells the customer, this keeps the screen in step. Polling stops
    // once the order reaches a terminal state (nothing more will change).
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      final status = ref.read(orderProvider(widget.orderId)).value?.status;
      if (status != null && _terminal.contains(status)) {
        _poll?.cancel();
        return;
      }
      ref.invalidate(orderProvider(widget.orderId));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from a push notification: refresh immediately.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(orderProvider(widget.orderId));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.orderId;
    final s = Strings.of(context);
    final order = ref.watch(orderProvider(orderId));

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(s.trackOrder),
      ),
      body: order.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.error, style: const TextStyle(color: AppColors.ink500)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(orderProvider(orderId)),
                child: Text(s.retry),
              ),
            ],
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(orderProvider(orderId)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Hero(order: data, s: s),
              const SizedBox(height: 14),
              _RestaurantCard(order: data, s: s),
              const SizedBox(height: 14),
              if (data.status != 'rejected' && data.status != 'cancelled')
                _Timeline(order: data, s: s),
              if (data.items.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ItemsCard(order: data, s: s),
              ],
              if (data.invoice?.qr != null) ...[
                const SizedBox(height: 14),
                _ViewInvoiceTile(orderId: data.id, s: s),
              ],
              const SizedBox(height: 20),
              if (data.status == 'completed' && data.storeToken != null)
                FilledButton(
                  onPressed: () => reorderAndOpenCart(context, ref, data, s),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ink900,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: Text(s.orderAgain, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              if (data.status == 'completed') const SizedBox(height: 12),
              if (data.status == 'placed')
                OutlinedButton(
                  onPressed: () async {
                    await ref.read(orderRepositoryProvider).cancel(orderId);
                    ref.invalidate(orderProvider(orderId));
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.bad,
                    side: const BorderSide(color: AppColors.badSoft),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(s.cancelOrder),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark status hero: fulfilment + current status on the start, an ETA ring
/// on the end. Terminal orders show a message instead of an ETA.
class _Hero extends StatelessWidget {
  const _Hero({required this.order, required this.s});
  final OrderResult order;
  final Strings s;

  String _statusText() => switch (order.status) {
        'placed' => s.orderStatusPlaced,
        'accepted' => s.orderStatusAccepted,
        'preparing' => s.orderStatusPreparing,
        'ready' => s.orderStatusReady,
        'completed' => s.orderStatusCompleted,
        'rejected' => s.orderStatusRejected,
        _ => s.orderStatusCancelled,
      };

  @override
  Widget build(BuildContext context) {
    final terminal = order.status == 'rejected' || order.status == 'cancelled';
    final eta = order.prepMinutes;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.ink900,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.fulfillmentLabel(order.fulfillmentType),
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text(_statusText(),
                    style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7))),
              ],
            ),
          ),
          if (!terminal && eta != null)
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$eta',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text(s.orderMinutes,
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
                ],
              ),
            )
          else
            Icon(order.status == 'rejected' ? Icons.cancel_rounded : Icons.info_outline_rounded,
                size: 34, color: Colors.white.withValues(alpha: 0.85)),
        ],
      ),
    );
  }
}

/// The restaurant + pickup-code card, with a call action.
class _RestaurantCard extends StatelessWidget {
  const _RestaurantCard({required this.order, required this.s});
  final OrderResult order;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    final isDelivery = order.fulfillmentType == 'delivery';
    final subtitle = isDelivery
        ? (order.deliveryAddress ?? '')
        : '${s.orderReference(order.reference)} · ${s.orderCode} ${order.pickupCode}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(color: AppColors.ink900, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              (order.storeName ?? '؟').characters.first,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.storeName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
                ],
              ],
            ),
          ),
          Material(
            color: AppColors.ink100,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: () {},
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(11),
                child: Icon(Icons.call_rounded, size: 20, color: AppColors.ink900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order, required this.s});
  final OrderResult order;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          for (final line in order.items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${line.quantity} × ${line.name}',
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                      if (line.options.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(line.options.join('، '),
                            style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                RiyalPrice(amount: line.lineTotal, size: 14),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const Divider(height: 1, color: AppColors.ink100),
          const SizedBox(height: 12),
          if (order.deliveryFee > 0 || order.taxAmount > 0) ...[
            _totalRow(s.subtotal, order.subtotal, bold: false),
            const SizedBox(height: 8),
            if (order.deliveryFee > 0) ...[
              _totalRow(s.deliveryFeeLabel, order.deliveryFee, bold: false),
              const SizedBox(height: 8),
            ],
            if (order.taxAmount > 0) ...[
              _totalRow(s.vat, order.taxAmount, bold: false),
              const SizedBox(height: 8),
            ],
          ],
          _totalRow(s.total, order.total, bold: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {required bool bold}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 16 : 14,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: bold ? AppColors.ink900 : AppColors.ink500)),
          RiyalPrice(amount: value, size: bold ? 16 : 14, weight: bold ? FontWeight.w800 : FontWeight.w700),
        ],
      );
}

/// "View invoice" — opens the full ZATCA simplified tax invoice on its own page.
class _ViewInvoiceTile extends StatelessWidget {
  const _ViewInvoiceTile({required this.orderId, required this.s});
  final int orderId;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/orders/$orderId/invoice'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, size: 22, color: AppColors.ink900),
            const SizedBox(width: 12),
            Expanded(
              child: Text(s.viewInvoice,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink900)),
            ),
            const Icon(Icons.chevron_left_rounded, color: AppColors.ink400),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order, required this.s});
  final OrderResult order;
  final Strings s;

  String _label(String step) => switch (step) {
        'placed' => s.orderStatusPlaced,
        'accepted' => s.orderStatusAccepted,
        'preparing' => s.orderStatusPreparing,
        'ready' => s.orderStatusReady,
        _ => s.orderStatusCompleted,
      };

  String _time(String step) {
    final dt = switch (step) {
      'placed' => order.createdAt,
      'accepted' => order.acceptedAt,
      'ready' => order.readyAt,
      _ => null,
    };
    if (dt == null) return '';
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final steps = _orderSteps;
    final current = steps.indexOf(order.status);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _Step(
              label: _label(steps[i]),
              time: _time(steps[i]),
              done: i <= current,
              active: i == current,
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.time,
    required this.done,
    required this.active,
    required this.isLast,
  });

  final String label;
  final String time;
  final bool done;
  final bool active;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.ink900 : AppColors.ink300;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(done ? Icons.check_rounded : Icons.circle, size: 12, color: Colors.white),
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: done ? AppColors.ink900 : AppColors.ink100)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: done ? AppColors.ink900 : AppColors.ink400,
                        )),
                  ),
                  if (time.isNotEmpty)
                    Text(time, style: const TextStyle(fontSize: 12.5, color: AppColors.ink400)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
