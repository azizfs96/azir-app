import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/session.dart';
import '../features/orders/board_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/profile/profile_screen.dart';
import 'theme.dart';

/// A route a push notification asked for before the router was ready.
final pendingDeepLink = ValueNotifier<String?>(null);

class _SessionListenable extends ChangeNotifier {
  void bump() => notifyListeners();
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = _SessionListenable();
  ref.listen(sessionProvider, (_, _) => listenable.bump());
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: Listenable.merge([listenable, pendingDeepLink]),
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final at = state.matchedLocation;

      // Still deciding: stay on the splash.
      if (session.isLoading && at == '/') return null;

      final signedIn = session.value != null;
      if (!signedIn) return at == '/login' ? null : '/login';

      // A tapped notification wins once, then is consumed.
      final link = pendingDeepLink.value;
      if (link != null) {
        pendingDeepLink.value = null;
        return link;
      }

      if (at == '/' || at == '/login') return '/orders';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/orders',
        builder: (_, _) => const BoardScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => OrderDetailScreen(orderId: int.parse(state.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(child: Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 56)),
    );
  }
}
