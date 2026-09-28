import 'package:flutter/material.dart';

import '../../../core/localization/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/map_targets.dart';
import '../domain/storefront.dart';

/// ============================================================================
/// THE "الموقع" TAP — one destination opens straight away; a multi-branch
/// merchant gets a chooser naming every branch with its address.
///
/// A top-level function rather than a private screen method so the widget test
/// drives the REAL sheet — a test-local copy of this logic would keep passing
/// while the production sheet rotted.
/// ============================================================================
Future<void> openStoreLocations(
  BuildContext context, {
  required Storefront store,
  required Strings s,
  required Color brand,
}) async {
    final targets = mapTargets(store);

    if (targets.isEmpty) return;

    if (targets.length == 1) {
      await openMapUrl(targets.first.url);
      return;
    }

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                s.branchesAndLocations,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink900,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                itemCount: targets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, index) {
                  final target = targets[index];

                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: brand.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(Icons.place_outlined, size: 20, color: brand),
                    ),
                    title: Text(
                      target.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    subtitle: (target.subtitle ?? '').isEmpty
                        ? null
                        : Text(
                            target.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.ink500),
                          ),
                    trailing: Text(
                      s.openInMaps,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: brand,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      openMapUrl(target.url);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
}
