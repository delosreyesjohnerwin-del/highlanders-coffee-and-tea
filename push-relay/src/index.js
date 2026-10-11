/**
 * Highlanders Coffee & Tea — free push relay (Cloudflare Workers).
 *
 * The Firebase free (Spark) plan cannot run Cloud Functions, so this Worker is
 * the in-app-shop notification loop instead: once a minute it polls Firestore
 * for order changes and sends FCM pushes. It is the free-tier counterpart to
 * `functions/src/notifications.ts` (which runs the same loop live once the
 * project is upgraded to Blaze).
 *
 * How change detection works without Cloud-Function triggers:
 *   - The mobile app writes `updatedAt` (a Firestore server timestamp) on every
 *     order save — see `firestore_shop_repository.dart`.
 *   - This Worker keeps a last-seen checkpoint in KV and queries
 *     `orders where updatedAt >= checkpoint`, which keeps Firestore reads tiny
 *     (a handful per minute, far inside the free-tier read quota) instead of
 *     scanning the whole collection every poll.
 *   - An order with no stored snapshot is a NEW order -> push every admin
 *     device. A snapshot whose status differs is a STATUS CHANGE -> push the
 *     customer's own devices. Both are exactly what `onOrderCreated` and
 *     `onOrderStatusChanged` did, minus the definitions trigger latency (up to
 *     ~60s here, the cron granularity).
 *
 * Free-tier cautions (verified against Cloudflare docs, 2026):
 *   - Cron Triggers fire at most once per minute, are not retried, and have no
 *     failure alerts. A missed run loses nothing: the next poll just picks up
 *     from the same checkpoint.
 *   - Workers Free allows 100k scheduled requests/day and 10ms of CPU per
 *     invocation. This loop's CPU (JSON parse, one RSA signature only on token
 *     refresh) is well inside that; the minutes are network I/O, which is not
 *     billed.
 *
 * Hygiene from the functions ported over:
 *   - Seeded history (`customerUid` starting with `seed-`) never pushes.
 *   - First run is a silent backfill: every existing order is snapshotted and
 *     checkpointed without pushing, so enabling the relay never announces old
 *     orders or sends a wave of status-change spam.
 *   - Dead FCM tokens (404 / 400 from FCM) have their `notificationTokens`
 *     document deleted so future runs stop paying for them.
 */

const SCOPES = 'https://www.googleapis.com/auth/cloud-platform';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FIRESTORE_API = 'https://firestore.googleapis.com/v1';
const FCM_API = 'https://fcm.googleapis.com/v1';

export default {
  /** Cron trigger (see `wrangler.toml`). Controller is unused beyond logging. */
  async scheduled(controller, env) {
    try {
      await runRelay(env);
    } catch (error) {
      console.error('push relay run failed', error);
    }
  },

  /** Manual trigger: hitting the Worker's URL runs one relay pass. */
  async fetch(request, env) {
    if (request.method === 'POST') {
      await runRelay(env);
      return new Response('{"ok":true}', { headers: { 'content-type': 'application/json' } });
    }
    return new Response('POST to run the push relay once.', { status: 405 });
  },
};

// ---------------------------------------------------------------------------
// One relay pass
// ---------------------------------------------------------------------------

async function runRelay(env) {
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const projectId = sa.project_id;
  const auth = await accessToken(env, sa);

  const checkpoint = await env.PUSH_STATE.get('checkpoint');
  if (!checkpoint) {
    const stoppedAt = await backfillSnapshots(env, projectId, auth);
    await env.PUSH_STATE.put('checkpoint', stoppedAt);
    console.log('cold start: snapshotted orders up to', stoppedAt);
    return;
  }

  const orders = await fetchOrdersSince(env, projectId, auth, checkpoint);
  if (orders.length === 0) return;
  const admins = await adminUids(env, projectId, auth);

  let newest = checkpoint;
  for (const doc of orders) {
    const order = parseOrder(doc);
    // Ascending order by updatedAt means the last doc carries the max, which
    // becomes the next checkpoint. Ties at the boundary are re-selected next
    // poll and deduped by the stored snapshot.
    newest = order.updatedAt;

    const before = await env.PUSH_STATE.get('o:' + order.id);

    if (!before) {
      if (order.customerUid.startsWith('seed-')) {
        await env.PUSH_STATE.put('o:' + order.id, snapshotOf(order));
        continue;
      }
      const tokens = await tokensForUids(env, projectId, auth, admins);
      await pushNewOrder(env, projectId, auth, tokens, order);
      await env.PUSH_STATE.put('o:' + order.id, snapshotOf(order));
      continue;
    }

    const previousStatus = JSON.parse(before).status;
    if (previousStatus !== order.status) {
      await pushStatusChange(env, projectId, auth, order);
    }
    await env.PUSH_STATE.put('o:' + order.id, snapshotOf(order));
  }

  await env.PUSH_STATE.put('checkpoint', newest);
}

// ---------------------------------------------------------------------------
// Cold start
// ---------------------------------------------------------------------------

/**
 * First ever run: page through every order (ascending by updatedAt), storing a
 * snapshot for each and pushing nothing, then write the checkpoint. Order
 * documents that predate the `updatedAt` field are excluded by the query and
 * stay invisible to the relay forever, which is exactly the "no noise from
 * backfill" behaviour wanted.
 */
async function backfillSnapshots(env, projectId, auth) {
  let cursor = '1970-01-01T00:00:00Z';
  let lastTs = null;
  for (;;) {
    const results = await runQuery(env, projectId, auth, {
      structuredQuery: {
        from: [{ collectionId: 'orders' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'updatedAt' },
            op: 'GREATER_THAN',
            value: { timestampValue: cursor },
          },
        },
        orderBy: [{ field: { fieldPath: 'updatedAt' }, direction: 'ASCENDING' }],
        limit: 200,
      },
    });
    const docs = results.map((r) => r.document).filter(Boolean);
    if (docs.length === 0) break;
    for (const doc of docs) {
      const order = parseOrder(doc);
      await env.PUSH_STATE.put('o:' + order.id, snapshotOf(order));
      lastTs = order.updatedAt;
    }
    if (docs.length < 200) break;
    cursor = lastTs;
  }
  return lastTs ?? new Date().toISOString();
}

// ---------------------------------------------------------------------------
// Firestore reads and writes
// ---------------------------------------------------------------------------

async function fetchOrdersSince(env, projectId, auth, checkpoint) {
  const results = await runQuery(env, projectId, auth, {
    structuredQuery: {
      from: [{ collectionId: 'orders' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'updatedAt' },
          op: 'GREATER_THAN_OR_EQUAL',
          value: { timestampValue: checkpoint },
        },
      },
      orderBy: [{ field: { fieldPath: 'updatedAt' }, direction: 'ASCENDING' }],
      limit: 200,
    },
  });
  return results.map((r) => r.document).filter(Boolean);
}

async function adminUids(env, projectId, auth) {
  const results = await runQuery(env, projectId, auth, {
    structuredQuery: {
      from: [{ collectionId: 'users' }],
      where: {
        fieldFilter: {
          field: { fieldPath: 'role' },
          op: 'EQUAL',
          value: { stringValue: 'admin' },
        },
      },
    },
  });
  return results.map((r) => r.document && docNameId(r.document.name)).filter(Boolean);
}

/** All device tokens registered to any of the given uids (IN is capped at 10). */
async function tokensForUids(env, projectId, auth, uids) {
  const tokens = [];
  for (let i = 0; i < uids.length; i += 10) {
    const chunk = uids.slice(i, i + 10);
    const results = await runQuery(env, projectId, auth, {
      structuredQuery: {
        from: [{ collectionId: 'notificationTokens' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'uid' },
            op: 'IN',
            value: { arrayValue: { values: chunk.map((u) => ({ stringValue: u })) } },
          },
        },
      },
    });
    for (const r of results) {
      if (!r.document) continue;
      const token = str(r.document.fields, 'token');
      if (token) tokens.push(token);
    }
  }
  return tokens;
}

async function runQuery(env, projectId, auth, body) {
  const res = await fetch(
    `${FIRESTORE_API}/projects/${projectId}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: 'Bearer ' + auth },
      body: JSON.stringify(body),
    },
  );
  if (!res.ok) {
    throw new Error(`runQuery failed ${res.status}: ${(await res.text()).slice(0, 400)}`);
  }
  return await res.json();
}

async function deleteTokenDoc(env, projectId, auth, token) {
  const res = await fetch(
    `${FIRESTORE_API}/projects/${projectId}/databases/(default)/documents/notificationTokens/${encodeURIComponent(token)}`,
    { method: 'DELETE', headers: { authorization: 'Bearer ' + auth } },
  );
  if (!res.ok) {
    console.error('token doc delete failed', res.status, (await res.text()).slice(0, 200));
  }
}

// ---------------------------------------------------------------------------
// Push content (mirrors functions/src/notifications.ts)
// ---------------------------------------------------------------------------

async function pushNewOrder(env, projectId, auth, tokens, order) {
  if (tokens.length === 0) return;
  const items = order.itemCount;
  const total = order.subtotal + order.deliveryFee;
  const customer = order.customerName || 'a customer';
  await sendToTokens(env, projectId, auth, tokens, {
    title: 'New order',
    body: `${customer} · ${items} item${items === 1 ? '' : 's'} · ₱${total.toFixed(2)}`,
    data: { type: 'new_order', orderId: order.id },
  });
}

async function pushStatusChange(env, projectId, auth, order) {
  if (order.customerUid.startsWith('seed-') || !order.customerUid) return;
  const body = statusCopy(order.status, order);
  if (!body) return;
  const tokens = await tokensForUids(env, projectId, auth, [order.customerUid]);
  if (tokens.length === 0) return;
  await sendToTokens(env, projectId, auth, tokens, {
    title: 'Highlanders Coffee & Tea',
    body,
    data: { type: 'order_status', orderId: order.id, status: order.status },
  });
}

/** Customer-facing line for each pipeline state, or null for no copy. */
function statusCopy(status, order) {
  switch (status) {
    case 'pending':
      return 'We received your order.';
    case 'confirmed':
      return 'Your order is confirmed.';
    case 'preparing':
      return 'Your order is being prepared.';
    case 'ready':
      return order.fulfillment === 'pickup' ? 'Your order is ready for pickup.' : 'Your order is ready.';
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

/**
 * Sends one FCM message per token. A token FCM rejects as dead (404
 * registration-token-not-registered, 400 invalid token) has its document
 * deleted so the next run does not pay for it again. A transient failure keeps
 * the token; the next poll's snapshot dedupe means we never double-send on
 * that basis.
 */
async function sendToTokens(env, projectId, auth, tokens, push) {
  for (const token of tokens) {
    const alive = await sendOne(env, projectId, auth, token, push);
    if (!alive) {
      await deleteTokenDoc(env, projectId, auth, token).catch(() => undefined);
    }
  }
}

async function sendOne(env, projectId, auth, token, push) {
  const payload = {
    message: {
      token,
      notification: { title: push.title, body: push.body },
      data: push.data,
      android: { priority: 'high' },
    },
  };
  const res = await fetch(`${FCM_API}/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: 'Bearer ' + auth },
    body: JSON.stringify(payload),
  });
  if (res.ok) return true;
  const status = res.status;
  if (status === 400 || status === 404) return false;
  console.error('FCM send failed', status, (await res.text()).slice(0, 300));
  return true;
}

// ---------------------------------------------------------------------------
// Document decoding
// ---------------------------------------------------------------------------

function parseOrder(doc) {
  const fields = doc.fields || {};
  let itemCount = 0;
  const values = fields.lines && fields.lines.arrayValue && fields.lines.arrayValue.values;
  if (Array.isArray(values)) {
    for (const line of values) {
      const lf = (line.mapValue && line.mapValue.fields) || {};
      const q = lf.quantity;
      if (q) itemCount += Number(q.integerValue ?? q.doubleValue ?? 0) || 0;
    }
  }
  return {
    id: docNameId(doc.name),
    status: str(fields, 'status') || 'pending',
    customerUid: str(fields, 'customerUid') || '',
    customerName: str(fields, 'customerName'),
    fulfillment: str(fields, 'fulfillment') || '',
    subtotal: num(fields, 'subtotal'),
    deliveryFee: num(fields, 'deliveryFee'),
    itemCount,
    updatedAt: ts(fields, 'updatedAt') || doc.updateTime || new Date().toISOString(),
  };
}

function snapshotOf(order) {
  return JSON.stringify({ status: order.status, updatedAt: order.updatedAt });
}

function str(fields, key) {
  const v = fields[key];
  return v && typeof v.stringValue === 'string' ? v.stringValue : null;
}

function num(fields, key) {
  const v = fields[key];
  if (!v) return 0;
  if (typeof v.integerValue === 'string') return parseInt(v.integerValue, 10);
  if (typeof v.doubleValue === 'string' || typeof v.doubleValue === 'number') {
    return parseFloat(v.doubleValue);
  }
  return 0;
}

function ts(fields, key) {
  const v = fields[key];
  return v && typeof v.timestampValue === 'string' ? v.timestampValue : null;
}

function docNameId(name) {
  const segments = (name || '').split('/');
  return segments[segments.length - 1] || '';
}

// ---------------------------------------------------------------------------
// Google OAuth from a service account (Firebase console: Project settings ->
// Service accounts -> Generate new private key). RS256 JWT signed with
// WebCrypto, exchanged for a short-lived access token cached in KV.
// ---------------------------------------------------------------------------

async function accessToken(env, sa) {
  const cached = await env.PUSH_STATE.get('oauth');
  if (cached) {
    const c = JSON.parse(cached);
    if (typeof c.token === 'string' && c.expMs > Date.now() + 300000) return c.token;
  }
  const signed = await mintJwt(sa);
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion: signed,
  });
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) {
    throw new Error('OAuth token exchange failed: ' + JSON.stringify(json).slice(0, 300));
  }
  const entry = {
    token: json.access_token,
    expMs: Date.now() + (Number(json.expires_in) || 3600) * 1000,
  };
  await env.PUSH_STATE.put('oauth', JSON.stringify(entry), { expirationTtl: 3600 });
  return entry.token;
}

async function mintJwt(sa) {
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: SCOPES,
      aud: TOKEN_URL,
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput)),
  );
  return `${signingInput}.${b64url(signature)}`;
}

function pemToDer(pem) {
  const base64 = pem
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

function b64url(input) {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}