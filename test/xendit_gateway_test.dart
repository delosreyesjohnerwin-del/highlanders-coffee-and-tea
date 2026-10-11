import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlanders_coffee/data/models/payment.dart';
import 'package:highlanders_coffee/services/payment_gateway.dart';
import 'package:highlanders_coffee/services/xendit_gateway.dart';

/// A throwable [FirebaseFunctionsException]. The real constructor is
/// `@protected`, which a subclass's own instance members may legally use.
class _FunctionsFailure extends FirebaseFunctionsException {
  _FunctionsFailure({
    required super.message,
    required super.code,
    super.details,
  }) : super();
}

/// The real gateway's contract with the Cloud Function: the app sends the
/// raw form values, the function (which holds the Xendit key) returns only
/// the persistable token + mask + tail. These tests pin that contract with a
/// fake [LinkCallable] so nothing touches Firebase.
void main() {
  const PaymentLinkRequest cardRequest = PaymentLinkRequest(
    network: PaymentNetwork.card,
    holderName: 'Marco Reyes',
    accountNumber: '4242424242424242',
    expiry: '12/29',
    cvc: '123',
  );

  test('sends the raw details to the Cloud Function and reads the token back',
      () async {
    Map<String, Object?>? sent;
    final XenditPaymentGateway gateway = XenditPaymentGateway(
      callable: (Map<String, Object?> payload) async {
        sent = payload;
        return <String, Object?>{
          'gatewayId': 'dpm-test-1',
          'accountLabel': '**** **** 4242',
          'tail': '4242',
          'cardBrand': 'Visa',
        };
      },
    );

    final PaymentLinkResult result = await gateway.link(cardRequest);

    expect(sent, <String, Object?>{
      'network': 'card',
      'holderName': 'Marco Reyes',
      'accountNumber': '4242424242424242',
      'email': null,
      'expiry': '12/29',
      'cvc': '123',
    });
    expect(result.gatewayId, 'dpm-test-1');
    expect(result.accountLabel, '**** **** 4242');
    expect(result.tail, '4242');
  });

  test('masks an e-wallet from the server label and keeps the tail', () async {
    final XenditPaymentGateway gateway = XenditPaymentGateway(
      callable: (_) async => <String, Object?>{
        'gatewayId': 'pm-ewallet-1',
        'accountLabel': '0917****456',
        'tail': '4567',
      },
    );

    final PaymentLinkResult result = await gateway.link(
      const PaymentLinkRequest(
        network: PaymentNetwork.gcash,
        holderName: 'Marco Reyes',
        accountNumber: '0917 123 4567',
        email: 'marco@example.com',
      ),
    );

    expect(result.gatewayId, 'pm-ewallet-1');
    expect(result.accountLabel, '0917****456');
    expect(result.tail, '4567');
  });

  test('falls back to the local mask when the function returns no label',
      () async {
    final XenditPaymentGateway gateway = XenditPaymentGateway(
      callable: (_) async =>
          <String, Object?>{'gatewayId': 'dpm-test-2', 'tail': '4242'},
    );

    final PaymentLinkResult result = await gateway.link(cardRequest);

    expect(result.gatewayId, 'dpm-test-2');
    expect(result.accountLabel, '**** **** 4242');
    expect(result.tail, '4242');
  });

  test('surfaces the function details message as a GatewayException', () async {
    final XenditPaymentGateway gateway = XenditPaymentGateway(
      callable: (_) async => throw _FunctionsFailure(
        message: 'internal error',
        code: 'failed-precondition',
        details: <String, Object?>{
          'message': 'The card was declined by the issuer.',
        },
      ),
    );

    await expectLater(
      gateway.link(cardRequest),
      throwsA(
        isA<GatewayException>().having(
          (GatewayException error) => error.message,
          'message',
          'The card was declined by the issuer.',
        ),
      ),
    );
  });

  test('falls back to the framework message when details have none', () async {
    final XenditPaymentGateway gateway = XenditPaymentGateway(
      callable: (_) async =>
          throw _FunctionsFailure(message: 'unauthenticated', code: 'unauthenticated'),
    );

    await expectLater(
      gateway.link(cardRequest),
      throwsA(
        isA<GatewayException>().having(
          (GatewayException error) => error.message,
          'message',
          'unauthenticated',
        ),
      ),
    );
  });

  test('wraps transport-level failures in a connection-friendly message',
      () async {
    final XenditPaymentGateway gateway = XenditPaymentGateway(
      callable: (_) async => throw StateError('no network'),
    );

    await expectLater(
      gateway.link(cardRequest),
      throwsA(
        isA<GatewayException>().having(
          (GatewayException error) => error.message,
          'message',
          contains('Check your connection'),
        ),
      ),
    );
  });

  test('rejects a response without a gateway id', () async {
    final XenditPaymentGateway gateway = XenditPaymentGateway(
      callable: (_) async =>
          <String, Object?>{'accountLabel': '**** **** 4242', 'tail': '4242'},
    );

    await expectLater(gateway.link(cardRequest), throwsA(isA<GatewayException>()));
  });
}