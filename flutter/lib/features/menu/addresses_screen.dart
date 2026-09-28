import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import 'address_repository.dart';

/// Saved delivery addresses (Jahez's "manage locations"). A live map picker
/// needs a maps SDK; until then a location is added with a short form.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final addresses = ref.watch(addressesProvider);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(s.myAddresses),
      ),
      body: addresses.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => Center(child: Text(s.error, style: const TextStyle(color: AppColors.ink500))),
        data: (list) => list.isEmpty
            ? _empty(s)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _AddressCard(
                  address: list[i],
                  s: s,
                  onDelete: () async {
                    await ref.read(addressRepositoryProvider).remove(list[i].id);
                    ref.invalidate(addressesProvider);
                  },
                ),
              ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: FilledButton.icon(
          onPressed: () => context.push('/addresses/new'),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(s.addLocation, style: const TextStyle(fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink900,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
      ),
    );
  }

  Widget _empty(Strings s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 46, color: AppColors.ink300),
              const SizedBox(height: 14),
              Text(s.noSavedLocations,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink900)),
              const SizedBox(height: 6),
              Text(s.noSavedLocationsHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.ink500)),
            ],
          ),
        ),
      );

}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address, required this.s, required this.onDelete});
  final CustomerAddress address;
  final Strings s;
  final VoidCallback onDelete;

  String _label() => switch (address.label) {
        'work' => s.labelWork,
        'other' => s.labelOther,
        _ => s.labelHome,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.location_on_rounded, color: AppColors.ink900),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(_label(),
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                    if (address.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.ink100, borderRadius: BorderRadius.circular(20)),
                        child: Text(s.defaultLabel,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink500)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(address.addressText,
                    style: const TextStyle(fontSize: 13, color: AppColors.ink500)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.ink400),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
