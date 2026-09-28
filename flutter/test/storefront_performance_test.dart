import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/stores/data/store_repository.dart';
import 'package:wasla/features/stores/presentation/store_avatar.dart';
import 'package:wasla/features/stores/domain/storefront.dart';
import 'package:wasla/features/stores/presentation/storefront_header.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// STOREFRONTS MUST OPEN FAST
///
/// Two proven causes of the "opening a store hangs" report:
///
///  1. Image.network decoded merchant uploads at FILE resolution on the UI
///     thread, mid push-animation. The fix is cacheWidth — Flutter expresses
///     it as a ResizeImage provider, which is what these tests assert.
///  2. The first tap on every store card paid a full network round trip
///     behind a spinner: nothing warmed the storefront cache from home.
/// ============================================================================
void main() {
  Widget host(Widget child) => MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: Strings.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      );

  group('decode-size caps', () {
    testWidgets('the avatar decodes at display size, not file size', (tester) async {
      await tester.pumpWidget(host(const StoreAvatar(
        name: 'Glow',
        logoPath: 'stores/1/logo.jpg',
        brandColor: '#111111',
        size: 56,
      )));

      final image = tester.widget<Image>(find.byType(Image));

      expect(
        image.image,
        isA<ResizeImage>(),
        reason: 'No cacheWidth: the full merchant upload is decoded on the UI thread.',
      );
    });

    testWidgets('the cover decodes at (capped) screen width', (tester) async {
      final store = storefrontFixture();

      await tester.pumpWidget(host(StorefrontHeader(
        store: Storefront.fromJson({
          'store': {
            'token': store.token,
            'name': store.name,
            'cover': 'stores/1/cover.jpg',
          },
          'configuration': const <String, dynamic>{},
          'flow': const <dynamic>[],
          'services': const <dynamic>[],
          'staff': const <dynamic>[],
          'branches': const <dynamic>[],
        }),
        s: const Strings(Locale('ar')),
        brand: Colors.black,
        onShare: () {},
      )));

      final images = tester.widgetList<Image>(find.byType(Image));

      expect(images, isNotEmpty);
      expect(
        images.every((image) => image.image is ResizeImage),
        isTrue,
        reason: 'The cover must carry a decode cap.',
      );

      final resize = images.first.image as ResizeImage;
      expect(resize.width, isNotNull);
      expect(resize.width!, lessThanOrEqualTo(1600));
    });
  });

  group('storefront prefetch', () {
    testWidgets('prefetch resolves every visible store once', (tester) async {
      final stores = FakeStoreRepository(storefront: storefrontFixture());

      await tester.pumpWidget(ProviderScope(
        overrides: [storeRepositoryProvider.overrideWithValue(stores)],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            return TextButton(
              onPressed: () =>
                  prefetchStorefronts(ref, const ['AAAA1111', 'BBBB2222', 'CCCC3333']),
              child: const Text('go'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('go'));
      await tester.pump();

      expect(stores.resolveCalls, 3, reason: 'Every listed store should be warmed.');

      // Warming again must serve from the provider cache, not refetch.
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(stores.resolveCalls, 3, reason: 'Prefetch must never re-fetch a cached store.');
    });
  });
}
