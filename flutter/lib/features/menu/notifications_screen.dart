import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';

/// The in-app inbox (Jahez's notifications). Newest first; tapping marks read.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final items = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(s.notifications),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, _) => Center(child: Text(s.error, style: const TextStyle(color: AppColors.ink500))),
        data: (list) => list.isEmpty
            ? _empty(s)
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _NotificationCard(
                    item: list[i],
                    onTap: () async {
                      if (!list[i].isRead) {
                        await ref.read(notificationRepositoryProvider).markRead(list[i].id);
                        ref.invalidate(notificationsProvider);
                      }
                    },
                  ),
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
              const Icon(Icons.notifications_none_rounded, size: 46, color: AppColors.ink300),
              const SizedBox(height: 14),
              Text(s.noNotifications,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink900)),
            ],
          ),
        ),
      );
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});
  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: item.isRead ? null : Border.all(color: AppColors.ink900, width: 1.4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: AppColors.ink900, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.notifications_rounded, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.body,
                        style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.ink500)),
                  ],
                ],
              ),
            ),
            if (!item.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 9, height: 9,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(color: AppColors.flame, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- data ------------------------------------------------------------------

class AppNotification {
  const AppNotification({required this.id, required this.title, required this.body, required this.isRead});

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        isRead: json['is_read'] as bool? ?? false,
      );

  final int id;
  final String title;
  final String body;
  final bool isRead;
}

class NotificationRepository {
  const NotificationRepository(this._api);
  final ApiClient _api;

  Future<List<AppNotification>> list() async {
    final json = await _api.get('/me/notifications');
    final data = (json['data'] as List?) ?? const [];
    return [for (final n in data) AppNotification.fromJson(n as Map<String, dynamic>)];
  }

  Future<void> markRead(int id) => _api.post('/me/notifications/$id/read');
}

final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) => NotificationRepository(ref.watch(apiClientProvider)));

final notificationsProvider =
    FutureProvider<List<AppNotification>>((ref) => ref.watch(notificationRepositoryProvider).list());
