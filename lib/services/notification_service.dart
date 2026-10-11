import 'dart:async';

// The three injected dependencies are private fields, and Dart has no
// initializing formal for a private named parameter, so the formals lint does
// not apply to this constructor — the assignments are the idiomatic shape.
// ignore_for_file: prefer_initializing_formals

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/firebase/firebase_bootstrap.dart';
import '../data/firestore/firestore_errors.dart';
import '../data/firestore/shop_repository.dart';
import '../data/models/order.dart';
import '../features/admin/admin_dashboard_screen.dart';
import '../features/order_tracking/order_tracking_screen.dart';
import '../state/session_provider.dart';
import 'in_app_alert.dart';

/// One notification tap decoded from a pushed message's `data` map.
///
/// Pure data — no widget or plugin types — so the routing logic can be tested
/// without a device.
@immutable
class NotificationTap {
  const NotificationTap({required this.type, required this.orderId});

  /// Customer pushed an order status change.
  static const String orderStatus = 'order_status';

  /// Admin pushed a freshly placed order.
  static const String newOrder = 'new_order';

  final String type;

  /// The order the push is about; 'new_order' pushes carry it too.
  final String orderId;
}

/// The slice of Firebase Cloud Messaging this service needs, abstracted so
/// widget tests can drive registration and taps without a real device token.
///
/// Mirrors the [PaymentGateway] seam: production gets the real
/// [FcmMessagingBackend], tests get a fake driven by stream controllers.
abstract class MessagingBackend {
  /// False when Firebase is not configured; the service then does nothing.
  bool get isAvailable;

  /// Prompts for notification permission. No-op where the OS does not ask.
  Future<void> requestPermission();

  /// Current registration token, or null before one exists.
  Future<String?> getToken();

  /// Fires when the OS rotates the registration token (reinstall, expiry).
  Stream<String> get onTokenRefresh;

  /// Foreground messages. FCM does not display these; the service surfaces
  /// them as an in-app banner.
  Stream<RemoteMessage> get onMessage;

  /// A tray notification the user tapped while the app was backgrounded.
  Stream<RemoteMessage> get onMessageOpenedApp;

  /// The tray notification that launched the app from a terminated state.
  Future<RemoteMessage?> getInitialMessage();
}

/// Real backend over Firebase Cloud Messaging.
///
/// Lazily touches the plugin so constructing the backend in tests (where
/// [FirebaseBootstrap.isReady] is false) never throws — `FirebaseMessaging`
/// requires a live `FirebaseApp`, which only exists once
/// `Firebase.initializeApp` has run.
class FcmMessagingBackend implements MessagingBackend {
  FcmMessagingBackend();

  FirebaseMessaging? _messaging;

  FirebaseMessaging get _instance => _messaging ??= FirebaseMessaging.instance;

  @override
  bool get isAvailable => FirebaseBootstrap.isReady;

  @override
  Future<void> requestPermission() async {
    // On Android 13+ this prompts for POST_NOTIFICATIONS; earlier versions are
    // granted at install and this resolves immediately.
    await _instance.requestPermission();
  }

  @override
  Future<String?> getToken() => _instance.getToken();

  @override
  Stream<String> get onTokenRefresh => _instance.onTokenRefresh;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => _instance.getInitialMessage();
}

/// Owns push notifications end to end: permission, device-token registration,
/// and routing taps to the screen the push refers to.
///
/// Produces no notifications by itself — Firebase Cloud Messaging adds the
/// tray notification for backgrounded and terminated apps automatically, and
/// the Cloud Functions in `functions/src/notifications.ts` do the sending. This
/// service is the app side of that loop:
///
///  * **Foreground** messages become an in-app banner (a second OS notification
///    while the user is already looking at the app is noise).
///  * **Background / terminated** taps are decoded and routed — customers to
///    the order's tracking screen, admins to the orders board.
///  * The device token is registered under the signed-in uid on sign-in and
///    re-registered when the OS rotates it, so the Cloud Functions know which
///    token to push to. Sign-out unregisters best-effort.
///
/// Everything is a no-op when [MessagingBackend.isAvailable] is false.
class NotificationService extends ChangeNotifier {
  NotificationService({
    required ShopRepository repository,
    required SessionProvider session,
    required GlobalKey<NavigatorState> navigatorKey,
    MessagingBackend? backend,
  })  : _repository = repository,
        _session = session,
        _navigatorKey = navigatorKey,
        _backend = backend ?? FcmMessagingBackend();

  final ShopRepository _repository;
  final SessionProvider _session;
  final GlobalKey<NavigatorState> _navigatorKey;
  final MessagingBackend _backend;

  bool _initialised = false;

  /// Uid the current registration belongs to, null while signed out.
  String? _registeredUid;

  /// Token most recently registered, so sign-out can unregister it.
  String? _registeredToken;

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Hooks the message streams and the session. Safe to call once.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    if (!_backend.isAvailable) return;

    try {
      await _backend.requestPermission();
    } catch (error) {
      debugPrint('notification permission request failed: $error');
    }

    _foregroundSub = _backend.onMessage.listen(_showForegroundBanner);
    _openedSub = _backend.onMessageOpenedApp.listen(_handleMessage);
    _tokenRefreshSub = _backend.onTokenRefresh.listen(_onTokenRefresh);
    _session.addListener(_onSessionChanged);
    _onSessionChanged();

    final RemoteMessage? initial = await _backend.getInitialMessage();
    if (initial != null) _handleMessage(initial);
  }

  bool get isEnabled =>
      _backend.isAvailable &&
      _registeredUid != null &&
      _session.isSignedIn &&
      _registeredUid == _session.user.uid &&
      _registeredToken != null;

  /// Requests notification permission and registers the device token for the
  /// currently signed-in user. If the user is not signed in, this will still
  /// request permission but will not register a token.
  Future<void> enable() async {
    if (!_backend.isAvailable) return;

    try {
      await _backend.requestPermission();
    } catch (error) {
      debugPrint('notification permission request failed: $error');
    }

    if (!_session.isSignedIn) return;
    final String uid = _session.user.uid;
    _registeredUid = uid;
    await _registerToken(uid);
    notifyListeners();
  }

  /// Unregisters the current device token and stops receiving push
  /// notifications on this device.
  Future<void> disable() async {
    final String? uid = _registeredUid;
    if (uid == null && _session.isSignedIn) {
      // Attempt to unregister using current session uid if available.
      final String currentUid = _session.user.uid;
      final String? token = _registeredToken;
      _registeredUid = null;
      _registeredToken = null;
      notifyListeners();
      if (token != null) {
        try {
          final WriteFailure? failure =
              await _repository.deleteNotificationToken(currentUid, token);
          if (failure != null) {
            debugPrint('notification token unregister skipped: ${failure.message}');
          }
        } catch (error) {
          debugPrint('notification token unregister failed: $error');
        }
      }
      return;
    }

    final String? token = _registeredToken;
    _registeredUid = null;
    _registeredToken = null;
    notifyListeners();
    if (uid == null || token == null) return;

    try {
      final WriteFailure? failure =
          await _repository.deleteNotificationToken(uid, token);
      if (failure != null) {
        debugPrint('notification token unregister skipped: ${failure.message}');
      }
    } catch (error) {
      debugPrint('notification token unregister failed: $error');
    }
  }

  /// Routes a notification tap to its screen. Public so tests can drive the
  /// same code the message streams call.
  void open(NotificationTap tap) => _routeTo(tap);

  // --- token registration ---------------------------------------------------

  void _onSessionChanged() {
    final bool signedIn = _session.isSignedIn;
    if (signedIn) {
      final String uid = _session.user.uid;
      if (_registeredUid != uid) {
        _registeredUid = uid;
        unawaited(_registerToken(uid));
      }
    } else if (_registeredUid != null) {
      final String uid = _registeredUid!;
      _registeredUid = null;
      unawaited(_unregisterToken(uid));
    }
  }

  Future<void> _registerToken(String uid) async {
    // Mirrors SessionProvider's seed-uid skip: the demo account has no
    // Firestore user document, and pushing a token under it would just leave
    // an orphan (and a debt the next admin list query pays down).
    if (_repository.isLive && uid == SessionProvider.seedUid) return;

    final String? token;
    try {
      token = await _backend.getToken();
    } catch (error) {
      debugPrint('notification token unavailable: $error');
      return;
    }
    if (token == null || token.isEmpty) return;
    _registeredToken = token;

    final WriteFailure? failure = await _repository.saveNotificationToken(uid, token);
    if (failure != null) logWriteFailure(failure);
  }

  Future<void> _unregisterToken(String uid) async {
    final String? token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;

    try {
      final WriteFailure? failure =
          await _repository.deleteNotificationToken(uid, token);
      if (failure != null) {
        // Best effort. On a live backend the client is signed out by now, so
        // the rules (uid == auth.uid) deny the delete — fine, the token doc is
        // re-claimed by the next sign-in's `set`.
        debugPrint('notification token unregister skipped: ${failure.message}');
      }
    } catch (error) {
      debugPrint('notification token unregister failed: $error');
    }
  }

  Future<void> _onTokenRefresh(String token) async {
    final String? uid = _registeredUid;
    if (uid == null) return;
    final String? previous = _registeredToken;
    _registeredToken = token;

    // The rotated token replaced the old one on the OS side; the old
    // registration is dead weight and must not linger in the collection.
    if (previous != null && previous != token) {
      await _repository.deleteNotificationToken(uid, previous);
    }
    final WriteFailure? failure = await _repository.saveNotificationToken(uid, token);
    if (failure != null) logWriteFailure(failure);
  }

  // --- message display & routing --------------------------------------------

  void _showForegroundBanner(RemoteMessage message) {
    final String body = message.notification?.body ?? 'Order update';
    showInAppAlert(_navigatorKey.currentContext, body);
  }

  void _handleMessage(RemoteMessage message) {
    final String type = _dataString(message, 'type');
    final String orderId = _dataString(message, 'orderId');
    if (orderId.isEmpty) return;
    _routeTo(NotificationTap(
      type: type.isEmpty ? NotificationTap.orderStatus : type,
      orderId: orderId,
    ));
  }

  void _routeTo(NotificationTap tap) {
    final BuildContext? context = _navigatorKey.currentContext;
    if (context == null) return;
    final NavigatorState navigator = Navigator.of(context);

    if (tap.type == NotificationTap.newOrder) {
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const AdminDashboardScreen(initialSection: AdminSection.orders),
      ));
      return;
    }

    // Keep on the live copy of the order from the session, exactly like the
    // tracking screen itself prefers.
    final Order? order =
        Provider.of<SessionProvider>(context, listen: false).orderById(tap.orderId);
    if (order == null) return;
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => OrderTrackingScreen(order: order),
    ));
  }

  static String _dataString(RemoteMessage message, String key) {
    final Object? value = message.data[key];
    return value == null ? '' : value.toString();
  }

  // --- lifecycle -------------------------------------------------------------

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    unawaited(_foregroundSub?.cancel());
    unawaited(_openedSub?.cancel());
    unawaited(_tokenRefreshSub?.cancel());
    super.dispose();
  }
}