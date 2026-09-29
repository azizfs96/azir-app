import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/strings.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase powers push notifications (order updates). A failure here must not
  // stop the app from launching — iOS reads GoogleService-Info.plist itself.
  // On web there is no native Firebase config and push isn't wired, so skip it.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // App runs without push rather than not at all.
    }
  }

  runApp(const ProviderScope(child: WaslaApp()));
}

/// Wasla — وصلة
///
///   امسح، وادخل مباشرة  ·  Scan, and enter directly
///
/// One customer app, many merchants, each reached by their own QR code.
class WaslaApp extends ConsumerStatefulWidget {
  const WaslaApp({super.key});

  @override
  ConsumerState<WaslaApp> createState() => _WaslaAppState();
}

class _WaslaAppState extends ConsumerState<WaslaApp> {
  @override
  void initState() {
    super.initState();
    // Keep an already-signed-in customer's push token fresh on every launch,
    // and send a tapped order notification to that order's tracking screen.
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final push = ref.read(pushServiceProvider);
        push.registerIfSignedIn();
        push.wireOrderTaps((orderId) => pendingDeepLink.value = '/orders/$orderId');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Wasla',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: ref.watch(appRouterProvider),

      /*
       * Arabic-first (spec §32, §33).
       *
       * ar is listed first, so it is chosen for any device whose language is
       * not English. Directionality flows from the locale, and every screen is
       * laid out RTL-first and checked LTR — that ordering catches the bugs
       * that a translated-afterwards app ships with.
       */
      locale: const Locale('ar'),
      supportedLocales: Strings.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
