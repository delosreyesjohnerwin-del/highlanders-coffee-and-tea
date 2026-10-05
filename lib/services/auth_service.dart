import 'package:flutter/foundation.dart';

import '../data/models/order.dart';

/// The identity a sign-in attempt produced.
@immutable
class AuthIdentity {
  const AuthIdentity({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
}

/// Outcome of a sign-in attempt.
///
/// A null [error] means success. [error] is a message already phrased for the
/// user, so screens can render it directly without a translation layer.
@immutable
class AuthResult {
  const AuthResult.success(this.identity) : error = null;

  const AuthResult.failure(this.error) : identity = null;

  final AuthIdentity? identity;
  final String? error;

  bool get isSuccess => identity != null;
}

/// Swappable sign-in backend.
///
/// Two implementations exist: [GoogleAuthService] for real Firebase-backed
/// accounts, and `MockAuthService` so the app stays fully usable before
/// Firebase is configured. Screens only ever talk to this interface.
abstract class AuthService {
  /// Whether this implementation can actually reach an identity provider.
  bool get isAvailable;

  /// Explanation shown when [isAvailable] is false.
  String get unavailableReason;

  /// Interactive Google sign-in.
  Future<AuthResult> signInWithGoogle();

  /// Email + password sign-in.
  Future<AuthResult> signInWithPassword({
    required String email,
    required String password,
  });

  /// Creates a local account and signs in. Not available on the real backend
  /// until Firebase Auth's email provider is enabled in the console.
  Future<AuthResult> register({
    required String fullName,
    required String email,
    required String password,
  });

  Future<void> signOut();

  /// The currently signed-in identity, if any.
  AuthIdentity? get current;
}

/// Resolves the account's role.
///
/// Roles are stored in `users/{uid}` rather than a custom claim, so that an
/// admin can be promoted from the Firebase console without deploying any
/// server code. Firestore rules prevent self-promotion.
abstract class RoleResolver {
  Future<UserRole> roleFor(AuthIdentity identity);

  /// Writes the user's profile doc on first sign-in.
  Future<void> ensureUserDoc(AuthIdentity identity, UserRole role);
}