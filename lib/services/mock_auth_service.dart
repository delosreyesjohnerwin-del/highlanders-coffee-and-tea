import '../data/models/order.dart';
import '../data/mock/mock_data.dart';
import 'auth_service.dart';

/// Demo sign-in backend used whenever Firebase is not configured.
///
/// It accepts any syntactically valid email with a password of at least six
/// characters, and hands back the matching seeded account so the admin and
/// customer paths stay distinguishable. This exists so the app is fully
/// navigable before `google-services.json` lands — it is **not** a security
/// boundary and must never ship as the real login.
class MockAuthService implements AuthService {
  MockAuthService({this.overrideReason});

  /// Shown on the login screen when the mock backend is active.
  final String? overrideReason;

  AuthIdentity? _current;

  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => overrideReason ?? 'Demo sign-in — Firebase not connected';

  @override
  AuthIdentity? get current => _current;

  /// The demo account matching [role], for pre-filling the login form.
  static AuthIdentity demoIdentityFor(UserRole role) {
    return role == UserRole.admin
        ? const AuthIdentity(
            uid: 'u-admin',
            email: 'admin@highlanderscoffee.ph',
            displayName: 'Café Admin',
          )
        : const AuthIdentity(
            uid: 'u-marco',
            email: 'marco.reyes@email.com',
            displayName: 'Marco Reyes',
          );
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // There is no Google account to read from, so the customer demo identity is
    // the sensible stand-in. The real path is GoogleAuthService.
    _current = demoIdentityFor(UserRole.customer);
    return AuthResult.success(_current!);
  }

  @override
  Future<AuthResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final String trimmed = email.trim();

    if (trimmed.isEmpty) return const AuthResult.failure('Enter your email address.');
    if (!_email.hasMatch(trimmed)) {
      return const AuthResult.failure('That email address looks invalid.');
    }
    if (password.isEmpty) return const AuthResult.failure('Enter your password.');
    if (password.length < 6) {
      return const AuthResult.failure('Password must be at least 6 characters.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));

    _current = AuthIdentity(
      uid: 'demo-${trimmed.toLowerCase()}',
      email: trimmed,
      displayName: _nameFromEmail(trimmed),
    );
    return AuthResult.success(_current!);
  }

  @override
  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final String trimmed = email.trim();
    final String name = fullName.trim();

    if (name.isEmpty) return const AuthResult.failure('Enter your name.');
    if (!_email.hasMatch(trimmed)) {
      return const AuthResult.failure('That email address looks invalid.');
    }
    if (password.length < 6) {
      return const AuthResult.failure('Password must be at least 6 characters.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));

    _current = AuthIdentity(
      uid: 'demo-$name-${trimmed.toLowerCase()}',
      email: trimmed,
      displayName: name,
    );
    return AuthResult.success(_current!);
  }

  @override
  Future<void> signOut() async {
    _current = null;
  }

  /// "juan.delacruz@email.com" becomes "Juan Delacruz" so the profile screen
  /// has something human to render for a brand-new demo account.
  static String _nameFromEmail(String email) {
    final String local = email.split('@').first;
    final List<String> parts = local
        .split(RegExp(r'[._-]+'))
        .where((String p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'Guest';

    return parts
        .map((String p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }
}

/// Role lookup for the mock backend: the seeded admin email is the admin,
/// everybody else is a customer.
class MockRoleResolver implements RoleResolver {
  const MockRoleResolver();

  @override
  Future<UserRole> roleFor(AuthIdentity identity) async {
    return identity.email.toLowerCase() == MockData.admin.email.toLowerCase()
        ? UserRole.admin
        : UserRole.customer;
  }

  @override
  Future<void> ensureUserDoc(AuthIdentity identity, UserRole role) async {
    // Nothing to persist while running on mock data.
  }
}