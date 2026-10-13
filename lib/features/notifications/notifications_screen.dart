import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/bw_colors.dart';
import '../../core/theme/bw_metrics.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/bw_button.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/order.dart';
import '../../state/notification_center.dart';
import '../../state/session_provider.dart';
import '../admin/admin_dashboard_screen.dart';
import '../order_tracking/order_tracking_screen.dart';

/// The notification inbox: every record kept for the signed-in user, newest
/// first, with unread state and a "mark all read" action.
///
/// Serves both panels. A customer sees their order-status records; an admin sees
/// the new-order records. The records themselves are kept apart by the Firestore
/// rules — `notifications/{uid}/items` — so this screen never has to filter by
/// role.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final NotificationCenter center = context.watch<NotificationCenter>();
    final List<AppNotification> items = center.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: BwIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.of(context).pop(),
          bordered: false,
          background: BwColors.transparent,
        ),
        actions: <Widget>[
          if (center.unreadCount > 0)
            TextButton(
              onPressed: center.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: SafeArea(
        child: items.isEmpty
            ? const _EmptyInbox()
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: BwSpacing.sm),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: BwColors.border,
                  indent: BwSpacing.gutter,
                  endIndent: BwSpacing.gutter,
                ),
                itemBuilder: (BuildContext context, int i) {
                  final AppNotification n = items[i];
                  return _NotificationTile(
                    notification: n,
                    onTap: () => _open(context, center, n),
                  );
                },
              ),
      ),
    );
  }

  /// Marks the record read, then routes to the order it refers to when the app
  /// still knows about it — the same destination a push tap would open.
  static Future<void> _open(
    BuildContext context,
    NotificationCenter center,
    AppNotification notification,
  ) async {
    await center.markRead(notification.id);
    if (!context.mounted) return;

    if (notification.type == AppNotificationType.newOrder) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const AdminDashboardScreen(initialSection: AdminSection.orders),
      ));
      return;
    }

    final Order? order =
        context.read<SessionProvider>().orderById(notification.orderId);
    if (order == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OrderTrackingScreen(order: order),
    ));
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool unread = !notification.read;

    return Material(
      color: BwColors.surface,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0x0A000000),
        highlightColor: const Color(0x0A000000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(BwSpacing.gutter, BwSpacing.md, BwSpacing.gutter, BwSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // The unread dot. A fixed-width slot keeps read and unread rows
              // aligned instead of shifting the text left when it disappears.
              SizedBox(
                width: 16,
                child: unread
                    ? const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(Icons.circle, size: 8, color: BwColors.inverse),
                      )
                    : null,
              ),
              const SizedBox(width: BwSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                              color: BwColors.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: BwSpacing.sm),
                        Text(
                          Fmt.relative(notification.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: BwColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: BwColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(BwSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.notifications_none_rounded, size: 44, color: BwColors.disabled),
            SizedBox(height: BwSpacing.md),
            Text(
              'No notifications yet',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BwColors.text),
            ),
            SizedBox(height: BwSpacing.xs),
            Text(
              'Order updates will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: BwColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
