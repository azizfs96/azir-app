import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/stores/domain/map_targets.dart';
import 'package:wasla/features/stores/domain/storefront.dart';
import 'package:wasla/features/stores/presentation/store_locations_sheet.dart';

/// ============================================================================
/// "الموقع" MUST GO SOMEWHERE
///
/// The header exposed an onOpenMap callback that no screen ever passed, so
/// tapping the location tile did nothing at all. And the tile was only
/// tappable when the STORE PROFILE had a pasted maps link — a merchant who
/// set locations on their branches (the normal case) got an inert tile.
///
/// The rule now: one destination opens directly; a multi-branch merchant gets
/// a chooser naming each branch with its address.
/// ============================================================================
void main() {
  Storefront storeWith({
    List<Map<String, dynamic>> branches = const [],
    Map<String, dynamic>? location,
  }) {
    return Storefront.fromJson({
      'store': {'token': 'ABC12345', 'name': 'Glow Beauty'},
      'configuration': const <String, dynamic>{},
      'flow': const <dynamic>[],
      'services': const <dynamic>[],
      'staff': const <dynamic>[],
      'branches': branches,
      'location': ?location,
    });
  }

  group('mapTargets — where the tap goes', () {
    test('a pasted branch link wins as-is', () {
      final targets = mapTargets(storeWith(branches: [
        {'id': 1, 'name': 'العليا', 'google_maps_url': 'https://maps.app.goo.gl/xyz'},
      ]));

      expect(targets, hasLength(1));
      expect(targets.first.url.toString(), 'https://maps.app.goo.gl/xyz');
    });

    test('dashboard-picked coordinates build a precise query', () {
      final targets = mapTargets(storeWith(branches: [
        {'id': 1, 'name': 'العليا', 'latitude': 24.7136, 'longitude': 46.6753},
      ]));

      expect(targets.first.url.toString(),
          'https://www.google.com/maps/search/?api=1&query=24.7136%2C46.6753');
    });

    test('address text falls back to a maps search', () {
      final targets = mapTargets(storeWith(branches: [
        {'id': 1, 'name': 'العليا', 'address': 'شارع العليا', 'city': 'الرياض'},
      ]));

      final url = targets.first.url.toString();
      expect(url, contains('maps/search'));
      expect(url, contains(Uri.encodeComponent('شارع العليا، الرياض')));
    });

    test('every located branch becomes a target, unlocated ones are skipped', () {
      final targets = mapTargets(storeWith(branches: [
        {'id': 1, 'name': 'العليا', 'google_maps_url': 'https://maps.app.goo.gl/a'},
        {'id': 2, 'name': 'النخيل', 'address': 'حي النخيل', 'city': 'الرياض'},
        {'id': 3, 'name': 'بدون موقع'},
      ]));

      expect(targets.map((t) => t.title), ['العليا', 'النخيل']);
    });

    test('with no located branches the store profile location is the target', () {
      final targets = mapTargets(storeWith(
        branches: [
          {'id': 3, 'name': 'بدون موقع'},
        ],
        location: {'maps_url': 'https://maps.app.goo.gl/store'},
      ));

      expect(targets, hasLength(1));
      expect(targets.first.title, 'Glow Beauty');
      expect(targets.first.url.toString(), 'https://maps.app.goo.gl/store');
    });

    test('nothing anywhere means no targets — and an untappable tile', () {
      expect(mapTargets(storeWith()), isEmpty);
    });
  });

  group('the chooser sheet', () {
    /// A minimal host exercising the same decision the storefront makes:
    /// one target → launch; several → sheet; each row launches its own URL.
    Future<List<Uri>> pumpAndTap(WidgetTester tester, Storefront store) async {
      final launched = <Uri>[];
      openMapUrl = (url) async {
        launched.add(url);
        return true;
      };

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: Strings.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: _LocationHost(store: store),
      ));

      await tester.tap(find.text('الموقع'));
      await tester.pumpAndSettle();

      return launched;
    }

    testWidgets('a single destination opens immediately, no sheet', (tester) async {
      final launched = await pumpAndTap(
        tester,
        storeWith(branches: [
          {'id': 1, 'name': 'العليا', 'google_maps_url': 'https://maps.app.goo.gl/a'},
        ]),
      );

      expect(launched.single.toString(), 'https://maps.app.goo.gl/a');
      expect(find.text('الفروع والمواقع'), findsNothing);
    });

    testWidgets('two branches raise the chooser, and a row opens ITS map',
        (tester) async {
      final launched = await pumpAndTap(
        tester,
        storeWith(branches: [
          {'id': 1, 'name': 'العليا', 'google_maps_url': 'https://maps.app.goo.gl/a'},
          {
            'id': 2,
            'name': 'النخيل',
            'address': 'حي النخيل',
            'google_maps_url': 'https://maps.app.goo.gl/b',
          },
        ]),
      );

      // Nothing launched yet — the customer chooses first.
      expect(launched, isEmpty);
      expect(find.text('الفروع والمواقع'), findsOneWidget);
      expect(find.text('العليا'), findsOneWidget);
      expect(find.text('النخيل'), findsOneWidget);
      expect(find.text('حي النخيل'), findsOneWidget);

      await tester.tap(find.text('النخيل'));
      await tester.pumpAndSettle();

      expect(launched.single.toString(), 'https://maps.app.goo.gl/b');
      expect(find.text('الفروع والمواقع'), findsNothing, reason: 'The sheet must close.');
    });
  });
}

/// Hosts the REAL production sheet — not a copy of its logic.
class _LocationHost extends StatelessWidget {
  const _LocationHost({required this.store});

  final Storefront store;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Scaffold(
      body: Center(
        child: TextButton(
          child: Text(s.location),
          onPressed: () => openStoreLocations(
            context,
            store: store,
            s: s,
            brand: Colors.black,
          ),
        ),
      ),
    );
  }
}
