/**
 * Highlanders Coffee & Tea — push notifications.
 *
 * Two Firestore triggers keep both sides of the shop in the loop:
 *
 *  - `onOrderCreated` pushes every registered admin device the moment an order
 *    lands, so the café does not have to watch the board.
 *  - `onOrderStatusChanged` pushes the customer's own devices on every status
 *    change, so they know the pace of their order without reopening the app.
 *
 * Both sides of the loop live here:
 *
 *  - Who to push to is read from the `notificationTokens` collection (one
 *    document per device, keyed by the FCM token and uid-scoped), which the
 *    mobile app writes when it registers. The admin SDK is not bound by the
 *    client security rules, so no rule change is needed for these reads.
 *  - The mobile app does not display anything by itself for backgrounded and
 *    terminated apps — FCM shows the `notification` payload in the tray and
 *    hands the `data` payload to the app on tap.
 *
 * Dead tokens (app uninstalled, token rotated away) are deleted as they
 * surface, which keeps the collection from accumulating orphans.
 */

import * as admin from 'firebase-admin';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';

// No `admin` access at module scope: `index.ts` calls `initializeApp()` and its
// imports evaluate first, so the default app does not exist until the module
// body runs. Handlers execute long after load, so touching `admin` inside them
// is safe.

// ---------------------------------------------------------------------------
// Address book
// ---------------------------------------------------------------------------

/** Device tokens registered to any of the given uids. */
async function tokensForUids(uids: string[]): Promise<string[]> {
  const db = admin.firestore();
  const tokens: string[] = [];

  // Firestore's `in` operator caps at ten values. The administrator list is far
  // smaller, but chunking keeps this correct if it ever grows.
  for (let i = 0; i < uids.length; i += 10) {
    const chunk = uids.slice(i, i + 10);
    const snapshot = await db
      .collection('notificationTokens')
      .where('uid', 'in', chunk)
      .get();
    snapshot.forEach((doc) => {
      const token = doc.data()['token'];
      if (typeof token === 'string' && token.length > 0) {
        tokens.push(token);
      }
    });
  }
  return tokens;
}

/** Uids of the accounts that carry the café side of the app. */
async function adminUids(): Promise<string[]> {
  const db = admin.firestore();
  const snapshot = await db.collection('users').where('role', '==', 'admin').get();
  return snapshot.docs.map((doc) => doc.id);
}

// ---------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------

interface Push {
  title: string;
  body: string;
  data: Record<string, string>;
}

/**
 * Sends [push] to every token, then deletes the documents of tokens that no
 * longer exist so the next send does not pay for them again.
 *
 * A failed push must never fail the trigger's own write, so nothing here
 * throws — errors are logged for the dashboard instead.
 */
async function sendToTokens(tokens: string[], push: Push): Promise<void> {
  if (tokens.length === 0) return;

  try {
    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: push.title, body: push.body },
      data: push.data,
      android: { priority: 'high' },
    });

    const db = admin.firestore();
    const dead: string[] = [];
    result.responses.forEach((response, index) => {
      const code = response.error?.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        dead.push(tokens[index]);
      }
    });
    await Promise.all(
      dead.map((token) =>
        db.collection('notificationTokens').doc(token).delete().catch(() => undefined),
      ),
    );
  } catch (error) {
    console.error('sendToTokens failed', error);
  }
}

// ---------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------

/**
 * On a freshly placed order, tap every admin device.
 */
export const onOrderCreated = onDocumentCreated('orders/{orderId}', async (event) => {
  const order = event.data?.data();
  if (!order) return;

  // Seeded history uses synthetic uids that match no account; pushing for it
  // would only announce the one-time seed to the owner.
  const customerUid = order['customerUid'];
  if (typeof customerUid === 'string' && customerUid.startsWith('seed-')) return;

  const tokens = await tokensForUids(await adminUids());
  if (tokens.length === 0) return;

  const items = itemCount(order);
  const total = (toNumber(order['subtotal']) ?? 0) + (toNumber(order['deliveryFee']) ?? 0);
  const customer = typeof order['customerName'] === 'string' ? order['customerName'] : 'a customer';

  await sendToTokens(tokens, {
    title: 'New order',
    body: `${customer} · ${items} item${items === 1 ? '' : 's'} · ₱${total.toFixed(2)}`,
    data: { type: 'new_order', orderId: event.params.orderId },
  });
});

/**
 * On an order status change, tap the customer's own devices.
 *
 * Idempotent by construction: the trigger ignores updates where `status` did
 * not actually change (the app rewrites the whole order document each save, so
 * touching an unrelated field must not re-ping the customer).
 */
export const onOrderStatusChanged = onDocumentUpdated('orders/{orderId}', async (event) => {
  const change = event.data;
  if (!change) return;
  const before = change.before.data();
  const after = change.after.data();
  if (!before || !after) return;

  const previousStatus = before['status'];
  const nextStatus = after['status'];
  if (previousStatus === nextStatus) return;

  const customerUid = after['customerUid'];
  if (typeof customerUid !== 'string' || customerUid.startsWith('seed-')) return;

  const body = statusCopy(typeof nextStatus === 'string' ? nextStatus : '', after);
  if (!body) return;

  const tokens = await tokensForUids([customerUid]);
  if (tokens.length === 0) return;

  await sendToTokens(tokens, {
    title: 'Highlanders Coffee & Tea',
    body,
    data: {
      type: 'order_status',
      orderId: event.params.orderId,
      status: typeof nextStatus === 'string' ? nextStatus : '',
    },
  });
});

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

/** Customer-facing line for each pipeline state, or null for no copy. */
function statusCopy(status: string, after: Record<string, unknown>): string | null {
  const fulfillment = after['fulfillment'];
  switch (status) {
    case 'pending':
      return 'We received your order.';
    case 'confirmed':
      return 'Your order is confirmed.';
    case 'preparing':
      return 'Your order is being prepared.';
    case 'ready':
      return fulfillment === 'pickup'
        ? 'Your order is ready for pickup.'
        : 'Your order is ready.';
    case 'outForDelivery':
      return 'Your order is out for delivery.';
    case 'delivered':
      return 'Your order has been delivered. Enjoy!';
    case 'failedDelivery':
      return 'Delivery failed — our team will contact you.';
    case 'cancelled':
      return 'Your order was cancelled.';
    default:
      return null;
  }
}

/** Total units across the order's lines. */
function itemCount(order: Record<string, unknown>): number {
  const lines = order['lines'];
  if (!Array.isArray(lines)) return 0;
  return lines.reduce(
    (sum: number, line: unknown) =>
      sum + (toNumber((line as Record<string, unknown> | undefined)?.['quantity']) ?? 0),
    0,
  );
}

function toNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}