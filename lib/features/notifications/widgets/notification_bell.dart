import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/bw_colors.dart';
import '../../../state/notification_center.dart';
import '../notifications_screen.dart';

/// The bell in a top bar: opens the inbox and carries the unread count.
///
/// Reads the count with `select` so it only rebuilds when the number changes,
/// not on every unrelated provider tick. Used by the customer home header and
/// the admin top bar, which is why the icon colour is injectable — the admin bar
/// sits on a dark surface.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.color = BwColors.text, this.background});

  final Color color;

  /// Optional circular backing, for bars that need the icon lifted off a fill.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final int unread =
        context.select<NotificationCenter, int>((NotificationCenter c) => c.unreadCount);

    final Widget icon = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Icon(Icons.notifications_none_rounded, size: 24, color: color),
        if (unread > 0)
          Positioned(
            right: -5,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: BwColors.inverse,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: background ?? BwColors.surface, width: 1.5),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: BwColors.onInverse,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      button: true,
      label: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      child: InkResponse(
        radius: 26,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: background == null
              ? icon
              : Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: background, shape: BoxShape.circle),
                  child: icon,
                ),
        ),
      ),
    );
  }
}
