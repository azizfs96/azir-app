import 'package:url_launcher/url_launcher.dart' as launcher;

import 'storefront.dart';

/// Opens a maps destination in the external maps app / browser.
///
/// A function variable, not a direct call: widget tests swap it for a spy —
/// there is no launching platform inside the test binding.
Future<bool> Function(Uri url) openMapUrl = (url) =>
    launcher.launchUrl(url, mode: launcher.LaunchMode.externalApplication);

/// ============================================================================
/// WHERE "الموقع" ACTUALLY TAKES YOU
///
/// One place that answers, for any storefront, "what map destinations exist?"
/// — so the tap handler and the branches sheet cannot disagree.
///
/// Rules, in order of trust:
///   1. A merchant-pasted maps URL wins — it points at the exact pin.
///   2. Coordinates from the dashboard map picker build a precise query.
///   3. Address/city text falls back to a maps SEARCH — imperfect, but a
///      customer with only "شارع العليا، الرياض" still gets somewhere useful.
///
/// Multiple branches ⇒ multiple targets ⇒ the UI shows a chooser. A store
/// whose only location data lives on the store profile yields one target.
/// ============================================================================
class MapTarget {
  const MapTarget({required this.title, required this.url, this.subtitle});

  final String title;
  final String? subtitle;
  final Uri url;
}

Uri _searchUri(String query) =>
    Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}');

Uri? _branchUri(StoreBranch branch) {
  final pasted = branch.mapsUrl;
  if (pasted != null && pasted.trim().isNotEmpty) return Uri.tryParse(pasted.trim());

  if (branch.latitude != null && branch.longitude != null) {
    return _searchUri('${branch.latitude},${branch.longitude}');
  }

  final text = [branch.address, branch.city]
      .where((v) => v != null && v.trim().isNotEmpty)
      .join('، ');

  return text.isEmpty ? null : _searchUri(text);
}

Uri? _storeUri(StoreLocation? location) {
  if (location == null) return null;

  final pasted = location.mapsUrl;
  if (pasted != null && pasted.trim().isNotEmpty) return Uri.tryParse(pasted.trim());

  final text = [location.address, location.city]
      .where((v) => v != null && v.trim().isNotEmpty)
      .join('، ');

  return text.isEmpty ? null : _searchUri(text);
}

/// Every place this store can send a customer to, best source first.
List<MapTarget> mapTargets(Storefront store) {
  final targets = <MapTarget>[
    for (final branch in store.branches)
      if (_branchUri(branch) != null)
        MapTarget(
          title: branch.name,
          subtitle: [branch.address, branch.city]
              .where((v) => v != null && v.trim().isNotEmpty)
              .join('، '),
          url: _branchUri(branch)!,
        ),
  ];

  if (targets.isNotEmpty) return targets;

  // No branch knows where it is — fall back to the store profile's location.
  final storeUri = _storeUri(store.location);

  if (storeUri == null) return const [];

  return [
    MapTarget(
      title: store.name,
      subtitle: [store.location?.address, store.location?.city]
          .where((v) => v != null && v.trim().isNotEmpty)
          .join('، '),
      url: storeUri,
    ),
  ];
}
