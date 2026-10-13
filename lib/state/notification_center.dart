import 'dart:async';

// The two injected dependencies are private fields, and Dart has no
// initializing formal for a private named parameter, so the formals lint does
// not apply to this constructor — the assignments are the idiomatic shape.
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/material.dart';

import '../data/firestore/firestore_errors.dart';
import '../data/firestore/shop_repository.dart';
import '../data/models/app_notification.dart';
import 'session_provider.dart';

/// The signed-in user's notification inbox, kept live.
///
/// One instance serves both panels: it subscribes to
/// `notifications/{uid}/items` for whoever is signed in, so the café's device
/// reads the admin inbox and a customer's device reads their own. The rules do
/// the separation; this class never has to know which role it is serving.
///
/// It is the single source for the **badges** (the bell's unread count) and the
/// **inbox screen**. The immediate in-app banner is still raised by the provider
/// that saw the change in its own order stream, because the write→stream
/// round-trip through Firestore is a beat slower than the stream that already
/// delivered the order — announcing from the inbox would make the banner lag the
/// board.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter({
    required ShopRepository repository,
    required SessionProvider session,
  })  : _repository = repository,
        _session = session {
    _session.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  final ShopRepository _repository;
  final SessionProvider _session;

  StreamSubscription<List<AppNotification>>? _sub;
  String? _uid;
  List<AppNotification> _items = const <AppNotification>[];
  bool _loaded = false;
  WriteFailure? _failure;

  /// True once a live backend has answered for the current uid.
  bool get isLive => _repository.isLive;

  bool get hasLoaded => _loaded;

  /// Everything in the inbox, newest first.
  List<AppNotification> get items => _items;

  /// Records the user has not opened yet — the number on the bell.
  int get unreadCount => _items.where((AppNotification n) => !n.read).length;

  /// Most recent failed write, and clears it.
  WriteFailure? consumeFailure() {
    final WriteFailure? failure = _failure;
    _failure = null;
    return failure;
  }

  void _recordFailure(WriteFailure? failure) {
    if (failure == null) return;
    _failure = failure;
    logWriteFailure(failure);
    notifyListeners();
  }

  /// Re-subscribes whenever the signed-in identity changes.
  ///
  /// The demo (seed) uid has no Firestore user document and no inbox, so it is
  /// skipped exactly like [SessionProvider] and [NotificationService] skip it.
  void _onSessionChanged() {
    final bool eligible = _session.isSignedIn && _session.user.uid != SessionProvider.seedUid;
    final String? uid = eligible ? _session.user.uid : null;
    if (uid == _uid) return;

    _uid = uid;
    unawaited(_sub?.cancel());
    _sub = null;
    _items = const <AppNotification>[];
    _loaded = false;

    if (uid != null) {
      _sub = _repository.watchNotifications(uid).listen(
        (List<AppNotification> items) {
          _items = items;
          _loaded = true;
          notifyListeners();
        },
        onError: (Object error) {
          _recordFailure(describeFailure('watch your notifications', error));
        },
      );
    }

    notifyListeners();
  }

  /// True when the inbox already holds a record for [orderId].
  ///
  /// Used by [NotificationService] to drop a foreground FCM banner for a change
  /// the app has already announced from its own stream, so an open app does not
  /// show the same update twice.
  bool hasOrderNotification(String orderId) {
    if (orderId.isEmpty) return false;
    return _items.any((AppNotification n) => n.orderId == orderId);
  }

  /// Marks one record read, updating the badge before the write lands.
  Future<void> markRead(String id) async {
    final String? uid = _uid;
    if (uid == null) return;

    final int i = _items.indexWhere((AppNotification n) => n.id == id);
    if (i >= 0 && !_items[i].read) {
      final List<AppNotification> next = <AppNotification>[..._items];
      next[i] = next[i].copyWith(read: true);
      _items = next;
      notifyListeners();
    }

    _recordFailure(await _repository.markNotificationRead(uid, id));
  }

  /// Marks every record read.
  Future<void> markAllRead() async {
    final String? uid = _uid;
    if (uid == null) return;

    if (_items.any((AppNotification n) => !n.read)) {
      _items = <AppNotification>[for (final AppNotification n in _items) n.copyWith(read: true)];
      notifyListeners();
    }

    _recordFailure(await _repository.markAllNotificationsRead(uid));
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
