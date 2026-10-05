import 'package:flutter/material.dart';

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
  SessionProvider({AuthService? authService, RoleResolver? roleResolver}) {
    // Resolved in the body rather than the initializer list: role resolution
    // depends on which backend was chosen, which is not known until the auth
    // service exists.
    _auth = authService ?? AuthServiceFactory.create();
    _roles = roleResolver ?? AuthServiceFactory.roleResolverFor(_auth);

    _loadAccount(UserRole.customer);
  }

  late final AuthService _auth;
  late final RoleResolver _roles;

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

  void addAddress(SavedAddress address) {
    _addresses = <SavedAddress>[..._addresses, address];
    notifyListeners();
  }

  void removeAddress(String id) {
    _addresses = _addresses.where((SavedAddress a) => a.id != id).toList(growable: false);
    notifyListeners();
  }

  /// Appends a freshly placed order to the top of the history.
  void placeOrder(Order order) {
    _orders = <Order>[order, ..._orders];
    notifyListeners();
  }

  void updateOrderStatus(String orderId, OrderStatus status) {
    _orders = _orders
        .map((Order o) => o.id == orderId
            ? Order(
                id: o.id,
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
    _status = AuthStatus.signedIn;
    _lastError = null;
    notifyListeners();
    return true;
  }

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