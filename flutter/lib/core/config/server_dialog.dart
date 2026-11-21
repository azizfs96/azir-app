import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/stores/data/store_repository.dart';
import '../session_cache.dart';
import 'env.dart';

/// Hidden developer setting: which server the app talks to. Reached by a
/// long-press (profile "المساعدة" row, or the sign-in title) so it never
/// surfaces for a normal customer. Saving applies immediately and clears every
/// cached response so nothing stays parked on the old server's errors.
Future<void> showServerDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController(text: Env.current);
  final result = await showDialog<String?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('عنوان الخادم'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://api.azir.sa/api/v1'),
          ),
          const SizedBox(height: 8),
          Text(
            'الافتراضي: ${Env.apiBase}',
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('الافتراضي')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('حفظ')),
      ],
    ),
  );
  controller.dispose();
  if (result == null) return; // cancelled

  await Env.setOverride(result.isEmpty ? null : result);
  // Fresh start against the new server: every store and user-scoped cache.
  ref.invalidate(storefrontProvider);
  invalidateUserCaches(ref);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('الخادم الآن: ${Env.current}'), behavior: SnackBarBehavior.floating),
    );
  }
}
