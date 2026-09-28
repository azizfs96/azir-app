import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../auth/data/auth_repository.dart';

/// The signed-in customer's account screen (Jahez's profile tab): identity, then
/// links to their orders, addresses and help.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final me = ref.watch(_meProvider);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(s.myAccount),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(color: AppColors.ink900, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(
                    (me.value?.name.characters.firstOrNull ?? '؟').toString(),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 14),
                Text(me.value?.name ?? '—',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                if ((me.value?.phone ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(me.value!.phone,
                      style: const TextStyle(fontSize: 14, color: AppColors.ink500)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          _MenuCard(children: [
            _Tile(icon: Icons.receipt_long_rounded, label: s.myOrders, onTap: () => context.push('/orders')),
            _Tile(icon: Icons.location_on_outlined, label: s.myAddresses, onTap: () => context.push('/addresses')),
            _Tile(icon: Icons.directions_car_outlined, label: s.myCars, onTap: () => context.push('/cars')),
            _Tile(icon: Icons.help_outline_rounded, label: s.help, onTap: () => _showHelp(context, s)),
          ]),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) context.go('/');
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.bad,
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(s.signOut, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context, Strings s) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppColors.ink100, borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: const Text('؟', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 16),
              Text(s.needHelp,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink900)),
              const SizedBox(height: 8),
              Text(s.helpBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppColors.ink500)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink900,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.call_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(s.contactRestaurant, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(s.close, style: const TextStyle(color: AppColors.ink500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.ink100, indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.ink900),
      title: Text(label,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.ink900)),
      trailing: const Icon(Icons.chevron_left_rounded, color: AppColors.ink400),
    );
  }
}

// ---- profile fetch ---------------------------------------------------------

class _Me {
  const _Me({required this.name, required this.phone});
  final String name;
  final String phone;
}

final _meProvider = FutureProvider<_Me>((ref) async {
  final json = await ref.watch(apiClientProvider).get('/me');
  return _Me(
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
  );
});
