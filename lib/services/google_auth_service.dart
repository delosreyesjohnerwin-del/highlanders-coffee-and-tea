import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/firebase/firebase_bootstrap.dart';
import '../data/models/order.dart';
import 'auth_service.dart';
import 'mock_auth_service.dart';

/// Firebase-backed sign-in.
///
/// Two flows:
///  * **Google** — the real path. `google_sign_in` obtains an ID token, which is
///    exchanged for a Firebase session via `signInWithCredential`.
///  * **Email/password** — requires the Email provider to be enabled in the
///    Firebase console. Returns a friendly message when it is not.
///
/// Requires `android/app/google-services.json` plus the
/// `com.google.gms.google-services` Gradle plugin; until then [isAvailable] is
/// false and [AuthServiceFactory] hands back the mock backend instead.
class GoogleAuthService implements AuthService {
  GoogleAuthService({required this.roleResolver});

  final RoleResolver roleResolver;

  bool _googleReady = false;

  @override
  bool get isAvailable => FirebaseBootstrap.isReady;

  @override
  String get unavailableReason => FirebaseBootstrap.unavailableReason;

  @override
  AuthIdentity? get current {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return AuthIdentity(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? 'Guest',
      photoUrl: user.photoURL,
    );
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    try {
      // Idempotent, but cheap — only runs the platform init once per app launch.
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize();
        _googleReady = true;
      }

      final GoogleSignInAccount account = await GoogleSignIn.instance.authenticate();
      final String? idToken = account.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        return const AuthResult.failure('Google sign-in returned no ID token.');
      }

      final UserCredential credential = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );

      final User? user = credential.user;
      if (user == null) {
        return const AuthResult.failure('Could not create a Highlanders session.');
      }

      return AuthResult.success(
        AuthIdentity(
          uid: user.uid,
          email: user.email ?? account.email,
          displayName: user.displayName ?? account.displayName ?? 'Guest',
          photoUrl: user.photoURL ?? account.photoUrl,
        ),
      );
    } on GoogleSignInException catch (error) {
      // The user backing out of the account chooser is not an error worth
      // shouting about, so it resolves quietly.
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return const AuthResult.failure('');
      }
      return AuthResult.failure(_describeGoogle(error.code));
    } on FirebaseAuthException catch (error) {
      return AuthResult.failure(_describeAuth(error.code));
    } catch (_) {
      return const AuthResult.failure('Google sign-in failed. Please try again.');
    }
  }

  @override
  Future<AuthResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final String trimmed = email.trim();

    if (trimmed.isEmpty) return const AuthResult.failure('Enter your email address.');
    if (password.isEmpty) return const AuthResult.failure('Enter your password.');

    try {
      final UserCredential credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: trimmed,
        password: password,
      );

      final User? user = credential.user;
      if (user == null) {
        return const AuthResult.failure('Could not create a Highlanders session.');
      }

      return AuthResult.success(
        AuthIdentity(
          uid: user.uid,
          email: user.email ?? trimmed,
          displayName: user.displayName ?? 'Guest',
          photoUrl: user.photoURL,
        ),
      );
    } on FirebaseAuthException catch (error) {
      return AuthResult.failure(_describeAuth(error.code));
    } catch (_) {
      return const AuthResult.failure('Sign-in failed. Please try again.');
    }
  }

  @override
  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final String name = fullName.trim();
    final String trimmed = email.trim();

    if (name.isEmpty) return const AuthResult.failure('Enter your name.');
    if (trimmed.isEmpty) return const AuthResult.failure('Enter your email address.');
    if (password.length < 6) {
      return const AuthResult.failure('Password must be at least 6 characters.');
    }

    try {
      final UserCredential credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: trimmed,
        password: password,
      );

      final User? user = credential.user;
      if (user == null) {
        return const AuthResult.failure('Could not create your account.');
      }

      // firebase_auth 6.x dropped the `displayName` argument from
      // createUserWithEmailAndPassword, so the name is set as a follow-up write.
      // Failures are swallowed: the account exists either way, and blocking
      // sign-in over a missing nickname would be worse than a blank one.
      try {
        await user.updateDisplayName(name);
      } on FirebaseAuthException {
        // Non-fatal — see above.
      }

      return AuthResult.success(
        AuthIdentity(
          uid: user.uid,
          email: user.email ?? trimmed,
          displayName: user.displayName ?? name,
          photoUrl: user.photoURL,
        ),
      );
    } on FirebaseAuthException catch (error) {
      return AuthResult.failure(_describeAuth(error.code));
    } catch (_) {
      return const AuthResult.failure('Sign-up failed. Please try again.');
    }
  }

  @override
  Future<void> signOut() async {
    // Also clear the Google-side session, otherwise the next tap silently
    // re-signs-in as the same account without showing the chooser.
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // No Google session to clear — harmless.
    }
    await FirebaseAuth.instance.signOut();
  }

  static String _describeGoogle(GoogleSignInExceptionCode code) {
    return switch (code) {
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google sign-in is not configured for this app yet.',
      GoogleSignInExceptionCode.userMismatch => 'Pick the account you want to use.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'The account chooser could not be opened. Try again in a moment.',
      GoogleSignInExceptionCode.interrupted => 'Google sign-in was interrupted. Try again.',
      // unknownError and canceled both fall through: cancel is already handled
      // by the caller, and unknown carries no better information than the
      // generic message.
      _ => 'Google sign-in failed. Please try again.',
    };
  }

  static String _describeAuth(String code) {
    return switch (code) {
      'invalid-email' => 'That email address looks invalid.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' =>
        'Incorrect email or password.',
      'email-already-in-use' => 'An account already exists for that email.',
      'weak-password' => 'Password must be at least 6 characters.',
      'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
      'network-request-failed' => 'No connection. Check your network and retry.',
      'operation-not-allowed' =>
        'Email sign-in is disabled in the Firebase console.',
      _ => 'Sign-in failed. Please try again.',
    };
  }
}

/// Reads and writes the role held in `users/{uid}`.
///
/// Using a Firestore document rather than a custom claim means an admin can be
/// promoted by editing one field in the console, with no Cloud Function and no
/// Admin SDK. `firestore.rules` enforces that only an existing admin can change
/// a role, so nobody can promote themselves.
class FirestoreRoleResolver implements RoleResolver {
  FirestoreRoleResolver({FirebaseFirestore? firestore}) : _injected = firestore;

  final FirebaseFirestore? _injected;

  /// Resolved on first use, not in the constructor.
  ///
  /// `FirebaseFirestore.instance` throws when no default app exists, so touching
  /// it eagerly would make merely *constructing* this class a hard failure in an
  /// unconfigured build. Deferring it keeps the object safe to build either way.
  FirebaseFirestore get _firestore => _injected ?? FirebaseFirestore.instance;

  static const String collection = 'users';

  @override
  Future<UserRole> roleFor(AuthIdentity identity) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _firestore.collection(collection).doc(identity.uid).get();

      final Object? raw = doc.data()?['role'];
      return raw == UserRole.admin.name ? UserRole.admin : UserRole.customer;
    } catch (_) {
      // A missing or unreachable doc must never lock the user out; the least
      // privileged role is the safe default.
      return UserRole.customer;
    }
  }

  @override
  Future<void> ensureUserDoc(AuthIdentity identity, UserRole role) async {
    try {
      await _firestore.collection(collection).doc(identity.uid).set(
        <String, dynamic>{
          'uid': identity.uid,
          'email': identity.email,
          'displayName': identity.displayName,
          'photoUrl': identity.photoUrl,
          'role': role.name,
          'createdAt': FieldValue.serverTimestamp(),
        },
        // `role` is deliberately included. The Firestore rules reject this
        // write unless the role is 'customer', which is exactly what a
        // first-time sign-in should create.
        SetOptions(merge: true),
      );
    } catch (_) {
      // Non-fatal: the user is still signed in, just without a profile doc.
    }
  }
}

/// Picks the auth backend once, at startup.
class AuthServiceFactory {
  const AuthServiceFactory._();

  static AuthService create() {
    if (FirebaseBootstrap.isReady) {
      return GoogleAuthService(roleResolver: FirestoreRoleResolver());
    }
    return MockAuthService(overrideReason: FirebaseBootstrap.unavailableReason);
  }

  static RoleResolver roleResolverFor(AuthService service) {
    if (service is GoogleAuthService) return service.roleResolver;
    return const MockRoleResolver();
  }
}