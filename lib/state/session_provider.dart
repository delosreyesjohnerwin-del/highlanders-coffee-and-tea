import 'dart:async';

import 'package:flutter/material.dart';

import '../data/firestore/firestore_errors.dart';
import '../data/firestore/shop_repository.dart';
import '../data/mock/mock_data.dart';
import '../data/models/order.dart';
import '../services/auth_service.dart';
import '../services/google_auth_service.dart';

/// Whether anyone is signed in.
///
/// `signedOut` is the launch state — the login screen is the app's root until a
/// successful sign-in flips this.
enum AuthStatus { signedOut, signedIn, busy }

/// Signed-in user, saved addresses, order history and auth state.
///
/// Swapping the mock lists for Firestore streams happens here and nowhere else.
/// Auth itself is delegated to an [AuthService] so the mock and Firebase
/// backends are interchangeable.
class SessionProvider extends ChangeNotifier {
  SessionProvider({
    AuthService? authService,
    RoleResolver? roleResolver,
    ShopRepository? repository,
  }) {
    // Resolved in the body rather than the initializer list: role resolution
    // depends on which backend was chosen, which is not known until the auth
    // service exists.
    _auth = authService ?? AuthServiceFactory.create();
    _roles = roleResolver ?? AuthServiceFactory.roleResolverFor(_auth);
    _repository = repository;

    _loadAccount(UserRole.customer);
  }

  late final AuthService _auth;
  late final RoleResolver _roles;

  /// Null when the app has no backend. Every method that touches it must handle
  /// null rather than assume a repository exists — the memory-backed providers
  /// are the ones that carry the seed data in that case.
  ShopRepository? _repository;

  StreamSubscription<List<Order>>? _ordersSub;
  StreamSubscription<List<SavedAddress>>? _addressesSub;
  WriteFailure? _failure;

  AuthStatus _status = AuthStatus.signedOut;
  bool _rememberMe = false;
  String? _lastError;

  late AppUser _user;
  late List<SavedAddress> _addresses;
  late List<Order> _orders;

  AppUser get user => _user;
  List<SavedAddress> get addresses => _addresses;
  List<Order> get orders => _orders;

  AuthStatus get status => _status;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get isBusy => _status == AuthStatus.busy;
  bool get rememberMe => _rememberMe;

  /// Last sign-in failure, for display on the login screen.
  String? get lastError => _lastError;

  /// Which backend is live — surfaced in Settings for debugging.
  AuthService get authService => _auth;
  RoleResolver get roleResolver => _roles;

  /// True when orders and addresses are actually being read from a backend.
  bool get isLive => _repository?.isLive ?? false;

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

  bool get isAdmin => isSignedIn && _user.role == UserRole.admin;

  List<Order> get activeOrders =>
      _orders.where((Order o) => o.status.isActive).toList(growable: false);

  List<Order> get pastOrders =>
      _orders.where((Order o) => !o.status.isActive).toList(growable: false);

  Order? orderById(String id) {
    for (final Order o in _orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  SavedAddress? get defaultAddress {
    if (_addresses.isEmpty) return null;
    for (final SavedAddress a in _addresses) {
      if (a.isDefault) return a;
    }
    return _addresses.first;
  }

  /// Adds a new address or replaces an existing one (upsert by id), so the
  /// same method serves both the "add" and "edit" flows.
  ///
  /// Marking an address as default also clears the default flag on whatever
  /// previously held it — two "default" deliveries would leave the shop
  /// guessing which one to use. The unset is written through to the backend
  /// just like the new value, so the persisted state matches what the user
  /// sees.
  void addAddress(SavedAddress address) {
    SavedAddress? clearedDefault;
    final List<SavedAddress> next = <SavedAddress>[];
    bool replaced = false;

    for (final SavedAddress a in _addresses) {
      if (a.id == address.id) {
        next.add(address);
        replaced = true;
      } else if (a.isDefault && address.isDefault) {
        final SavedAddress cleared = a.copyWith(isDefault: false);
        next.add(cleared);
        clearedDefault = cleared;
      } else {
        next.add(a);
      }
    }
    if (!replaced) next.add(address);

    _addresses = next;
    notifyListeners();

    final ShopRepository? repo = _repository;
    if (repo == null) return;
    unawaited(repo.saveAddress(_user.uid, address).then(_recordFailure));
    if (clearedDefault != null) {
      unawaited(repo.saveAddress(_user.uid, clearedDefault).then(_recordFailure));
    }
  }

  void removeAddress(String id) {
    _addresses = _addresses.where((SavedAddress a) => a.id != id).toList(growable: false);
    notifyListeners();

    final ShopRepository? repo = _repository;
    if (repo == null) return;
    unawaited(repo.deleteAddress(_user.uid, id).then(_recordFailure));
  }

  /// Appends a freshly placed order to the top of the history.
  ///
  /// Writes through when a backend exists. The local append happens first and is
  /// not rolled back on failure — the customer has paid, and telling them their
  /// order vanished because the phone lost signal would be worse than showing a
  /// retryable warning. The failure is recorded for the UI to surface.
  void placeOrder(Order order) {
    _orders = <Order>[order, ..._orders];
    notifyListeners();

    final ShopRepository? repo = _repository;
    if (repo == null) return;
    unawaited(repo.createOrder(order).then(_recordFailure));
  }

  void updateOrderStatus(String orderId, OrderStatus status) {
    _orders = _orders
        .map((Order o) => o.id == orderId
            ? Order(
                id: o.id,
                customerUid: o.customerUid,
                lines: o.lines,
                status: status,
                fulfillment: o.fulfillment,
                paymentMethod: o.paymentMethod,
                createdAt: o.createdAt,
                subtotal: o.subtotal,
                deliveryFee: o.deliveryFee,
                distanceKm: o.distanceKm,
                address: o.address,
                customerName: o.customerName,
                pickupCode: o.pickupCode,
                driverName: o.driverName,
                driverPhone: o.driverPhone,
                paymentRef: o.paymentRef,
                promoCode: o.promoCode,
              )
            : o)
        .toList(growable: false);
    notifyListeners();
  }

  // --- auth ---------------------------------------------------------------

  /// Signs in with the backend's Google flow. Returns true on success.
  Future<bool> signInWithGoogle() async {
    _setBusy();
    final AuthResult result = await _auth.signInWithGoogle();
    return _settle(result);
  }

  /// Email + password sign-in.
  Future<bool> signInWithPassword({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    _setBusy();
    final AuthResult result = await _auth.signInWithPassword(email: email, password: password);
    if (!result.isSuccess) return _settle(result);
    _rememberMe = rememberMe;
    return _settle(result);
  }

  /// Creates an account and signs straight in.
  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    _setBusy();
    final AuthResult result = await _auth.register(
      fullName: fullName,
      email: email,
      password: password,
    );
    if (!result.isSuccess) return _settle(result);
    _rememberMe = rememberMe;
    return _settle(result);
  }

  Future<void> signOut() async {
    // Drop the live subscriptions *before* the auth token goes, so no read
    // arrives afterwards under an identity that no longer matches the query it
    // was issued with.
    _cancelOrders();
    _cancelAddresses();

    await _auth.signOut();
    // Reset to the seeded customer account. Screens can still be rendered in
    // isolation (tests do exactly that) without becoming a special case.
    _loadAccount(UserRole.customer);
    _status = AuthStatus.signedOut;
    _lastError = null;
    notifyListeners();
  }

  /// Clears the last sign-in error once the screen has shown it.
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  void _setBusy() {
    _status = AuthStatus.busy;
    _lastError = null;
    notifyListeners();
  }

  /// Resolves a [signIn]-style result into the signed-in account.
  Future<bool> _settle(AuthResult result) async {
    final AuthIdentity? identity = result.identity;

    if (identity == null) {
      _status = AuthStatus.signedOut;
      // An empty message means the user simply dismissed a dialog.
      _lastError = (result.error ?? '').isEmpty ? null : result.error;
      notifyListeners();
      return false;
    }

    UserRole role = await _roles.roleFor(identity);
    await _roles.ensureUserDoc(identity, role);

    _loadAccount(role, identity: identity);
    _bindLiveData();
    _status = AuthStatus.signedIn;
    _lastError = null;
    notifyListeners();
    return true;
  }

  /// Subscribes to the signed-in customer's own orders and addresses.
  ///
  /// Both queries filter on the uid, and both have to: the `orders.list` rule is
  /// evaluated per document the query would return, so an unfiltered query is
  /// refused outright with PERMISSION_DENIED rather than silently returning
  /// nothing. The comment in `firestore.rules` says the same thing from the other
  /// side.
  ///
  /// A real identity gets *empty* lists first, not the seeded ones — the seed
  /// belongs to a demo account that does not exist in Firestore, and showing a
  /// new customer someone else's order history would be a privacy bug that reads
  /// as a feature.
  void _bindLiveData() {
    final ShopRepository? repo = _repository;
    if (repo == null || !repo.isLive) return;
    if (_user.uid == _seedUid) return;

    _cancelOrders();
    _cancelAddresses();

    _ordersSub = repo.watchOrdersFor(_user.uid).listen(
      (List<Order> orders) {
        _orders = orders;
        notifyListeners();
      },
      onError: (Object error) {
        _recordFailure(describeFailure('watch your orders', error));
      },
    );

    _addressesSub = repo.watchAddresses(_user.uid).listen(
      (List<SavedAddress> addresses) {
        _addresses = addresses;
        notifyListeners();
      },
      onError: (Object error) {
        _recordFailure(describeFailure('watch your addresses', error));
      },
    );
  }

  void _cancelOrders() {
    unawaited(_ordersSub?.cancel());
    _ordersSub = null;
  }

  void _cancelAddresses() {
    unawaited(_addressesSub?.cancel());
    _addressesSub = null;
  }

  @override
  void dispose() {
    _cancelOrders();
    _cancelAddresses();
    super.dispose();
  }

  /// The seeded accounts' uid. Orders and addresses are never fetched for it:
  /// [MockData] already holds them, and there is no such document in Firestore.
  static const String _seedUid = 'u-marco';

  /// Swaps in the seeded account for [role], or builds one from a real identity.
  void _loadAccount(UserRole role, {AuthIdentity? identity}) {
    if (identity != null) {
      _user = AppUser(
        uid: identity.uid,
        fullName: identity.displayName,
        email: identity.email,
        avatarUrl: identity.photoUrl,
        role: role,
        memberTier: role == UserRole.admin ? 'Staff' : 'Gold Member',
        orderCount: role == UserRole.admin ? MockData.admin.orderCount : 0,
        reviewCount: role == UserRole.admin ? MockData.admin.reviewCount : 0,
        rewards: 0,
      );
      _addresses = <SavedAddress>[];
      _orders = <Order>[];
      return;
    }

    if (role == UserRole.admin) {
      _user = MockData.admin;
      _addresses = <SavedAddress>[];
      _orders = List<Order>.from(MockData.adminQueue);
    } else {
      _user = MockData.user;
      _addresses = List<SavedAddress>.from(MockData.addresses);
      _orders = MockData.ordersFor(MockData.user.uid);
    }
  }
}