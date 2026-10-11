import 'package:flutter/foundation.dart';

import '../data/models/payment.dart';

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

/// Where linked instruments are created.
///
/// ## The real integration (when it lands)
///
///  * **PayMongo** — e-wallets go through a checkout session / `PaymentLink`
///    with `source` set to `gcash` or `maya`; cards use `Token.create` with
///    PAN + expiry + CVC and return a `tok_…`. The token is all the app keeps.
///  * **Xendit** — same shape: `PaymentMethod` creation returning an `id`.
///
/// This interface is the seam those implementations would fill.
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
/// The mock is the only implementation until a real PayMongo/Xendit client
/// exists — mirroring how `AuthServiceFactory` hands back the mock or the
/// real backend depending on configuration.
class PaymentGatewayFactory {
  const PaymentGatewayFactory._();

  static PaymentGateway create() => const MockPaymentGateway();
}