import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';

/// ============================================================================
/// LIVE DELIVERY TRACKING — the driver's position between the restaurant and
/// the customer's door, polled every 5 s only while the order is on the road.
/// ============================================================================

class OrderTracking {
  const OrderTracking({
    required this.status,
    required this.driverName,
    required this.driverPhone,
    required this.driverVehicle,
    required this.driverLat,
    required this.driverLng,
    required this.driverHeading,
    required this.driverFresh,
    required this.etaMinutes,
    required this.originLat,
    required this.originLng,
    required this.originName,
    required this.destLat,
    required this.destLng,
    required this.distanceKm,
  });

  final String status;
  final String? driverName;
  final String? driverPhone;
  final String? driverVehicle;
  final double? driverLat;
  final double? driverLng;
  final int? driverHeading;
  final bool driverFresh;
  final int? etaMinutes;
  final double? originLat;
  final double? originLng;
  final String? originName;
  final double? destLat;
  final double? destLng;
  final double? distanceKm;

  bool get hasDriver => driverName != null;

  bool get hasDriverPosition => driverLat != null && driverLng != null;

  factory OrderTracking.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] as Map<String, dynamic>?;
    final loc = json['driver_location'] as Map<String, dynamic>?;
    final origin = json['origin'] as Map<String, dynamic>?;
    final dest = json['destination'] as Map<String, dynamic>?;
    double? d(Object? v) => (v as num?)?.toDouble();

    return OrderTracking(
      status: json['status'] as String? ?? '',
      driverName: driver?['name'] as String?,
      driverPhone: driver?['phone'] as String?,
      driverVehicle: driver?['vehicle'] as String?,
      driverLat: d(loc?['latitude']),
      driverLng: d(loc?['longitude']),
      driverHeading: (loc?['heading'] as num?)?.toInt(),
      driverFresh: loc?['fresh'] as bool? ?? false,
      etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
      originLat: d(origin?['latitude']),
      originLng: d(origin?['longitude']),
      originName: origin?['name'] as String?,
      destLat: d(dest?['latitude']),
      destLng: d(dest?['longitude']),
      distanceKm: d(json['distance_km']),
    );
  }
}

final orderTrackingProvider = FutureProvider.autoDispose.family<OrderTracking, int>(
  (ref, id) async => OrderTracking.fromJson(await ref.watch(apiClientProvider).get('/orders/$id/tracking')),
);

/// The driver card + map. Shown for a delivery order once a driver is assigned;
/// the map (and the 5 s polling) only runs while the order is out for delivery.
class DeliveryTrackingCard extends ConsumerStatefulWidget {
  const DeliveryTrackingCard({super.key, required this.orderId, required this.moving, required this.s});

  final int orderId;

  /// status == out_for_delivery — the only time the position is live.
  final bool moving;
  final Strings s;

  @override
  ConsumerState<DeliveryTrackingCard> createState() => _DeliveryTrackingCardState();
}

class _DeliveryTrackingCardState extends ConsumerState<DeliveryTrackingCard> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant DeliveryTrackingCard old) {
    super.didUpdateWidget(old);
    if (old.moving != widget.moving) _sync();
  }

  void _sync() {
    _poll?.cancel();
    _poll = null;
    if (widget.moving) {
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => ref.invalidate(orderTrackingProvider(widget.orderId)));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final tracking = ref.watch(orderTrackingProvider(widget.orderId)).value;
    if (tracking == null || !tracking.hasDriver) return const SizedBox.shrink();

    final driverPoint = tracking.hasDriverPosition ? LatLng(tracking.driverLat!, tracking.driverLng!) : null;
    final dest = tracking.destLat != null && tracking.destLng != null ? LatLng(tracking.destLat!, tracking.destLng!) : null;
    final origin = tracking.originLat != null && tracking.originLng != null
        ? LatLng(tracking.originLat!, tracking.originLng!)
        : null;
    final points = [driverPoint ?? origin, dest].whereType<LatLng>().toList();
    final showMap = widget.moving && points.isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          if (showMap)
            SizedBox(
              height: 200,
              child: _TrackingMap(points: points, driver: driverPoint, origin: origin, dest: dest, heading: tracking.driverHeading),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(color: AppColors.infoSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.two_wheeler_rounded, color: AppColors.info, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.driverLabel, style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
                      Text(
                        [tracking.driverName, tracking.driverVehicle].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink900),
                      ),
                      if (widget.moving) ...[
                        const SizedBox(height: 3),
                        Text(
                          tracking.etaMinutes != null
                              ? s.etaMinutes(tracking.etaMinutes!)
                              : (tracking.hasDriverPosition ? s.driverOnTheWay : s.waitingDriverLocation),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: tracking.driverFresh ? AppColors.ok : AppColors.ink500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (tracking.driverPhone != null && tracking.driverPhone!.isNotEmpty)
                  Material(
                    color: AppColors.ink100,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => launchUrl(Uri(scheme: 'tel', path: tracking.driverPhone)),
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(11),
                        child: Icon(Icons.call_rounded, size: 20, color: AppColors.ink900),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingMap extends StatefulWidget {
  const _TrackingMap({required this.points, required this.driver, required this.origin, required this.dest, required this.heading});

  final List<LatLng> points;
  final LatLng? driver;
  final LatLng? origin;
  final LatLng? dest;
  final int? heading;

  @override
  State<_TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<_TrackingMap> {
  final _controller = MapController();
  bool _fitted = false;

  @override
  void didUpdateWidget(covariant _TrackingMap old) {
    super.didUpdateWidget(old);
    // Follow the driver without fighting the customer's own panning: re-fit
    // only when the set of pins changes (driver appeared), not on every tick.
    if (old.points.length != widget.points.length) _fitted = false;
    if (!_fitted && widget.points.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(widget.points), padding: const EdgeInsets.all(40)));
        _fitted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.points.length >= 2
        ? MapOptions(
            initialCameraFit: CameraFit.bounds(bounds: LatLngBounds.fromPoints(widget.points), padding: const EdgeInsets.all(40)),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
          )
        : MapOptions(
            initialCenter: widget.points.first,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
          );

    return FlutterMap(
      mapController: _controller,
      options: options,
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'sa.azir.app'),
        if (widget.driver != null && widget.dest != null)
          PolylineLayer(
            polylines: [
              Polyline(points: [widget.driver!, widget.dest!], color: AppColors.info.withValues(alpha: 0.6), strokeWidth: 3, pattern: const StrokePattern.dotted()),
            ],
          ),
        MarkerLayer(
          markers: [
            if (widget.origin != null)
              Marker(point: widget.origin!, width: 36, height: 36, child: const _Pin(Icons.storefront_rounded, AppColors.ink900)),
            if (widget.dest != null)
              Marker(point: widget.dest!, width: 36, height: 36, child: const _Pin(Icons.home_rounded, AppColors.bad)),
            if (widget.driver != null)
              Marker(
                point: widget.driver!,
                width: 40,
                height: 40,
                child: Transform.rotate(
                  angle: (widget.heading ?? 0) * 3.141592653589793 / 180,
                  child: const _Pin(Icons.navigation_rounded, AppColors.info),
                ),
              ),
          ],
        ),
      ],
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
      child: Icon(icon, color: color, size: 20),
    );
  }
}
