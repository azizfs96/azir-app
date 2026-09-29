import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import 'address_repository.dart';

/// ============================================================================
/// THE MAP LOCATION PICKER (feature expansion — delivery)
///
/// A real map (OpenStreetMap tiles, no API key): the customer drags the map
/// under a fixed pin, or taps "my location", and the centre is reverse-geocoded
/// to an address. Saving stores the address centrally (/me/addresses), so every
/// store inherits it — the customer sets their location ONCE in the app.
/// ============================================================================
class MapPickerScreen extends ConsumerStatefulWidget {
  const MapPickerScreen({super.key});

  @override
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  final _map = MapController();
  final _details = TextEditingController();

  // Default view: Riyadh, until we have the device location.
  LatLng _center = const LatLng(24.7136, 46.6753);
  String _label = 'home';
  String? _address;
  bool _resolving = false;
  bool _saving = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation(initial: true));
    _resolve(_center);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _details.dispose();
    super.dispose();
  }

  /// Reverse-geocode the centre into a readable address (native geocoder).
  Future<void> _resolve(LatLng point) async {
    // The native geocoder isn't available on web; the pin's coordinates still
    // save, the customer just types the address label themselves.
    if (kIsWeb) return;
    setState(() => _resolving = true);
    try {
      final marks = await geo.placemarkFromCoordinates(point.latitude, point.longitude);
      final p = marks.firstOrNull;
      final parts = [p?.subLocality, p?.thoroughfare, p?.locality]
          .where((s) => (s ?? '').isNotEmpty)
          .toList();
      setState(() => _address = parts.isEmpty ? null : parts.join('، '));
    } catch (_) {
      // Geocoding can fail offline; the pin's coordinates are still saved.
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _useMyLocation({bool initial = false}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final here = LatLng(pos.latitude, pos.longitude);
      _map.move(here, 16);
      setState(() => _center = here);
      await _resolve(here);
    } catch (_) {
      // Location unavailable — the customer can still drag the map manually.
    }
  }

  void _onMove(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (!hasGesture) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _resolve(_center));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(addressRepositoryProvider).add(
            label: _label,
            addressText: _address ?? '${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}',
            details: _details.text.trim(),
            latitude: _center.latitude,
            longitude: _center.longitude,
          );
      ref.invalidate(addressesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(s.pinYourLocation),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onPositionChanged: _onMove,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'sa.wasla.wasla',
              ),
            ],
          ),

          // A fixed pin at the centre — the map moves under it.
          IgnorePointer(
            child: Center(
              child: Padding(
                // Lift the tip so it points at the exact centre.
                padding: const EdgeInsets.only(bottom: 40),
                child: Icon(Icons.location_on, size: 48, color: AppColors.ink900),
              ),
            ),
          ),

          // "My location" button.
          PositionedDirectional(
            end: 16,
            bottom: 300,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                onTap: _useMyLocation,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.my_location_rounded, color: AppColors.ink900),
                ),
              ),
            ),
          ),

          // The address + label + confirm sheet.
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 20, color: AppColors.ink900),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _resolving ? s.locating : (_address ?? s.dragMapHint),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (final l in const ['home', 'work', 'other'])
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                label: Text(switch (l) {
                                  'work' => s.labelWork,
                                  'other' => s.labelOther,
                                  _ => s.labelHome,
                                }),
                                selected: _label == l,
                                onSelected: (_) => setState(() => _label = l),
                                selectedColor: AppColors.ink900,
                                labelStyle: TextStyle(
                                    color: _label == l ? Colors.white : AppColors.ink700,
                                    fontWeight: FontWeight.w600),
                                backgroundColor: AppColors.ink100,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                showCheckmark: false,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _details,
                        decoration: InputDecoration(
                          hintText: s.addressDetailsHint,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ink900,
                          minimumSize: const Size.fromHeight(54),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(s.confirmLocation, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
