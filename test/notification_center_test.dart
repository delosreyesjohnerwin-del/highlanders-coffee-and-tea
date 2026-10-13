import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/firestore/memory_shop_repository.dart';
import 'package:highlanders_coffee/data/models/app_notification.dart';
import 'package:highlanders_coffee/data/models/order.dart';
import 'package:highlanders_coffee/services/mock_auth_service.dart';
import 'package:highlanders_coffee/state/notification_center.dart';
import 'package:highlanders_coffee/state/session_provider.dart';

/// The inbox state layer: who it binds to, and the badge arithmetic.
///
/// The center is the single reader behind the bell badge and the notifications
/// screen on both the customer and the admin side, so a mistake here shows up as
/// a badge that never clears or never appears.
void main() {
  /// Signs [session] in as the mock customer, whose uid is derived from the
  /// email. Returns that uid once the center has re-bound to it.
  Future<String> signIn(SessionProvider session) async {
    await session.signInWithPassword(
      email: 'ana.dizon@email.com',
      password: 'secret1',
      rememberMe: true,
    );
    await pumpEventQueue();
    return session.user.uid;
  }

  AppNotification note(String id, {bool read = false}) => AppNotification(
        id: id,
        type: AppNotificationType.orderStatus,
        title: 'Highlanders Coffee & Tea',
        body: 'Your order #$id has been confirmed!',
        orderId: id,
        status: OrderStatus.confirmed,
        createdAt: DateTime(2026, 1, 1),
        read: read,
      );

  group('NotificationCenter', () {
    late MemoryShopRepository repo;
    late SessionProvider session;
    late NotificationCenter center;

    setUp(() {
      repo = MemoryShopRepository();
      session = SessionProvider(
        authService: MockAuthService(),
        roleResolver: const MockRoleResolver(),
        repository: repo,
      );
      center = NotificationCenter(repository: repo, session: session);
    });

    tearDown(() async {
      center.dispose();
      session.dispose();
      await repo.dispose();
    });

    test('is empty while signed out', () {
      expect(center.items, isEmpty);
      expect(center.unreadCount, 0);
      expect(center.hasLoaded, isFalse);
    });

    test('binds to the signed-in uid and counts unread', () async {
      final String uid = await signIn(session);

      await repo.saveNotification(uid, note('A'));
      await repo.saveNotification(uid, note('B', read: true));
      await pumpEventQueue();

      expect(center.items, hasLength(2));
      expect(center.unreadCount, 1);
      expect(center.hasLoaded, isTrue);
    });

    test('never sees another user\'s inbox', () async {
      final String uid = await signIn(session);

      await repo.saveNotification(uid, note('mine'));
      await repo.saveNotification('u-someone-else', note('theirs'));
      await pumpEventQueue();

      expect(center.items.single.id, 'mine');
    });

    test('markRead clears one, markAllRead clears the rest', () async {
      final String uid = await signIn(session);
      await repo.saveNotification(uid, note('A'));
      await repo.saveNotification(uid, note('B'));
      await pumpEventQueue();
      expect(center.unreadCount, 2);

      await center.markRead('A');
      expect(center.unreadCount, 1);

      await center.markAllRead();
      expect(center.unreadCount, 0);
      // The write reached the repository, so a relaunch would agree.
      final List<AppNotification> stored = await repo.loadNotifications(uid);
      expect(stored.every((AppNotification n) => n.read), isTrue);
    });

    test('hasOrderNotification recognises a change already in the inbox', () async {
      final String uid = await signIn(session);
      await repo.saveNotification(uid, note('HL-7'));
      await pumpEventQueue();

      expect(center.hasOrderNotification('HL-7'), isTrue);
      expect(center.hasOrderNotification('HL-99'), isFalse);
      expect(center.hasOrderNotification(''), isFalse);
    });

    test('unbinds on sign-out so the next account starts clean', () async {
      final String uid = await signIn(session);
      await repo.saveNotification(uid, note('A'));
      await pumpEventQueue();
      expect(center.items, isNotEmpty);

      await session.signOut();
      await pumpEventQueue();

      expect(center.items, isEmpty);
      expect(center.unreadCount, 0);
    });

    test('an optimistically read record survives the repository round-trip', () async {
      final String uid = await signIn(session);
      await repo.saveNotification(uid, note('A'));
      await pumpEventQueue();

      // markRead updates the badge before the write lands.
      final Future<void> pending = center.markRead('A');
      expect(center.unreadCount, 0);
      await pending;

      // A re-save of the same deterministic id (as the relay would do) must not
      // bring the unread dot back.
      await repo.saveNotification(uid, note('A'));
      await pumpEventQueue();
      expect(center.unreadCount, 0);
    });
  });
}
