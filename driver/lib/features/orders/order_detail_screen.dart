import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/env.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'order_model.dart';
import 'order_repository.dart';

/// One delivery: where to pick up, where to go, who to call, and the single
/// next action (claim → picked up → delivered).
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The kitchen marks "ready" from the dashboard; keep the button current.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      final order = ref.read(orderProvider(widget.orderId)).value;
      if (order != null && order.isTerminal) return;
      ref.invalidate(orderProvider(widget.orderId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<DriverOrder> Function(OrderRepository repo) action, {String? toast}) async {
    final s = Strings.of(context);
    setState(() => _busy = true);
    try {
      await action(ref.read(orderRepositoryProvider));
      AppHaptics.success();
      invalidateOrders(ref);
      if (mounted && toast != null) showSnack(context, toast);
    } catch (e) {
      final f = ApiFailure.from(e);
      invalidateOrders(ref);
      if (!mounted) return;
      showSnack(
        context,
        f.isAlreadyTaken
            ? s.takenByOther
            : (f.fromServer ? f.message : (f.statusCode == null ? s.offlineError : s.genericError)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelivered() async {
    final s = Strings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deliveredConfirmTitle),
        content: Text(s.deliveredConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    if (yes == true) await _run((repo) => repo.updateStatus(widget.orderId, 'completed'));
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final order = ref.watch(orderProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        title: Text(order.value == null ? s.board : s.orderNumber(order.value!.reference)),
        actions: [
          IconButton(
            tooltip: s.refresh,
            onPressed: () => ref.invalidate(orderProvider(widget.orderId)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: order.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.ink)),
        error: (e, _) {
          final f = ApiFailure.from(e);
          return ErrorView(
            message: f.statusCode == 404 ? s.takenByOther : (f.fromServer ? f.message : s.genericError),
            onRetry: () => ref.invalidate(orderProvider(widget.orderId)),
          );
        },
        data: (o) => _Body(
          order: o,
          busy: _busy,
          onClaim: () => _run((r) => r.claim(o.id), toast: s.claimed),
          onPickUp: () => _run((r) => r.updateStatus(o.id, 'out_for_delivery')),
          onDelivered: _confirmDelivered,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.order,
    required this.busy,
    required this.onClaim,
    required this.onPickUp,
    required this.onDelivered,
  });

  final DriverOrder order;
  final bool busy;
  final VoidCallback onClaim;
  final VoidCallback onPickUp;
  final VoidCallback onDelivered;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final delivery = order.delivery;
    final phone = order.customerPhone;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _MapCard(order: order),
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(order.status),
                        const Spacer(),
                        if (delivery?.distanceKm != null)
                          Text(
                            s.km(delivery!.distanceKm!),
                            style: const TextStyle(color: AppColors.ink2, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    LabeledValue(
                      label: s.customer,
                      value: order.customerName ?? '—',
                      trailing: phone == null || phone.isEmpty
                          ? null
                          : RoundAction(
                              icon: Icons.call_rounded,
                              tooltip: s.callCustomer,
                              onTap: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                            ),
                    ),
                    const SizedBox(height: 14),
                    LabeledValue(
                      label: s.address,
                      value: [
                        delivery?.address,
                        delivery?.details,
                      ].whereType<String>().where((x) => x.isNotEmpty).join(' — '),
                      trailing: delivery?.hasPin == true
                          ? RoundAction(
                              icon: Icons.navigation_rounded,
                              tooltip: s.openInMaps,
                              onTap: () => _openMaps(delivery!.latitude!, delivery.longitude!),
                            )
                          : null,
                    ),
                    if (delivery?.hasPin == true) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _openMaps(delivery!.latitude!, delivery.longitude!),
                        icon: const Icon(Icons.map_outlined, size: 20),
                        label: Text(s.openInMaps),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(s.noPin, style: const TextStyle(color: AppColors.ink3, fontSize: 13)),
                    ],
                    if (order.branch != null) ...[
                      const SizedBox(height: 14),
                      LabeledValue(
                        label: s.pickupFrom,
                        value: [
                          order.branch!.name,
                          order.branch!.address,
                        ].whereType<String>().where((x) => x.isNotEmpty).join(' — '),
                      ),
                    ],
                    if (order.customerNotes != null && order.customerNotes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      LabeledValue(label: s.notes, value: order.customerNotes!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.items,
                      style: const TextStyle(
                        color: AppColors.ink3,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final line in order.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.soft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${line.quantity}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(line.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  if (line.options.isNotEmpty)
                                    Text(
                                      line.options.join(' · '),
                                      style: const TextStyle(color: AppColors.ink3, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        Text(
                          s.total,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink2),
                        ),
                        const Spacer(),
                        Text(
                          '${order.total.toStringAsFixed(2)} ${s.currency}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _ActionBar(order: order, busy: busy, onClaim: onClaim, onPickUp: onPickUp, onDelivered: onDelivered),
      ],
    );
  }

  /// Google Maps app when installed (iOS scheme / Android handles the https
  /// intent), otherwise the universal directions URL in the browser.
  static Future<void> _openMaps(double lat, double lng) async {
    if (Platform.isIOS) {
      final app = Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
      if (await canLaunchUrl(app)) {
        await launchUrl(app);
        return;
      }
    }
    final web = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }
}

/// The one button that matters for this order's state.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.order,
    required this.busy,
    required this.onClaim,
    required this.onPickUp,
    required this.onDelivered,
  });

  final DriverOrder order;
  final bool busy;
  final VoidCallback onClaim;
  final VoidCallback onPickUp;
  final VoidCallback onDelivered;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    Widget? child;
    if (order.isTerminal) {
      child = null;
    } else if (order.isClaimable) {
      child = PrimaryButton(
        label: s.claim,
        icon: Icons.pan_tool_alt_rounded,
        onPressed: onClaim,
        loading: busy,
      );
    } else if (order.isUnassigned) {
      child = null;
    } else if (order.isBeingPrepared) {
      child = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(color: AppColors.warnSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.soup_kitchen_outlined, color: AppColors.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.waitingKitchen,
                style: const TextStyle(color: AppColors.warn, fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
          ],
        ),
      );
    } else if (order.isReadyForPickup) {
      child = PrimaryButton(
        label: s.pickUp,
        icon: Icons.two_wheeler_rounded,
        onPressed: onPickUp,
        loading: busy,
      );
    } else if (order.isOutForDelivery) {
      child = PrimaryButton(
        label: s.delivered,
        icon: Icons.check_circle_rounded,
        color: AppColors.ok,
        onPressed: onDelivered,
        loading: busy,
      );
    }

    return AnimatedSize(
      duration: AppMotion.dur(context, AppMotion.base),
      curve: AppMotion.curve,
      child: child == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: child,
            ),
    );
  }
}

/// Pickup point and destination on one map, fitted to both.
class _MapCard extends StatelessWidget {
  const _MapCard({required this.order});

  final DriverOrder order;

  @override
  Widget build(BuildContext context) {
    final dest = order.delivery?.hasPin == true
        ? LatLng(order.delivery!.latitude!, order.delivery!.longitude!)
        : null;
    final origin = order.branch?.hasPin == true
        ? LatLng(order.branch!.latitude!, order.branch!.longitude!)
        : null;
    final points = [origin, dest].whereType<LatLng>().toList();

    if (points.isEmpty) return const SizedBox.shrink();

    final options = points.length == 2
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(44),
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          )
        : MapOptions(
            initialCenter: points.first,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: options,
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: Env.packageName,
            ),
            if (points.length == 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    color: AppColors.ink.withValues(alpha: 0.35),
                    strokeWidth: 3,
                    pattern: const StrokePattern.dotted(),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (origin != null)
                  Marker(
                    point: origin,
                    width: 40,
                    height: 40,
                    child: const _Pin(Icons.storefront_rounded, AppColors.ink),
                  ),
                if (dest != null)
                  Marker(
                    point: dest,
                    width: 40,
                    height: 40,
                    child: const _Pin(Icons.location_on_rounded, AppColors.bad),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
