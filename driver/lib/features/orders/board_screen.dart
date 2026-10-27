import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/session.dart';
import '../location/location_heartbeat.dart';
import 'order_model.dart';
import 'order_repository.dart';

/// The driver's home: three boards (available / mine / past) that refresh on
/// a short interval while the app is in the foreground.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> with WidgetsBindingObserver {
  static const _interval = Duration(seconds: 20);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_interval, (_) => ref.invalidate(boardProvider));
    // Make sure location sharing is armed from the first frame.
    ref.read(heartbeatProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(boardProvider);
      ref.read(heartbeatProvider.notifier).retry();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final session = ref.watch(sessionProvider).value;
    final heartbeat = ref.watch(heartbeatProvider);

    return DefaultTabController(
      length: 3,
      initialIndex: 1,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.board),
              if (session != null)
                Text(
                  session.store.name,
                  style: const TextStyle(color: AppColors.ink2, fontSize: 13, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: s.profile,
              onPressed: () => context.push('/profile'),
              icon: const Icon(Icons.account_circle_outlined, size: 28),
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: s.tabAvailable),
              Tab(text: s.tabMine),
              Tab(text: s.tabPast),
            ],
          ),
        ),
        body: Column(
          children: [
            _HeartbeatBanner(heartbeat),
            const Expanded(
              child: TabBarView(
                children: [
                  _BoardList(BoardFilter.available),
                  _BoardList(BoardFilter.mine),
                  _BoardList(BoardFilter.past),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sharing your location" / "permission denied" strip under the tabs.
class _HeartbeatBanner extends ConsumerWidget {
  const _HeartbeatBanner(this.state);

  final HeartbeatState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final (text, fg, bg, icon, action) = switch (state.status) {
      HeartbeatStatus.sharing => (
        s.trackingOn,
        AppColors.info,
        AppColors.infoSoft,
        Icons.my_location_rounded,
        null,
      ),
      HeartbeatStatus.permissionDenied => (
        s.locationDenied,
        AppColors.bad,
        AppColors.badSoft,
        Icons.location_off_rounded,
        () => Geolocator.openAppSettings(),
      ),
      HeartbeatStatus.serviceDisabled => (
        s.locationOff,
        AppColors.bad,
        AppColors.badSoft,
        Icons.location_disabled_rounded,
        () => Geolocator.openLocationSettings(),
      ),
      HeartbeatStatus.idle => (null, AppColors.ink, AppColors.bg, Icons.circle, null),
    };

    return AnimatedSize(
      duration: AppMotion.dur(context, AppMotion.base),
      curve: AppMotion.curve,
      alignment: Alignment.topCenter,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: bg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (action != null)
                    TextButton(
                      onPressed: action,
                      style: TextButton.styleFrom(foregroundColor: fg, visualDensity: VisualDensity.compact),
                      child: Text(s.openSettings),
                    ),
                ],
              ),
            ),
    );
  }
}

class _BoardList extends ConsumerWidget {
  const _BoardList(this.filter);

  final BoardFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final orders = ref.watch(boardProvider(filter));

    Future<void> refresh() async {
      ref.invalidate(boardProvider(filter));
      await ref.read(boardProvider(filter).future).catchError((_) => const <DriverOrder>[]);
    }

    return RefreshIndicator(
      color: AppColors.ink,
      onRefresh: refresh,
      child: orders.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.ink)),
        error: (e, _) {
          final f = ApiFailure.from(e);
          return ListView(
            children: [
              SizedBox(
                height: 400,
                child: ErrorView(
                  message: f.fromServer
                      ? f.message
                      : (f.statusCode == null ? s.offlineError : s.genericError),
                  onRetry: refresh,
                ),
              ),
            ],
          );
        },
        data: (list) {
          if (list.isEmpty) {
            final (icon, title, hint) = switch (filter) {
              BoardFilter.available => (Icons.inbox_outlined, s.emptyAvailable, s.emptyAvailableHint),
              BoardFilter.mine => (Icons.two_wheeler_rounded, s.emptyMine, s.emptyMineHint),
              BoardFilter.past => (Icons.history_rounded, s.emptyPast, null),
            };
            return ListView(
              children: [
                SizedBox(
                  height: 420,
                  child: EmptyState(icon: icon, title: title, hint: hint),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _OrderCard(list[i]),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard(this.order);

  final DriverOrder order;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final time = order.createdAt == null ? '' : DateFormat('HH:mm').format(order.createdAt!);
    final distance = order.delivery?.distanceKm;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/orders/${order.id}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.orderNumber(order.reference),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  StatusChip(order.status),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.ink3),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.customerName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, size: 18, color: AppColors.ink3),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.delivery?.address ?? '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.ink2, height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Meta(Icons.schedule_rounded, time),
                  const SizedBox(width: 14),
                  if (distance != null) ...[
                    _Meta(Icons.route_rounded, s.km(distance)),
                    const SizedBox(width: 14),
                  ],
                  _Meta(Icons.shopping_bag_outlined, '${order.itemCount}'),
                  const Spacer(),
                  Text(
                    '${order.total.toStringAsFixed(2)} ${s.currency}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.ink3),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppColors.ink2, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
