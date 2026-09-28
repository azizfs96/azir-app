import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/phone_screen.dart';
import '../../features/booking/data/booking_repository.dart';
import '../../features/booking/presentation/booking_flow_screen.dart';
import '../../features/booking/presentation/confirmation_screen.dart';
import '../../features/menu/cart_screen.dart';
import '../../features/menu/order_status_screen.dart';
import '../../features/menu/orders_screen.dart';
import '../../features/menu/invoice_screen.dart';
import '../../features/menu/addresses_screen.dart';
import '../../features/menu/profile_screen.dart';
import '../../features/menu/menu_search_screen.dart';
import '../../features/menu/cars_screen.dart';
import '../../features/menu/map_picker_screen.dart';
import '../../features/menu/notifications_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/qr_scanner/presentation/scanner_screen.dart';
import '../../features/stores/domain/storefront.dart';
import '../../features/stores/presentation/storefront_screen.dart';

/// Routing and deep links (spec §7, §38).
///
/// The path shape matches the public link exactly — wasla.sa/s/8F72K maps to
/// /s/8F72K — so an incoming Universal Link / App Link needs no translation.
///
/// NOTE what is absent (spec §46): there is no /search, /explore, /nearby or
/// /categories route. The app cannot navigate to a marketplace because none
/// exists.
/// Where /booking/confirmed may go, given what the route was handed.
///
/// A plain function rather than an inline closure so the crash it prevents —
/// `state.extra!` on a restored or hand-typed navigation — stays covered by a
/// unit test that needs no router at all.
String? confirmedRouteGuard(Object? extra) =>
    extra is BookingResult ? null : '/';

/// A deep link to navigate to as soon as the router can honour it — set when the
/// customer taps a push notification. Going through the router's own
/// refreshListenable makes the navigation reliable even on a cold launch, where
/// pushing directly is dropped before the first route settles.
final pendingDeepLink = ValueNotifier<String?>(null);

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: pendingDeepLink,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScannerScreen(),
      ),
      GoRoute(
        path: '/signin',
        builder: (context, state) => PhoneScreen(
          redirectTo: state.uri.queryParameters['next'],
        ),
      ),

      // THE DEEP LINK TARGET. Both a QR scan and a Universal Link land here.
      GoRoute(
        path: '/s/:token',
        builder: (context, state) => StorefrontScreen(
          token: state.pathParameters['token']!,
        ),
        routes: [
          GoRoute(
            path: 'cart',
            builder: (context, state) => CartScreen(
              token: state.pathParameters['token']!,
            ),
          ),
          GoRoute(
            path: 'search',
            builder: (context, state) => MenuSearchScreen(
              token: state.pathParameters['token']!,
            ),
          ),
          GoRoute(
            path: 'book',
            builder: (context, state) => BookingFlowScreen(
              token: state.pathParameters['token']!,
              preselectedService: state.extra as StoreService?,
            ),
          ),
        ],
      ),

      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrdersScreen(),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) => OrderStatusScreen(
          orderId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/orders/:id/invoice',
        builder: (context, state) => InvoiceScreen(
          orderId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/addresses',
        builder: (context, state) => const AddressesScreen(),
      ),
      GoRoute(
        path: '/addresses/new',
        builder: (context, state) => const MapPickerScreen(),
      ),
      GoRoute(
        path: '/cars',
        builder: (context, state) => const CarsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

      GoRoute(
        path: '/booking/confirmed',
        // The booking arrives as route `extra`, which survives a normal
        // pushReplacement but NOT a process restart or a hand-typed deep
        // link — `state.extra!` crashed on those. With nothing to show, home
        // is the only honest destination.
        redirect: (context, state) => confirmedRouteGuard(state.extra),
        builder: (context, state) => ConfirmationScreen(
          booking: state.extra! as BookingResult,
        ),
      ),
    ],

    /*
     * Authentication is required to OPEN A STORE (and therefore to book/order).
     *
     * Opening a store adds it to My Stores, which needs an identity — so we sign
     * the customer in first, then land them on the store, which is saved for
     * them. Only the home screen, the scanner and sign-in itself stay open.
     */
    redirect: (context, state) async {
      // A tapped notification asked to open a specific screen: honour it once,
      // then fall through to the normal auth checks for that destination.
      final pending = pendingDeepLink.value;
      if (pending != null && state.matchedLocation != pending) {
        pendingDeepLink.value = null;
        return pending;
      }

      final loc = state.matchedLocation;
      final needsAuth = loc.startsWith('/s/') ||
          loc.endsWith('/book') ||
          loc.startsWith('/orders') ||
          loc == '/profile' ||
          loc.startsWith('/addresses') ||
          loc == '/cars' ||
          loc == '/notifications';
      if (!needsAuth) return null;

      final signedIn = await ref.read(authRepositoryProvider).isSignedIn();
      if (signedIn) return null;

      return '/signin?next=${Uri.encodeComponent(loc)}';
    },
  );
});
