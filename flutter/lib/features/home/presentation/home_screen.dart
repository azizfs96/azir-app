import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../stores/data/store_repository.dart';
import '../data/my_stores_repository.dart';
import 'store_card.dart';

/// ============================================================================
/// THE HOME SCREEN (spec §5, §46)
///
///   Good morning, Abdulaziz
///
///   My Stores
///   ┌────────────────────────┐
///   │ Glow Beauty            │
///   │ Next appointment       │
///   │ Tomorrow • 7:00 PM     │
///   │ [View Store]           │
///   └────────────────────────┘
///
/// There is NO search, NO categories, NO explore, NO nearby, NO trending.
/// The customer sees only stores they personally added by scanning a QR.
/// "The customer should not feel that Wasla is a marketplace."
/// ============================================================================
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.customerName});

  final String? customerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final stores = ref.watch(myStoresProvider);

    /*
     * Warm every visible storefront as soon as the list lands. Without
     * this, the first tap on each card paid a full network round trip
     * behind a spinner — the "opening a store is slow" complaint.
     */
    ref.listen(myStoresProvider, (previous, next) {
      final data = next.value;
      if (data != null) {
        prefetchStorefronts(ref, data.map((store) => store.token));
      }
    });

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myStoresProvider),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.greeting(customerName),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink900,
                              ),
                            ),
                          ),
                          _HomeIcon(
                              icon: Icons.notifications_none_rounded,
                              onTap: () => context.push('/notifications')),
                          const SizedBox(width: 10),
                          _HomeIcon(
                              icon: Icons.receipt_long_rounded,
                              onTap: () => context.push('/orders')),
                          const SizedBox(width: 10),
                          _HomeIcon(
                              icon: Icons.person_outline_rounded,
                              onTap: () => context.push('/profile')),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        s.myStores,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              stores.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (error, _) => SliverFillRemaining(
                  child: _ErrorState(
                    message: s.error,
                    onRetry: () => ref.invalidate(myStoresProvider),
                    retryLabel: s.retry,
                  ),
                ),
                data: (list) => list.isEmpty
                    ? SliverFillRemaining(hasScrollBody: false, child: _EmptyStores(s: s))
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                        sliver: SliverList.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            thickness: 1,
                            indent: 88, // clears the icon, App Store-style
                            color: AppColors.ink100,
                          ),
                          itemBuilder: (context, i) => StoreCard(
                            store: list[i],
                            onTap: () => context.push('/s/${list[i].token}'),
                            onRemove: () async {
                              await ref.read(myStoresRepositoryProvider).hide(list[i].token);
                              ref.invalidate(myStoresProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(s.storeRemoved), behavior: SnackBarBehavior.floating),
                                );
                              }
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      // The scanner is THE primary action — it is how every store gets here.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scan'),
        backgroundColor: AppColors.ink900,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: Text(s.scanQr),
      ),
    );
  }
}

class _HomeIcon extends StatelessWidget {
  const _HomeIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink100,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: AppColors.ink900),
        ),
      ),
    );
  }
}

class _EmptyStores extends StatelessWidget {
  const _EmptyStores({required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_2_rounded, size: 56, color: AppColors.ink300),
          const SizedBox(height: 16),
          Text(
            s.noStoresTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.ink900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // The empty state is the whole product pitch: there is nothing to
            // browse, so it tells you the one thing that works.
            s.noStoresHint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink500),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, required this.retryLabel});

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppColors.ink500)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}
