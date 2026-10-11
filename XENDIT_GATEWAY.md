# Xendit gateway — going real (test mode)

This is the runbook for flipping the payment-methods feature from the mock
gateway to the real Xendit integration.

## Architecture

```
App (Flutter)                    Cloud Function (Firebase)            Xendit
┌──────────────────────┐ HTTPS  ┌─────────────────────────┐  REST   ┌────────────────┐
│ LinkPaymentScreen ──▶│ call  │ linkPaymentMethod(uid,  │ ──────▶ │ POST /customers │
│ (raw number, CVC)    │       │  network, number, ...)  │  ◀───── │ POST /payment__ │
│  never stored        │       │  (holds XENDIT secret)  │         │   methods      │
└──────────────────────┘       └─────────────────────────┘         └────────────────┘
                                   │ writes paymentGatewayCustomers/{uid}
                                   ▼ Firestore
```

- The app sends raw form values over the authenticated callable channel.
- The **Cloud Function** owns the Xendit secret key and performs the
  tokenization. Only the persistable result returns: a reusable
  payment-method id, a masked label, a last-four tail, and a card brand.
- The app stores exactly what it always stored — mask + tail + token — under
  the existing `paymentMethods` rules. Nothing else changes downstream.

## The four steps

### 1. Create a Xendit account and copy the test keys

1. Sign up at <https://www.xendit.co> (any PH-valid email).
2. **Settings → API keys** → copy the *test* secret key
   (`xnd_development_…`). Test mode needs no business verification and moves
   no real money.
3. Useful test fixtures (sandbox):
   - Cards that succeed: `4242 4242 4242 4242`
   - E-wallet / bank OTP: `123456` (the function submits it automatically)

### 2. Set the secrets in Firebase

The project id is already pinned in `.firebaserc`
(`highlanderscoffeeandtea-108a2`).

```powershell
firebase login
firebase use highlanderscoffeeandtea-108a2
firebase functions:secrets:set XENDIT_SECRET_KEY
# enter the test key when prompted
firebase functions:secrets:set XENDIT_TEST_OTP
# enter 123456
```

### 3. Deploy the function

```powershell
firebase deploy --only functions
```

`firebase.json` auto-builds the TypeScript (`npm --prefix functions run
build`) before deploying. Node 22 runtime.

### 4. Build the app with the real gateway enabled

```powershell
flutter run --dart-define=XENDIT_ENABLED=true
# or for a release install:
flutter build apk --dart-define=XENDIT_ENABLED=true
```

`PaymentGatewayFactory.create()` hands back the real
`XenditPaymentGateway` only when **both** hold:

- Firebase is available (`FirebaseBootstrap.isReady`), and
- the build opted in with `--dart-define=XENDIT_ENABLED=true`.

Everything else — offline dev, the demo seed, every widget test — keeps
riding the deterministic mock, so without the flag nothing changes.

## Verifying the first real link

1. Open **Profile → Payment Methods → Add payment method**.
2. **Debit/Credit Card**, hold `4242 4242 4242 4242`, expiry `12/29`,
   CVC `123` → link.
3. The list shows `**** **** 4242`. Check the console:
   - `paymentGatewayCustomers/{uid}` now maps the user to a Xendit
     `Customer`.
   - The Xendit dashboard shows a reusable DPA payment method.
4. Link a GCash / Maya wallet → masked mobile, sandbox OTP auto-submitted.

If any Xendit shape is refused, the function relays Xendit's error message
verbatim to the app's SnackBar. That message is the clue for a one-line fix
in `functions/src/index.ts`; redeploy with `firebase deploy --only
functions`.

## Moving to live payments (later)

- Register the business (DTI/SEC), verify a bank account, pass Xendit's
  review, then swap the **test** key for the **production** key
  (`xnd_production_…`) via `firebase functions:secrets:set XENDIT_SECRET_KEY`.
- Same code. Two known follow-ups before charging real money:
  - Reusable e-wallets need the **real OTP flow** (the function currently
    auto-submits the sandbox OTP only when the key starts with
    `xnd_development_`). That means an OTP step in `LinkPaymentScreen` plus a
    second callable.
  - Bank direct-debit channel is configurable via `XENDIT_BANK_CHANNEL`
    (defaults to `BDO_DEBIT`).

## Security notes

- The Xendit secret key exists only in Cloud Functions secrets — never in the
  app, never in `--dart-define`.
- Raw PAN / CVC are never logged and never written to Firestore. The only
  writes are the masked `paymentMethods` documents (existing app path) and the
  uid→customer mapping in `paymentGatewayCustomers` (server-only, denied to
  clients).
- If a key is ever exposed, rotate it in the Xendit dashboard and re-set the
  secret.