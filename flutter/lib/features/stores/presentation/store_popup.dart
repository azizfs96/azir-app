import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/haptics.dart';
import '../../../core/localization/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../domain/storefront.dart';
import 'store_avatar.dart';

/// ============================================================================
/// STORE POP-UP ADS — the merchant's "own app" moment.
///
/// When a customer opens a store, the merchant's pop-up (an image, optionally
/// titled) appears over the storefront, the way a brand's own app announces an
/// offer. The merchant chooses how often ONE customer sees each pop-up:
///
///   every_visit   → every time the storefront opens
///   once_per_day  → at most once per calendar day (per device)
///   once          → a single time, ever (per device)
///
/// Frequency is remembered on the device (SharedPreferences) so it survives
/// restarts; "every visit" is additionally limited to once per app session so
/// re-opening the same store from the cart doesn't nag.
/// ============================================================================

/// Pop-ups already shown in this app session (every_visit shows once per
/// session, not once per rebuild).
final Set<int> _shownThisSession = {};

String _seenKey(int id) => 'popup.seen.$id';

Future<List<StorePopup>> _dueToShow(List<StorePopup> popups) async {
  if (popups.isEmpty) return const [];
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final due = <StorePopup>[];
  for (final p in popups) {
    if (_shownThisSession.contains(p.id)) continue;
    final seenMs = prefs.getInt(_seenKey(p.id));
    final seen = seenMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seenMs);
    final ok = switch (p.frequency) {
      'once' => seen == null,
      'once_per_day' =>
        seen == null ||
            seen.year != now.year ||
            seen.month != now.month ||
            seen.day != now.day,
      _ => true, // every_visit
    };
    if (ok) due.add(p);
  }
  return due;
}

Future<void> _markSeen(List<StorePopup> popups) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final p in popups) {
    _shownThisSession.add(p.id);
    await prefs.setInt(_seenKey(p.id), now);
  }
}

/// Show the store's due pop-ups (if any) over [context]. Safe to call on every
/// storefront open — it decides by itself whether anything is due.
Future<void> maybeShowStorePopups(
  BuildContext context,
  Storefront store,
) async {
  final due = await _dueToShow(store.popups);
  if (due.isEmpty || !context.mounted) return;
  // Mark first: a crash or dismissal mid-way must never re-show a "once".
  await _markSeen(due);
  if (!context.mounted) return;
  AppHaptics.tick();
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: Strings.of(context).close,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: AppMotion.dur(context, AppMotion.base),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) =>
        _PopupDialog(popups: due, brand: brandColorOf(store.brandColor)),
  );
}

class _PopupDialog extends StatefulWidget {
  const _PopupDialog({required this.popups, required this.brand});
  final List<StorePopup> popups;
  final Color brand;

  @override
  State<_PopupDialog> createState() => _PopupDialogState();
}

class _PopupDialogState extends State<_PopupDialog> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final size = MediaQuery.sizeOf(context);
    // A phone-shaped card: as tall as fits, 9:16, with room for the close
    // button above and the dots below.
    final maxH = size.height * 0.72;
    final width = (maxH * 9 / 16).clamp(240.0, size.width - 48);
    final many = widget.popups.length > 1;

    return SafeArea(
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close: a round button above the card, always reachable.
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: (size.width - width) / 2,
                  ),
                  child: _Close(
                    onTap: () => Navigator.of(context).pop(),
                    label: s.close,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: width,
                height: width * 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: PageView.builder(
                    controller: _page,
                    itemCount: widget.popups.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final p = widget.popups[i];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          AppImage(
                            url: logoUrlOf(p.image),
                            fit: BoxFit.cover,
                            placeholderColor: Ds.soft,
                            error: ColoredBox(color: widget.brand),
                          ),
                          if (p.title != null && p.title!.isNotEmpty)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  40,
                                  18,
                                  18,
                                ),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0x00000000),
                                      Color(0xB3000000),
                                    ],
                                  ),
                                ),
                                child: Text(
                                  p.title!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (many) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < widget.popups.length; i++)
                      AnimatedContainer(
                        duration: AppMotion.dur(context, AppMotion.fast),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: i == _index ? 1 : 0.45,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Close extends StatelessWidget {
  const _Close({required this.onTap, required this.label});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.close_rounded, size: 22, color: Ds.ink),
          ),
        ),
      ),
    );
  }
}
