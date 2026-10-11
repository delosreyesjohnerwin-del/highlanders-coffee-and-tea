import 'package:flutter/foundation.dart';

import '../core/firebase/firebase_bootstrap.dart';
import '../data/models/payment.dart';
import 'xendit_gateway.dart';

/// A request to link a customer's payment instrument with a payment gateway.
@immutable
class PaymentLinkRequest {
  const PaymentLinkRequest({
    required this.network,
    required this.holderName,
    required this.accountNumber,
    this.email,
    this.expiry,
    this.cvc,
  });

  final PaymentNetwork network;
  final String holderName;

  /// The full mobile number, card PAN or bank account number. Held only for
  /// the duration of the link call — never persisted by the app.
  final String accountNumber;

  /// E-wallet email, when supplied.
  final String? email;

  /// Card-only: MM/YY expiry and CVC. Transient — the gateway consumes them
  /// and returns a token. A linked card should be remembered by its token, not
  /// re-typed at every checkout.
  final String? expiry;
  final String? cvc;
}

/// Outcome of a link attempt.
///
/// The account persists only what is safe to keep: a gateway token plus the
/// already-masked display string and its last-four tail.
@immutable
class PaymentLinkResult {
  const PaymentLinkResult({
    required this.gatewayId,
    required this.accountLabel,
    required this.tail,
  });

  final String gatewayId;
  final String accountLabel;
  final String tail;
}

/// A gateway failure with a message safe to show the customer.
///
/// Real gateways surface provider-side messages ("invalid card", "OTP
/// required"); wrapping them lets the UI show one friendly SnackBar instead of
/// leaking `FirebaseFunctionsException` internals.
class GatewayException implements Exception {
  const GatewayException(this.message);

  final String message;

  @override
  String toString() => 'GatewayException: $message';
}

/// Where linked instruments are created.
///
/// The real implementation is [XenditPaymentGateway], which proxies to the
/// `linkPaymentMethod` Cloud Function. The function holds the Xendit secret
/// key, calls Xendit's v2 API on the app's behalf and returns only the
/// persistable result — a reusable payment-method id, a masked label, the
/// tail and the card brand. The app never handles the secret key, and the raw
/// PAN/CVC pass through as transient request data only.
///
/// [MockPaymentGateway] is the deterministic offline fallback: it computes the
/// mask itself and fabricates a gateway-style id. Offline builds take it, and
/// so does every widget test.
abstract class PaymentGateway {
  /// Links [PaymentLinkRequest] and returns the safe-to-store result.
  Future<PaymentLinkResult> link(PaymentLinkRequest request);
}

/// Deterministic offline implementation: computes the display mask itself and
/// fabricates a gateway-style id. The same path production-with-no-config
/// takes, which is also the one every widget test rides.
class MockPaymentGateway implements PaymentGateway {
  const MockPaymentGateway();

  @override
  Future<PaymentLinkResult> link(PaymentLinkRequest request) async {
    return PaymentLinkResult(
      gatewayId: 'mock-pm-${DateTime.now().microsecondsSinceEpoch}',
      accountLabel: PaymentAccount.maskOf(request.network, request.accountNumber),
      tail: PaymentAccount.tailOf(request.accountNumber),
    );
  }
}

/// Builds the gateway the app uses.
///
/// The real [XenditPaymentGateway] is selected only when both hold:
///
///  1. Firebase is available (so the authenticated HTTPS callable to the
///     deployed Cloud Function can be made) — [FirebaseBootstrap.isReady]; and
///  2. the build opts in via `--dart-define=XENDIT_ENABLED=true`.
///
/// Everything else — offline dev machines, the demo seed, every widget test —
/// rides the deterministic mock, exactly as `AuthServiceFactory` falls back to
/// the mock auth service when Firebase is not configured.
class PaymentGatewayFactory {
  const PaymentGatewayFactory._();

  /// Build-time opt-in. Pass `--dart-define=XENDIT_ENABLED=true` when the
  /// `linkPaymentMethod` Cloud Function is deployed and Xendit keys are set.
  static const bool xenditEnabled = bool.fromEnvironment('XENDIT_ENABLED');

  static PaymentGateway create() {
    if (FirebaseBootstrap.isReady && xenditEnabled) {
      return XenditPaymentGateway();
    }
    return const MockPaymentGateway();
  }
}