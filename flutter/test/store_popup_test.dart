import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/stores/domain/storefront.dart';
import 'package:wasla/features/stores/presentation/store_popup.dart';

/// The merchant's pop-up ad: shown on entry, honouring the frequency the
/// merchant chose, and never re-shown after "once".
void main() {
  Storefront storeWith(List<StorePopup> popups) => Storefront.fromJson({
        'store': {'token': 'TESTSTR1', 'name': 'متجر', 'type': 'restaurant'},
        'popups': [
          for (final p in popups)
            {'id': p.id, 'image': p.image, 'title': p.title, 'frequency': p.frequency},
        ],
      });

  Future<void> pump(WidgetTester tester, Storefront store) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: Strings.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => maybeShowStorePopups(context, store),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the pop-up with its title on entry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester, storeWith(const [
      StorePopup(id: 1, image: 'stores/1/popups/a.jpg', title: 'عرض الافتتاح', frequency: 'every_visit'),
    ]));
    expect(find.text('عرض الافتتاح'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('a "once" pop-up is not shown again after it was seen', (tester) async {
    SharedPreferences.setMockInitialValues({'popup.seen.7': 1});
    await pump(tester, storeWith(const [
      StorePopup(id: 7, image: 'stores/1/popups/b.jpg', title: 'مرة واحدة', frequency: 'once'),
    ]));
    expect(find.text('مرة واحدة'), findsNothing);
  });

  testWidgets('a "once per day" pop-up seen yesterday shows again today', (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({'popup.seen.9': yesterday});
    await pump(tester, storeWith(const [
      StorePopup(id: 9, image: 'stores/1/popups/c.jpg', title: 'يومي', frequency: 'once_per_day'),
    ]));
    expect(find.text('يومي'), findsOneWidget);
  });

  testWidgets('pop-ups without an image are ignored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = Storefront.fromJson({
      'store': {'token': 'TESTSTR1', 'name': 'x', 'type': 'restaurant'},
      'popups': [
        {'id': 3, 'image': null, 'title': 'بدون صورة', 'frequency': 'every_visit'},
      ],
    });
    expect(store.popups, isEmpty);
  });
}
