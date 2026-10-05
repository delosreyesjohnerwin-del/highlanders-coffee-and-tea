import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Startup probe for Firebase.
///
/// The app is built so it runs with or without Firebase configured. When
/// `android/app/google-services.json` is missing — or Firebase throws for any
/// other reason — [isReady] stays false and the app falls back to the mock auth
/// service rather than showing a black screen.
///
/// TODO(owner): once the Firebase project exists and the Gradle
/// `com.google.gms.google-services` plugin is applied, this will succeed and
/// [AuthServiceFactory] will hand back the real Google-backed implementation.
class FirebaseBootstrap {
  const FirebaseBootstrap._();

  static bool _ready = false;
  static String _reason = '';

  /// True when `Firebase.initializeApp` completed successfully.
  static bool get isReady => _ready;

  /// Human-readable explanation when [isReady] is false. Shown on the login
  /// screen so a missing config is never a mystery.
  static String get unavailableReason => _reason;

  /// Attempts initialisation exactly once. Safe to call repeatedly.
  static Future<void> ensureInitialized() async {
    if (_ready || _reason.isNotEmpty) return;

    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (error) {
      _ready = false;
      _reason = _describe(error);
    }
  }

  /// Forces the app into mock mode.
  ///
  /// Used by tests and by the demo path in the login screen, where the user
  /// deliberately signs in without a Google account.
  static void forceMock(String reason) {
    _ready = false;
    _reason = reason;
  }

  /// Resets the probe. Test-only.
  @visibleForTesting
  static void resetForTest() {
    _ready = false;
    _reason = '';
  }

  static String _describe(Object error) {
    final String raw = error.toString();

    // The overwhelmingly common cause on Android is a missing/ignored
    // google-services.json, which surfaces as a core-library-initialise failure.
    if (raw.contains('google-services') ||
        raw.contains('core-library-initialise') ||
        raw.contains('Default FirebaseApp')) {
      return 'Firebase is not configured yet';
    }

    return 'Firebase unavailable';
  }
}