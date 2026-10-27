import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push_service.dart';
import 'core/router.dart';
import 'core/strings.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Push is optional: without a Firebase config the app still runs, the
  // driver just relies on the board's refresh.
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  runApp(const ProviderScope(child: DriverApp()));
}

/// Easy App Driver — the delivery app for a merchant's drivers.
class DriverApp extends ConsumerStatefulWidget {
  const DriverApp({super.key});

  @override
  ConsumerState<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends ConsumerState<DriverApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final push = ref.read(pushServiceProvider);
      push.registerIfSignedIn();
      push.wireOrderTaps((orderId) => pendingDeepLink.value = '/orders/$orderId');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Easy App Driver',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: ref.watch(appRouterProvider),
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
