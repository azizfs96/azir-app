import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/session_cache.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/inline_error.dart';
import '../../core/widgets/riyal_price.dart';
import '../stores/data/store_repository.dart';
import '../stores/domain/storefront.dart';
import '../stores/presentation/store_avatar.dart';
import '../../core/network/api_client.dart';
import '../auth/data/auth_repository.dart';
import 'address_repository.dart';
import 'car_repository.dart';
import 'cart_controller.dart';
import 'delivery_selection.dart';
import 'fulfillment.dart';
import 'order_repository.dart';

/// ============================================================================
/// THE CART / ORDER REVIEW (RestaurantEngine) — the Jahez cart, exactly:
/// dish rows with a thumbnail and a stepper, the fulfilment pills (shared with
/// the storefront header), the branch, a discount field, the totals, and the
/// place-order bar. The chosen fulfilment mode drives the order.
/// ============================================================================
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final cart = ref.watch(cartForStoreProvider(token));
    final store = ref.watch(storefrontProvider(token)).value;

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(s.cart),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.ink900),
              onPressed: () => ref.read(cartProvider.notifier).clear(),
            ),
        ],
      ),
      body: cart.isEmpty
          ? _EmptyCart(s: s)
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      for (final line in cart.lines) ...[
                        _CartItemCard(
                          line: line,
                          s: s,
                          onChanged: (q) =>
                              ref.read(cartProvider.notifier).setQuantity(line.signature, q),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 4),
                      if (store != null) _FulfillmentCard(token: token, store: store, s: s),
                      const SizedBox(height: 12),
                      _ContextCard(token: token, s: s),
                      const SizedBox(height: 12),
                      _TotalsCard(
                        subtotal: cart.total,
                        s: s,
                        deliveryFee: _deliveryFee(ref, token, store),
                      ),
                    ],
                  ),
                ),
                _CheckoutBar(
                  token: token,
                  subtotal: cart.total,
                  deliveryFee: _deliveryFee(ref, token, store),
                  s: s,
                ),
              ],
            ),
    );
  }

  /// The delivery fee applies only when delivery is the chosen mode.
  double _deliveryFee(WidgetRef ref, String token, Storefront? store) {
    if (store == null) return 0;
    final mode = ref.watch(modeForStoreProvider(token));
    return mode == FulfillmentMode.delivery ? store.configuration.deliveryFee : 0;
  }
}

/// One dish row: thumbnail on the start (right), text in the middle, the
/// quantity stepper on the end (left) — the reference's layout.
class _CartItemCard extends StatelessWidget {
  const _CartItemCard({required this.line, required this.s, required this.onChanged});

  final CartLine line;
  final Strings s;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = line.chosenOptions.map((o) => o.name).join('، ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 84,
              height: 84,
              child: ColoredBox(color: AppColors.cream, child: _thumb(line.item.image)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                if (options.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(options,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.ink500)),
                ],
                const SizedBox(height: 8),
                RiyalPrice(amount: line.lineTotal, size: 16),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Stepper(quantity: line.quantity, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _thumb(String? path) {
    return AppImage(
      url: logoUrlOf(path),
      fit: BoxFit.cover,
      error: const Icon(Icons.restaurant_rounded, size: 26, color: AppColors.ink300),
    );
  }
}

/// "+ 1 −" — plus (black) on the end/left, minus (grey) on the start/right, as
/// the reference shows it.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _sq(Icons.remove_rounded, AppColors.ink100, AppColors.ink900, () {
          AppHaptics.tick();
          onChanged(quantity - 1);
        }),
        SizedBox(
          width: 34,
          child: Text('$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        _sq(Icons.add_rounded, AppColors.ink900, Colors.white, () {
          AppHaptics.tick();
          onChanged(quantity + 1);
        }),
      ],
    );
  }

  Widget _sq(IconData icon, Color bg, Color fg, VoidCallback onTap) => Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 20, color: fg)),
        ),
      );
}

/// Fulfilment pills (shared with the header) + the branch row, in one card.
class _FulfillmentCard extends ConsumerWidget {
  const _FulfillmentCard({required this.token, required this.store, required this.s});

  final String token;
  final Storefront store;
  final Strings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = enabledModes(store.configuration);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fulfillmentModeProvider.notifier).ensureDefault(token, modes);
    });
    final selected = ref.watch(modeForStoreProvider(token)) ?? (modes.isNotEmpty ? modes.first : null);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                for (final m in modes) ...[
                  Expanded(
                    child: _ModeChip(
                      mode: m,
                      selected: m == selected,
                      s: s,
                      onTap: () => ref.read(fulfillmentModeProvider.notifier).set(token, m),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (store.branches.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.ink100),
            Builder(builder: (context) {
              // A single-branch store shows its only branch (used automatically).
              if (store.branches.length == 1) {
                final b = store.branches.first;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                  child: Row(
                    children: [
                      const Icon(Icons.storefront_rounded, size: 22, color: AppColors.ink900),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.name,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                            if ((b.address ?? '').isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(b.address!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Multiple branches: choose inline (no modal, no extra step) — the
              // options are right there and one tap picks. Nothing is pre-selected
              // so the customer can't miss it and order from the wrong branch.
              final selId = ref.watch(selectedBranchIdProvider(token));
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(s.selectBranch,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink500)),
                    ),
                    for (final b in store.branches)
                      _BranchOption(
                        name: b.name,
                        address: b.address,
                        selected: b.id == selId,
                        onTap: () {
                          AppHaptics.tick();
                          ref.read(selectedBranchIdProvider(token).notifier).set(b.id);
                        },
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

}

/// One selectable branch, chosen inline in the cart (no modal). A clear radio +
/// flame highlight makes the current choice obvious at a glance.
class _BranchOption extends StatelessWidget {
  const _BranchOption({
    required this.name,
    required this.address,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String? address;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.dur(context, AppMotion.fast),
        curve: AppMotion.curve,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.flame.withValues(alpha: 0.08) : AppColors.cream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.flame : AppColors.ink200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator.
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.flame : AppColors.ink300, width: 2),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: AppColors.flame, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                  if ((address ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(address!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode, required this.selected, required this.s, required this.onTap});

  final FulfillmentMode mode;
  final bool selected;
  final Strings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7E2D9) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(mode.icon, size: 19, color: AppColors.ink900),
            const SizedBox(height: 5),
            Text(mode.label(s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.ink900)),
          ],
        ),
      ),
    );
  }
}

/// The mode-specific requirement: a delivery order shows the address to send to,
/// a curbside order shows the car to bring the food to. Either can be added or
/// changed here, so the customer is never sent to a dead end.
class _ContextCard extends ConsumerWidget {
  const _ContextCard({required this.token, required this.s});
  final String token;
  final Strings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeForStoreProvider(token));

    if (mode == FulfillmentMode.delivery) {
      final addresses = ref.watch(addressesProvider).value ?? const [];
      final selId = ref.watch(selectedAddressIdProvider);
      final chosen = _pick(addresses, selId, (a) => a.id);
      return _row(
        context,
        icon: Icons.location_on_rounded,
        title: chosen?.addressText ?? s.addDeliveryAddress,
        actionLabel: chosen != null ? s.change : s.addLocation,
        onTap: chosen != null
            ? () => _chooseAddress(context, ref, addresses)
            : () => context.push('/addresses/new'),
      );
    }

    if (mode == FulfillmentMode.curbside) {
      final cars = ref.watch(carsProvider).value ?? const [];
      final selId = ref.watch(selectedCarIdProvider);
      final chosen = _pick(cars, selId, (c) => c.id);
      return _row(
        context,
        icon: Icons.directions_car_rounded,
        title: chosen?.label ?? s.addCarForCurbside,
        actionLabel: chosen != null ? s.change : s.addCar,
        onTap: chosen != null
            ? () => _chooseCar(context, ref, cars)
            : () => context.push('/cars'),
      );
    }

    // Dine-in requires the party size before the order can be placed.
    if (mode == FulfillmentMode.dineIn) {
      final size = ref.watch(partySizeProvider);
      return _row(
        context,
        icon: Icons.groups_rounded,
        title: size == null ? s.selectPartySize : '${s.partySize}: ${s.partySizeLabel(size)}',
        actionLabel: size == null ? s.select : s.change,
        onTap: () => _pickPartySize(context, ref),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _pickPartySize(BuildContext context, WidgetRef ref) {
    final current = ref.read(partySizeProvider);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.partySize,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink900)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var n = 1; n <= 12; n++)
                    GestureDetector(
                      onTap: () {
                        AppHaptics.tick();
                        ref.read(partySizeProvider.notifier).set(n);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: n == current ? AppColors.ink900 : AppColors.cream,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: n == current ? AppColors.ink900 : AppColors.ink200),
                        ),
                        child: Text('$n',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: n == current ? Colors.white : AppColors.ink900)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  /// The selected item (by id) or the default (first) one.
  static T? _pick<T>(List<T> items, int? selectedId, int Function(T) idOf) {
    for (final it in items) {
      if (idOf(it) == selectedId) return it;
    }
    return items.isEmpty ? null : items.first;
  }

  Future<void> _chooseAddress(BuildContext context, WidgetRef ref, List<CustomerAddress> addresses) {
    return _chooser<CustomerAddress>(
      context, ref,
      items: addresses,
      title: s.myAddresses,
      icon: Icons.location_on_rounded,
      labelOf: (a) => a.addressText,
      onSelect: (a) => ref.read(selectedAddressIdProvider.notifier).set(a.id),
      onAdd: () => context.push('/addresses/new'),
      addLabel: s.addLocation,
    );
  }

  Future<void> _chooseCar(BuildContext context, WidgetRef ref, List<CustomerCar> cars) {
    return _chooser<CustomerCar>(
      context, ref,
      items: cars,
      title: s.myCars,
      icon: Icons.directions_car_rounded,
      labelOf: (c) => c.label,
      onSelect: (c) => ref.read(selectedCarIdProvider.notifier).set(c.id),
      onAdd: () => context.push('/cars'),
      addLabel: s.addCar,
    );
  }

  Future<void> _chooser<T>(
    BuildContext context,
    WidgetRef ref, {
    required List<T> items,
    required String title,
    required IconData icon,
    required String Function(T) labelOf,
    required void Function(T) onSelect,
    required VoidCallback onAdd,
    required String addLabel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink900)),
              const SizedBox(height: 12),
              for (final it in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: AppColors.ink900),
                  title: Text(labelOf(it),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  onTap: () {
                    onSelect(it);
                    Navigator.of(context).pop();
                  },
                ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAdd();
                },
                icon: const Icon(Icons.add_rounded, color: AppColors.flame),
                label: Text(addLabel, style: const TextStyle(color: AppColors.flame, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context,
      {required IconData icon,
      required String title,
      required String actionLabel,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.ink900),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink900)),
              ),
              const SizedBox(width: 8),
              Text(actionLabel,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.flame)),
            ],
          ),
        ),
      ),
    );
  }
}

// The discount-code field is hidden until promotions exist on the server —
// a code entry that can only ever say "invalid" is friction, not a feature.

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.subtotal, required this.deliveryFee, required this.s});

  final double subtotal;
  final double deliveryFee;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          _row(s.subtotal, subtotal, bold: false),
          if (deliveryFee > 0) ...[
            const SizedBox(height: 10),
            _row(s.deliveryFeeLabel, deliveryFee, bold: false),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.ink100),
          ),
          _row(s.total, subtotal + deliveryFee, bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, double value, {required bool bold}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 17 : 14.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: bold ? AppColors.ink900 : AppColors.ink500)),
          RiyalPrice(amount: value, size: bold ? 17 : 14.5, weight: bold ? FontWeight.w800 : FontWeight.w700),
        ],
      );
}

/// The fixed place-order bar.
class _CheckoutBar extends ConsumerStatefulWidget {
  const _CheckoutBar({
    required this.token,
    required this.subtotal,
    required this.deliveryFee,
    required this.s,
  });

  final String token;
  final double subtotal;
  final double deliveryFee;
  final Strings s;

  @override
  ConsumerState<_CheckoutBar> createState() => _CheckoutBarState();
}

/// The place-order lifecycle the bar reflects. Kept explicit so the button label
/// ("Sending" vs "Checking") and the double-submit guard read from one source.
enum _CheckoutPhase { idle, sending, verifying }

class _CheckoutBarState extends ConsumerState<_CheckoutBar> {
  _CheckoutPhase _phase = _CheckoutPhase.idle;
  String? _error;

  bool get _busy => _phase != _CheckoutPhase.idle;

  Future<void> _place() async {
    // Double-submit prevention: while a submission is in flight the button is
    // already disabled, and this guards the programmatic retry path too.
    if (_busy || _submitting) return;
    // Claim the submission BEFORE the first await: the pre-flight checks below
    // (sign-in, addresses, cars) take time, and a second tap during them used
    // to reach `place()` as well — two real orders. Released on every exit.
    _submitting = true;
    try {
      await _placeChecked();
    } finally {
      _submitting = false;
    }
  }

  bool _submitting = false;

  Future<void> _placeChecked() async {
    final s = widget.s;

    // Sign-in is required only here, at checkout. A guest builds the cart
    // freely; when they commit to ordering, send them to sign in and return
    // to this same cart (the cart state survives the in-app navigation).
    final signedIn = await ref.read(authRepositoryProvider).isSignedIn();
    if (!signedIn) {
      if (!mounted) return;
      final next = Uri.encodeComponent('/s/${widget.token}/cart');
      context.push('/signin?next=$next');
      return;
    }

    final mode = ref.read(modeForStoreProvider(widget.token)) ?? FulfillmentMode.pickup;
    final cart = ref.read(cartForStoreProvider(widget.token));

    // Branch must be chosen explicitly when the store has more than one, so an
    // order never silently goes to the wrong branch. One-branch stores are used
    // automatically (nothing to choose).
    final store = ref.read(storefrontProvider(widget.token)).value;
    final branches = store?.branches ?? const [];
    // Only a branch that belongs to THIS store counts as chosen; anything else
    // (a stale id) is treated as "nothing chosen" and never sent.
    final chosenBranch = ref.read(selectedBranchIdProvider(widget.token));
    final branchId = branches.any((b) => b.id == chosenBranch) ? chosenBranch : null;
    if (branches.length > 1 && branchId == null) {
      if (!mounted) return;
      setState(() => _error = s.selectBranchRequired);
      return;
    }

    // Delivery needs a saved address; curbside needs a saved car. Pull the
    // customer's default; prompt to add one if they have none.
    int? addressId;
    int? carId;
    if (mode == FulfillmentMode.delivery) {
      final addresses = await ref.read(addressesProvider.future);
      if (addresses.isEmpty) {
        if (!mounted) return;
        // Not a dead end: take them to add an address, then come back.
        context.push('/addresses');
        return;
      }
      // Honour the address the customer picked in the cart; fall back to the
      // default (first) when they never chose or it was since deleted.
      final selId = ref.read(selectedAddressIdProvider);
      addressId = addresses.any((a) => a.id == selId) ? selId : addresses.first.id;
    } else if (mode == FulfillmentMode.curbside) {
      final cars = await ref.read(carsProvider.future);
      if (cars.isEmpty) {
        if (!mounted) return;
        context.push('/cars');
        return;
      }
      final selId = ref.read(selectedCarIdProvider);
      carId = cars.any((c) => c.id == selId) ? selId : cars.first.id;
    }

    // Dine-in: the party size is mandatory. Surface the requirement next to the
    // button rather than silently placing an order without it.
    int? partySize;
    if (mode == FulfillmentMode.dineIn) {
      partySize = ref.read(partySizeProvider);
      if (partySize == null) {
        if (!mounted) return;
        setState(() => _error = s.partySizeRequired);
        return;
      }
    }

    setState(() {
      _phase = _CheckoutPhase.sending;
      _error = null;
    });
    try {
      final order = await ref.read(orderRepositoryProvider).place(
            storeToken: widget.token,
            fulfillmentType: mode.api,
            lines: cart.lines,
            addressId: addressId,
            carId: carId,
            partySize: partySize,
            branchId: branchId,
          );
      if (!mounted) return;
      _confirm(order.id);
    } on Object catch (error) {
      final failure = ApiFailure.from(error);

      // Unknown result: the connection dropped after we sent, so the order MAY
      // have been created. Verify against the customer's active orders before
      // letting them try again — a blind retry here is what creates duplicates.
      if (failure.isConnectionIssue) {
        if (!mounted) return;
        setState(() => _phase = _CheckoutPhase.verifying);
        final match = await findRecentMatchingOrder(
          ref.read(orderRepositoryProvider),
          storeToken: widget.token,
          lines: cart.lines,
        );
        if (!mounted) return;
        if (match != null) {
          _confirm(match.id); // it went through after all — open it, don't resend
          return;
        }
        setState(() {
          _phase = _CheckoutPhase.idle;
          _error = s.checkoutConnectionUnknown;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _phase = _CheckoutPhase.idle;
        // A server-localized message is shown as-is; anything else falls back to
        // our own wording rather than leaking transport/exception text.
        _error = failure.fromServer ? failure.message : s.orderFailed;
      });
    }
  }

  /// Move to the confirmation once we KNOW the order exists: clear the cart and
  /// REPLACE this screen with tracking, so Back returns to the store and can
  /// never re-submit. `placed=1` tells tracking to open on its confirmation.
  void _confirm(int orderId) {
    AppHaptics.success();
    ref.read(cartProvider.notifier).clear();
    // The orders list and the home "reorder" shortcut are cached for the
    // session — refresh them so the new order shows up without a restart.
    invalidateOrderCaches(ref);
    context.pushReplacement('/orders/$orderId?placed=1');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final total = widget.subtotal + widget.deliveryFee;

    return Container(
      color: AppColors.cream,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The failure is shown right above the button that produced it,
              // sliding in calmly, and the cart underneath is left untouched.
              AnimatedSize(
                duration: AppMotion.dur(context, AppMotion.base),
                curve: AppMotion.curve,
                alignment: Alignment.bottomCenter,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InlineError(message: _error!, onRetry: _place),
                      ),
              ),
              FilledButton(
                onPressed: _busy ? null : _place,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink900,
                  disabledBackgroundColor: AppColors.ink900.withValues(alpha: 0.72),
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(58),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: AnimatedSwitcher(
                  duration: AppMotion.dur(context, AppMotion.fast),
                  child: _busy
                      ? Row(
                          key: const ValueKey('busy'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            const SizedBox(width: 12),
                            Text(_phase == _CheckoutPhase.verifying ? s.verifyingOrder : s.sendingOrder,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ],
                        )
                      : Row(
                          key: const ValueKey('idle'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(s.placeOrder,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 10),
                            RiyalPrice(amount: total, size: 15, color: Colors.white),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.s});
  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 44, color: AppColors.ink300),
            const SizedBox(height: 14),
            Text(s.emptyCart,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink900)),
            const SizedBox(height: 6),
            Text(s.emptyCartHint,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.ink500)),
          ],
        ),
      ),
    );
  }
}

/// The floating "view cart" bar (`.viewcart`) shown over the storefront, above
/// the nav, while the cart for this store has anything in it: count box, label,
/// total — in the merchant's brand colour.
class CartBar extends ConsumerWidget {
  const CartBar({super.key, required this.token, required this.brand});

  final String token;
  final Color brand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final cart = ref.watch(cartForStoreProvider(token));

    if (cart.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        AppHaptics.tick();
        context.push('/s/$token/cart');
      },
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: brand, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 34),
              height: 34,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text('${cart.count}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(width: 12),
            Text(s.viewCart,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
            const Spacer(),
            RiyalPrice(amount: cart.total, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
