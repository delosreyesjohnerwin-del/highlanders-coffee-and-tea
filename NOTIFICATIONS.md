# Push notifications — going real

> **Two ways to run this loop.** The Cloud Functions in `functions/` are the
> full-latency path and need the Firebase **Blaze** plan (the free Spark plan
> cannot run functions). If the project is still on the free plan, use the
> **free Cloudflare relay** in `push-relay/` instead — see `FREE_PUSH.md`. The
> loop, the message copy and the hygiene are identical; only the triggering
> mechanism (Firestore event vs 1-minute poll) differs. Prefer this file once
> the project is upgraded to Blaze.

This is the runbook for turning on the push-notification loop end to end. The
code is already in place; these are the steps that make pushes actually travel
from the shop to a phone.

## What is built

```
                    orders/{orderId} (Firestore)
                    ┌───────────────┐   onOrderCreated ─┐
Customer app ──────▶│  placed order │                   ▼
       │  sign-in    └───────────────┘        admin devices get a
       │  writes notificationTokens/{token}   "New order" push
       ▼                    │
notificationTokens          │  onOrderStatusChanged
(one doc per device,        └──────────────▶ customer devices get a
 keyed by the FCM token)                        "Your order is …" push
```

- **Two Cloud Function triggers** in `functions/src/notifications.ts`:
  - `onOrderCreated` — pushes every registered admin device when an order lands.
  - `onOrderStatusChanged` — pushes the customer's own devices whenever the
    order's `status` actually changes.
- **`notificationTokens`** — one Firestore document per installed app, keyed by
  the FCM device token and scoped to the signed-in uid. Written by the app on
  sign-in / token rotation, read by the functions (admin SDK, rules exempt).
  Dead tokens are deleted as they surface.
- **App side** (`lib/services/notification_service.dart`) — requests
  permission, registers the token while signed in, re-registers on rotation,
  and routes taps. FCM shows the tray notification itself in the
  background/terminated states; foreground messages become an in-app banner
  (a second OS notification while the user is already in the app is noise).

## Deploy steps

The project id is pinned in `.firebaserc`
(`highlanderscoffeeandtea-108a2`).

### 1. Deploy the functions

```powershell
firebase login
firebase use highlanderscoffeeandtea-108a2
firebase deploy --only functions
```

This deploys `linkPaymentMethod` (Xendit) together with both new triggers —
`firebase.json` builds the TypeScript first, and `index.ts` registers
`notifications.ts` so they ship in the same bundle.

### 2. Deploy the security rules

`notificationTokens` needs its rules live before the app can write to it. The
rules are deployed from a staged directory (see the header of
`firestore.rules`):

```powershell
$stage = New-Item -ItemType Directory -Force "$env:TEMP\hl-rules"
Copy-Item firestore.rules "$stage\firestore.rules" -Force
'{"firestore":{"rules":"firestore.rules"}}' > "$stage\firebase.json"
firebase deploy --only firestore:rules --project highlanderscoffeeandtea-108a2 --config "$stage\firebase.json"
```

Then verify the deployed copy is byte-identical to this file.

Rules summary:

- `notificationTokens` — a signed-in user may create/update/delete their own
  token document (`uid` must equal their auth uid); only admins may read it.
  This stops one customer re-pointing another customer's device.

### 3. Rebuild the app on the phone

The app currently on the INOI lacks the messaging code. Reinstall:

```powershell
flutter install -d A1800523021656 --debug
```

No `--dart-define` is needed for notifications — unlike the Xendit gateway, the
service activates automatically when Firebase is available (`FirebaseBootstrap
.isReady`, which it is once `google-services.json` is in place). `flutter
install` uninstalls the old build first, which wipes on-device state — sign in
again after installing.

## Verifying the loop on the phone

1. **Sign in as a customer.** The first sign-in triggers the permission prompt
   (Android 13). Grant it.
2. **Place an order** through checkout. The admin device should receive a
   "New order" push within a few seconds.
3. **Sign in as the admin** on the same phone (or another device), open Orders,
   and advance the order (`Confirm → Start preparing → Mark ready →
   Hand to rider → Mark delivered`).
4. **The customer device gets a push at every step**:
   - *app open* → in-app banner at the bottom,
   - *app backgrounded or closed* → tray notification.
5. **Tap a tray notification** → the app opens the order's tracking screen.
   An admin tapping "New order" lands on the Orders board.

Check the `notificationTokens` collection in the Firebase console: one document
per device, `uid` = the signed-in account. If a device shows no document, the
permission was denied or sign-in never settled.

Seed orders are never pushed: their customer uids start with `seed-`, which the
triggers treat as synthetic demo accounts.

## Notes

- **Same-phone café + customer.** When both roles sign in on one device, each
  sign-in rewrites the token doc's `uid`, so the phone receives exactly the
  pushes for whichever account is currently signed in. That is the intended
  behaviour on a shared phone: sign out of the customer and into the admin to
  switch which pushes arrive.
- **Dead-token cleanup.** When FCM reports a token as unregistered (app
  uninstalled, token rotated), the functions delete its document, so the
  collection does not grow stale.
- **Foreground ≠ tray.** FCM does not display `notification` messages in the
  foreground. The app shows those as an in-app banner instead — no
  `flutter_local_notifications` dependency, one tap path, nothing to configure.
- **Retries.** A notification failure never fails the order write it hangs off:
  the functions log and return.