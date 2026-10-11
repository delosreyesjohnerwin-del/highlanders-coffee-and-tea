/**
 * Highlanders Coffee & Tea — payment-gateway Cloud Functions.
 *
 * The single place the Xendit secret key lives. The mobile app sends the raw
 * number / CVC over the authenticated HTTPS callable channel; this function
 * hands them to Xendit and returns only the safe, persistable result: a
 * reusable payment-method id, the masked label, the last-four tail and the
 * card brand.
 *
 * PCI hygiene:
 *  - Raw PAN / CVC are never written to Firestore and never logged here.
 *  - Xendit is the PCI DSS-compliant party; the secret key stays server-side.
 */

import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { defineSecret } from 'firebase-functions/params';

admin.initializeApp();

const xenditSecret = defineSecret('XENDIT_SECRET_KEY');
const xenditTestOtp = defineSecret('XENDIT_TEST_OTP');

// Xendit uses the same base URL for sandbox and live; the key prefix
// (`xnd_development_…` vs `xnd_production_…`) selects the environment.
const XENDIT_API = 'https://api.xendit.co';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireString(payload: unknown, key: string, what: string): string {
  const value = (payload as Record<string, unknown> | undefined)?.[key];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `A valid ${what} is required.`,
    );
  }
  return value.trim();
}

function digitsOnly(value: string): string {
  return value.replace(/\D/g, '');
}

function lastFour(value: string): string {
  const digits = digitsOnly(value);
  return digits.length > 4 ? digits.slice(-4) : digits;
}

function lastThree(value: string): string {
  const digits = digitsOnly(value);
  return digits.length > 3 ? digits.slice(-3) : digits;
}

/**
 * E-wallet label like the app's own mask: local `0…` form, first 4 + last 3.
 * `+63…` normalises to `0…` exactly the way the Flutter side does.
 */
function ewalletMask(mobile: string): { label: string; tail: string } {
  const digits = digitsOnly(mobile);
  const local =
    digits.length === 12 && digits.startsWith('63') ? `0${digits.slice(2)}` : digits;
  const label =
    local.length >= 7 ? `${local.slice(0, 4)}****${local.slice(-3)}` : local;
  return { label, tail: lastFour(mobile) };
}

async function xenditPost(
  path: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const key = xenditSecret.value();
  const response = await fetch(`${XENDIT_API}${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${key}:`).toString('base64')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const json: Record<string, unknown> | unknown = await response.json().catch(() => ({}));
  const payload = (json ?? {}) as Record<string, unknown>;

  if (!response.ok) {
    const rawError = payload['error'] as Record<string, unknown> | undefined;
    const message =
      (typeof rawError?.['message'] === 'string' ? rawError['message'] : undefined) ??
      (typeof payload['message'] === 'string' ? payload['message'] : undefined) ??
      `Xendit declined the request (HTTP ${response.status}).`;
    throw new functions.https.HttpsError('failed-precondition', message, {
      status: response.status,
      code: typeof rawError?.['code'] === 'string' ? rawError['code'] : undefined,
    });
  }

  return payload;
}

async function customerIdFor(
  uid: string,
  givenNames: string,
  email?: string,
): Promise<string> {
  const db = admin.firestore();
  const cacheRef = db.collection('paymentGatewayCustomers').doc(uid);
  const cached = await cacheRef.get();
  const cachedId = cached.get('xenditCustomerId');
  if (typeof cachedId === 'string' && cachedId.length > 0) {
    return cachedId;
  }

  const body: Record<string, unknown> = {
    reference_id: uid,
    given_names: givenNames,
  };
  if (email) {
    body['email'] = email;
  }

  const customer = await xenditPost('/customers', body);
  const customerId = typeof customer['id'] === 'string' ? customer['id'] : '';
  if (!customerId) {
    throw new functions.https.HttpsError(
      'internal',
      'Xendit did not return a customer id.',
    );
  }

  await cacheRef.set({
    xenditCustomerId: customerId,
    referenceId: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return customerId;
}

/** Follow the Xendit auth flow for reusable non-card methods (OTP in test). */
async function completeAuthIfNeeded(
  paymentMethod: Record<string, unknown>,
  otp: string,
): Promise<void> {
  const id = typeof paymentMethod['id'] === 'string' ? paymentMethod['id'] : '';
  const status = typeof paymentMethod['status'] === 'string' ? paymentMethod['status'] : '';
  const needsAuth = ['PENDING', 'AWAITING_AUTH', 'REQUIRES_AUTH', 'EXPECTED'].includes(status);
  if (!id || !needsAuth) {
    return;
  }
  await xenditPost(`/payment_methods/${id}/auth`, { auth_code: otp });
}

// ---------------------------------------------------------------------------
// Per-network Xendit v2 payloads
// ---------------------------------------------------------------------------

async function linkCard(
  request: Record<string, unknown>,
  customerId: string,
): Promise<{ gatewayId: string; accountLabel: string; tail: string; cardBrand: string | null }> {
  const account = requireString(request, 'accountNumber', 'card number');
  const expiry = requireString(request, 'expiry', 'card expiry');
  const cvc = requireString(request, 'cvc', 'card CVC');

  const paymentMethod = await xenditPost('/payment_methods', {
    type: 'DEBIT_CARD',
    reusability: 'REUSABLE',
    customer_id: customerId,
    card: {
      card_number: account,
      card_expiry: expiry, // MM/YY
      card_cvc: cvc,
      currency: 'PHP',
    },
    metadata: { source: 'highlanders-coffee-app' },
  });

  const gatewayId = typeof paymentMethod['id'] === 'string' ? paymentMethod['id'] : '';
  if (!gatewayId) {
    throw new functions.https.HttpsError('internal', 'Xendit did not return a payment-method id.');
  }

  const card = paymentMethod['card'] as Record<string, unknown> | undefined;
  const props = card?.['channel_properties'] as Record<string, unknown> | undefined;
  const brand = typeof props?.['card_brand'] === 'string' ? props['card_brand'] : null;

  return {
    gatewayId,
    accountLabel: `**** **** ${lastFour(account)}`,
    tail: lastFour(account),
    cardBrand: brand,
  };
}

async function linkEwallet(
  request: Record<string, unknown>,
  customerId: string,
  network: 'gcash' | 'maya',
): Promise<{ gatewayId: string; accountLabel: string; tail: string; cardBrand: null }> {
  const mobile = requireString(request, 'accountNumber', 'mobile number');
  const holder = requireString(request, 'holderName', 'account holder name');
  const email = typeof request['email'] === 'string' ? request['email'] : undefined;

  const paymentMethod = await xenditPost('/payment_methods', {
    type: 'EWALLET',
    reusability: 'REUSABLE',
    customer_id: customerId,
    ewallet: {
      channel_code: network === 'gcash' ? 'GCASH' : 'MAYA',
      account: {
        mobile_number: mobile,
        given_names: holder,
        ...(email ? { email } : {}),
      },
    },
    metadata: { source: 'highlanders-coffee-app' },
  });

  const gatewayId = typeof paymentMethod['id'] === 'string' ? paymentMethod['id'] : '';
  if (!gatewayId) {
    throw new functions.https.HttpsError('internal', 'Xendit did not return a payment-method id.');
  }

  // Reusable e-wallets surface an OTP step in both sandbox and live. The
  // sandbox accepts a fixed test OTP; live mode will need the real OTP UI.
  const key = xenditSecret.value();
  if (key.startsWith('xnd_development_')) {
    await completeAuthIfNeeded(paymentMethod, xenditTestOtp.value() || '123456');
  }

  const masked = ewalletMask(mobile);
  return {
    gatewayId,
    accountLabel: masked.label,
    tail: masked.tail,
    cardBrand: null,
  };
}

async function linkBank(
  request: Record<string, unknown>,
  customerId: string,
): Promise<{ gatewayId: string; accountLabel: string; tail: string; cardBrand: null }> {
  const account = requireString(request, 'accountNumber', 'bank account number');
  const holder = requireString(request, 'holderName', 'account holder name');

  // Uses Xendit's Direct Debit channel for linked bank accounts. The channel
  // code is configurable; the sandbox shape should be confirmed on first real
  // run (Xendit surfaces a descriptive error otherwise, which we relay to the
  // app so the mismatch is visible rather than silent).
  const paymentMethod = await xenditPost('/payment_methods', {
    type: 'DIRECT_DEBIT',
    reusability: 'REUSABLE',
    customer_id: customerId,
    direct_debit: {
      channel_code: xenditBankChannel(),
      account: {
        bank_account_number: digitsOnly(account),
        bank_account_holder_name: holder,
      },
    },
    metadata: { source: 'highlanders-coffee-app' },
  });

  const gatewayId = typeof paymentMethod['id'] === 'string' ? paymentMethod['id'] : '';
  if (!gatewayId) {
    throw new functions.https.HttpsError('internal', 'Xendit did not return a payment-method id.');
  }

  const key = xenditSecret.value();
  if (key.startsWith('xnd_development_')) {
    await completeAuthIfNeeded(paymentMethod, xenditTestOtp.value() || '123456');
  }

  const tail = lastFour(account);
  return { gatewayId, accountLabel: `****${tail}`, tail, cardBrand: null };
}

// Reads configurable channel code from environment (functions config or env).
// Defaults to BDO since that is the most common PH direct-debit channel.
function xenditBankChannel(): string {
  const configured =
    process.env['XENDIT_BANK_CHANNEL'] ??
    (functions.config()['xendit']?.['bank_channel'] as string | undefined);
  return configured || 'BDO_DEBIT';
}

// ---------------------------------------------------------------------------
// The callable
// ---------------------------------------------------------------------------

/**
 * Links a payment instrument on Xendit on behalf of the signed-in user.
 *
 * App call payload:
 *   { network: 'gcash'|'maya'|'card'|'bankTransfer',
 *     holderName: string, accountNumber: string, email?: string,
 *     expiry?: string, cvc?: string }
 *
 * Returns:
 *   { gatewayId: string, accountLabel: string, tail: string, cardBrand: string|null }
 */
export const linkPaymentMethod = functions.https.onCall(
  { secrets: [xenditSecret, xenditTestOtp] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Sign in to link a payment method.',
      );
    }

    const payload = request.data as Record<string, unknown>;
    const network = payload?.['network'];
    const allowed = ['gcash', 'maya', 'card', 'bankTransfer'];
    if (typeof network !== 'string' || !allowed.includes(network)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Unsupported payment network.',
      );
    }

    const holder = requireString(payload, 'holderName', 'account holder name');
    const account = requireString(payload, 'accountNumber', 'account number');
    const email =
      typeof payload['email'] === 'string' && payload['email'].trim().length > 0
        ? payload['email'].trim()
        : undefined;

    const customerId = await customerIdFor(uid, holder, email);

    switch (network) {
      case 'card':
        return linkCard({ ...payload, holderName: holder, accountNumber: account }, customerId);
      case 'gcash':
      case 'maya':
        return linkEwallet({ ...payload, holderName: holder, accountNumber: account }, customerId, network);
      case 'bankTransfer':
        return linkBank({ ...payload, holderName: holder, accountNumber: account }, customerId);
      default:
        throw new functions.https.HttpsError('invalid-argument', 'Unsupported payment network.');
    }
  });

// Register the push-notification triggers. Kept in a separate module — this
// file is already mostly Xendit — and imported here so they deploy as part of
// the same functions bundle (the CLI only loads what `index.js` imports).
import './notifications';