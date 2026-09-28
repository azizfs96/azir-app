import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/stores/domain/storefront.dart';
import 'package:wasla/features/stores/presentation/storefront_header.dart';

/// ============================================================================
/// THE STOREFRONT BACK ARROW WORKS FROM BOTH ENTRY PATHS
///
/// The storefront is reached two ways, and the back arrow must lead home from
/// each:
///   · PUSHED from the home list      → pop back to home
///   · go()'d from the confirmation   → stack was replaced, nothing to pop,
///     so fall back to go('/')
///
/// Returning here from confirmation with go() left the storefront as the root;
/// maybePop() then did nothing and the arrow looked dead. This pins both.
/// ============================================================================
void main() {
  Storefront store() => Storefront.fromJson({
        'store': {'token': 'FGEE5Y2M', 'name': 'Glow Beauty'},
        'configuration': const <String, dynamic>{},
        'flow': const <dynamic>[],
        'services': const <dynamic>[],
        'staff': const <dynamic>[],
        'branches': const <dynamic>[],
      });

  Widget header() => StorefrontHeader(
        store: store(),
        s: const Strings(Locale('ar')),
        brand: Colors.black,
        onShare: () {},
      );

  GoRouter buildRouter({required String initial}) => GoRouter(
        initialLocation: initial,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('APP_HOME')),
          GoRoute(
            path: '/s/:token',
            builder: (_, _) => Scaffold(body: header()),
          ),
        ],
      );

  Future<void> pump(WidgetTester tester, GoRouter router) async {
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      locale: const Locale('ar'),
      supportedLocales: Strings.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ));
    await tester.pumpAndSettle();
  }

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

  testWidgets('pushed onto home: back pops to home', (tester) async {
    final router = buildRouter(initial: '/');
    await pump(tester, router);

    router.push('/s/FGEE5Y2M');
    await tester.pumpAndSettle();
    expect(location(router), '/s/FGEE5Y2M');

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.text('APP_HOME'), findsOneWidget);
  });

  testWidgets('go-rooted (post-confirmation): back falls to app home',
      (tester) async {
    // Exactly the confirmation screen's go('/s/token') — the storefront is now
    // the stack root with nothing beneath it.
    final router = buildRouter(initial: '/s/FGEE5Y2M');
    await pump(tester, router);

    expect(location(router), '/s/FGEE5Y2M');

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text('APP_HOME'),
      findsOneWidget,
      reason: 'The back arrow was dead — nothing to pop and no fallback.',
    );
    expect(location(router), '/');
  });
}
