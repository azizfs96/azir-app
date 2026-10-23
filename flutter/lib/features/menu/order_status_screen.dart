import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/session_cache.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/riyal_price.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/top_banner.dart';
import '../stores/data/store_repository.dart';
import 'order_repository.dart';
import 'reorder_action.dart';

/// ============================================================================
/// ORDER TRACKING (RestaurantEngine) — the Jahez tracking screen: a status hero
/// with the ETA, the restaurant/pickup-code card, and a timed step timeline.
/// The status is authoritative on the server; the screen refetches rather than
/// guessing.
/// ============================================================================
class OrderStatusScreen extends ConsumerStatefulWidget {
  const OrderStatusScreen({super.key, required this.orderId, this.justPlaced = false});

  final int orderId;

  /// True when reached straight from checkout: the screen opens on a clear
  /// confirmation of the just-placed order, which then settles into tracking.
  final bool justPlaced;

  @override
  ConsumerState<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

/// The forward-only lifecycle the tracker draws as a timeline.
const _orderSteps = ['placed', 'accepted', 'preparing', 'ready', 'completed'];

class _OrderStatusScreenState extends ConsumerState<OrderStatusScreen> with WidgetsBindingObserver {
  static const _terminal = {'completed', 'rejected', 'cancelled'};

  Timer? _poll;

  /// The just-placed confirmation is shown once, as a top notification banner
  /// rather than an inline card — guarded so a refetch/rebuild can't repeat it.
  bool _placedBannerShown = false;

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
        // A skeleton in the shape of the tracker, not a bare spinner — it keeps
        // the layout stable so the real content swaps in without a white flash.
        loading: () => const _TrackingSkeleton(),
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
        data: (data) {
          // Confirmation as a top notification banner (not an inline card):
          // shown once, only when we arrived from checkout on a freshly placed
          // order. It states one true fact — we have the order — and points to
          // the next step, never claiming the restaurant has accepted it yet.
          if (widget.justPlaced && !_placedBannerShown && data.status == 'placed') {
            _placedBannerShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              showTopBanner(context, title: s.orderPlaced, message: s.orderReceivedHint);
            });
          }
          // While the restaurant hasn't accepted yet, the screen wears a
          // distinct "waiting" design; once accepted, it becomes the live
          // tracking timeline. The two cross-fade as the status flips.
          final waiting = data.status == 'placed';
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(orderProvider(orderId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AnimatedSwitcher(
                  duration: AppMotion.dur(context, AppMotion.base),
                  child: KeyedSubtree(
                    key: ValueKey(waiting),
                    child: waiting ? _WaitingHero(order: data, s: s) : _Hero(order: data, s: s),
                  ),
                ),
              const SizedBox(height: 14),
              _RestaurantCard(order: data, s: s),
              if (!waiting && data.status != 'rejected' && data.status != 'cancelled') ...[
                const SizedBox(height: 14),
                _Timeline(order: data, s: s),
              ],
              if (data.items.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ItemsCard(order: data, s: s),
              ],
              // The invoice appears only once the restaurant has accepted the
              // order — not while it's still waiting, and not for a rejected or
              // cancelled order (which never became a sale).
              if (!waiting &&
                  data.status != 'rejected' &&
                  data.status != 'cancelled' &&
                  data.invoice?.qr != null) ...[
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
                    invalidateOrderCaches(ref);
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
          );
        },
      ),
    );
  }
}

/// The waiting state — shown while the order is placed but not yet accepted.
/// A deliberately different, calmer design from the tracking timeline: an
/// hourglass inside softly pulsing rings that say "the restaurant is looking at
/// this now", with the order reference. No timeline and no ETA — there is
/// nothing real to time until the kitchen accepts.
class _WaitingHero extends StatefulWidget {
  const _WaitingHero({required this.order, required this.s});
  final OrderResult order;
  final Strings s;

  @override
  State<_WaitingHero> createState() => _WaitingHeroState();
}

class _WaitingHeroState extends State<_WaitingHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final reduce = AppMotion.reduced(context);

    // Boxless and airy: the animation sits directly on the page's cream canvas,
    // large and calm, with a minimal step indicator underneath.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Column(
        children: [
          SizedBox(
            width: 156,
            height: 156,
            child: reduce
                ? Center(child: _center())
                : AnimatedBuilder(
                    animation: _c,
                    builder: (_, _) => Stack(
                      alignment: Alignment.center,
                      children: [
                        for (var i = 0; i < 3; i++) _ring((_c.value + i / 3) % 1.0),
                        _center(),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 26),
          Text(
            s.waitingAcceptTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink900),
          ),
          const SizedBox(height: 10),
          Text(
            s.waitingAcceptHint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.ink500),
          ),
          const SizedBox(height: 22),
          // Minimal progress: four segments, the first active while we wait.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  width: 22,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == 0 ? AppColors.flame : AppColors.ink200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// One expanding, fading ring on the cream canvas. [t] runs 0→1: it grows
  /// outward and dissolves.
  Widget _ring(double t) {
    return Opacity(
      opacity: (1 - t) * 0.5,
      child: Container(
        width: 66 + t * 88,
        height: 66 + t * 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.flame, width: 1.6),
        ),
      ),
    );
  }

  Widget _center() => Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.flame.withValues(alpha: 0.14),
          border: Border.all(color: AppColors.flame.withValues(alpha: 0.45)),
        ),
        child: const Icon(Icons.hourglass_top_rounded, color: AppColors.flame, size: 32),
      );
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
class _RestaurantCard extends ConsumerWidget {
  const _RestaurantCard({required this.order, required this.s});
  final OrderResult order;
  final Strings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The store's phone comes from its (already-cached) storefront; the call
    // button only appears when there is actually a number to dial.
    final token = order.storeToken;
    final phone = token == null ? null : ref.watch(storefrontProvider(token)).value?.phone;

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
          if (phone != null && phone.isNotEmpty)
            Material(
              color: AppColors.ink100,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
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

/// The loading placeholder: the tracker's own silhouette — hero, restaurant card,
/// timeline — in the same paddings as the real content, so data swaps in without
/// the layout shifting.
class _TrackingSkeleton extends StatelessWidget {
  const _TrackingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        SkeletonBox(height: 108, radius: 24, color: AppColors.ink200),
        SizedBox(height: 14),
        SkeletonCard(height: 74),
        SizedBox(height: 14),
        SkeletonCard(height: 220),
      ],
    );
  }
}
