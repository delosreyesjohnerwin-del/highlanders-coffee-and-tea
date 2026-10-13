# Free push relay — Cloudflare Workers (no Blaze, no Firebase Functions)

The Firebase free (Spark) plan cannot run Cloud Functions. This relay does the
same job: every minute, it finds orders that changed (via `updatedAt`), sends
real FCM pushes to admins (new order) and to the customer (status changes), and
**backfills the same change into the recipient's in-app notification inbox**
(`notifications/{uid}/items`, see `lib/data/models/app_notification.dart`). The
copy, ids, deduplication and dead-token cleanup all match
`functions/src/notifications.ts` and the app.

Why the inbox write matters: an FCM push is best-effort — the OS may suppress
it, the user may have denied permission, or the device may be offline. The
stored record is not. It is what makes the bell badge correct and what the
Notifications screen lists when the app next opens. The record id is
deterministic (`new-order-<id>` / `order-status-<id>-<status>`), so an app that
*was* open — and already wrote its own record from the live order stream — and
this relay collapse onto a single document. The relay writes only when the
document is absent and never touches `read`, so it cannot un-read a record the
user already opened.

The trade-off: **up to ~60 seconds of latency** (cron granularity), not
event-driven. Everything else — "new order" to the café, "your order is…"
to the customer, foreground banner, the in-app inbox and badges, tap
deep-linking — works the same.

## 1. Prerequisites
- [Cloudflare account](https://dash.cloudflare.com/) — free tier is enough
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/install-and-update/) (one-off: `npm i -g wrangler`)
- Cloudflare auth: either `wrangler login`, or (used here, no browser) a custom
  API token exported as `CLOUDFLARE_API_TOKEN` with these account-scoped
  permissions: **Workers Scripts: Edit**, **Workers KV Storage: Edit**,
  **Workers Tail: Read**, **Account Settings: Read**, **User Details: Read**.
- A Firebase service account for this project (FIREBASE_SERVICE_ACCOUNT)
- FCM server access is available (the FCM API token is minted from that key)
- The app already writes `updatedAt` on orders — the code you shipped does this

## 2. Create a KV namespace for state
State is cheap and tiny: one checkpoint, one small snapshot per live order,
and one cached OAuth token. Create it:

```bash
cd push-relay
wrangler kv namespace create PUSH_STATE
```

Wrangler will print something like:

```toml
[[kv_namespaces]]
binding = "PUSH_STATE"
id = "9f34a2b1c3d4e5f6a7b8c9d0e1f2a3b4"
```

Open `push-relay/wrangler.toml` and replace the `id` with the printed value.

> This project's namespace id is already committed in `wrangler.toml`.

## 3. Add the Firebase service account (secret)
In the Firebase console: **Project settings → Service accounts → Generate new
private key**. Download the JSON (keep it safe, it has admin-ish access).

Add it to the Worker as a secret. Wrangler will encrypt it:

```bash
cd push-relay
wrangler secret put FIREBASE_SERVICE_ACCOUNT
# paste the entire JSON, then Ctrl+D (or Enter) as prompted
```

> Piping a file works and avoids the paste: PowerShell
> `cmd /c "wrangler secret put FIREBASE_SERVICE_ACCOUNT < path\to\key.json"`,
> or bash
> `wrangler secret put FIREBASE_SERVICE_ACCOUNT < path/to/key.json  # quotes for path directly, not content`.
> **Do not** run `wrangler secret put` with an empty/redirected-away stdin — it
> silently uploads an empty secret and still reports success. Verify with
> `wrangler secret list`.

## 4. Deploy
```bash
cd push-relay
wrangler deploy
```

This also registers the cron trigger (`* * * * *`). The Worker is live
immediately.

## 5. Cold-start sanity check (first run, no push spam)
First invocation does a one-pass backfill: it pages orders that already have
`updatedAt` and stores their status; it **does not push** for anything it sees.
It writes the checkpoint and stops. Trigger a manual run to see "cold start"
logged:

```bash
curl -X POST https://highlanders-push-relay.<your-subdomain>.workers.dev
```

Or watch logs: `wrangler tail --format pretty`.

Expect: `cold start: snapshotted orders up to 2026-10-11T...Z` and zero pushes.

## 6. Verify the real loop on the phone
1. Reinstall/update the debug APK on the INOI phone (or `flutter install`).
   - The app already has `firebase_messaging`, `POST_NOTIFICATIONS` declared,
     and `NotificationService` wired via `_navigatorKey` + provider.
2. Sign in with a real customer account.
3. Grant the notification permission (Android 13+ will prompt).
4. Place a fresh order from that phone — you should see:
   - **Café side** (an admin phone, same account/role or another admin): a
     push with title `New order received` and a body carrying the order id
     (`New Order Received #HL-… · Name · N items · ₱XX.XX`) within ~60s. Tapping
     it deep-links to the admin orders board. The bell in the admin top bar
     also gains an unread dot, and the record is listed under Notifications.
5. As an admin, change the order status (confirmed → preparing → ready/pickup)
   from the admin panel. The customer should get a status push for each real
   status change, also within ~60s, worded `Your order #HL-… has been
   confirmed!` and so on. Tapping it deep-links to that specific order's
   tracking screen, and the customer's bell badge gains one.
6. **Closed-app check**: kill the app on the phone, place/advance an order, then
   reopen the app. The push may or may not have arrived, but the notification is
   in the inbox and the bell badge is set — that is the relay's backfill at work.
7. Uninstall/reinstall on the same phone: token rotates, the Worker deletes the
   dead token and picks up the new one next time (FCM send for the old one
   returns 404/400, which triggers cleanup).

## 7. Health, costs, limits
- **Free**: 100,000 scheduled requests/day on Workers Free. 1 run/min × 1440/day
  = ~1440 requests/day — ~69× headroom. CPU is well under 10ms.
- **Latency**: ≤ 60 seconds. For a café kiosk it's perfectly fine; if you want
  sub-minute later, you can trigger externally — but not needed.
- **No retries, no alerts**: if a run throws, the next tick resumes from the
  same checkpoint. Inspect `wrangler tail` if pushes ever stop.
- **Idempotent**: re-polling the boundary is harmless — we snapshot by order id
  and only act on a real status delta.

## 8. Switching to Blaze later (optional)
If you do upgrade to Blaze and want event-driven pushes, deploy the functions
as documented in `NOTIFICATIONS.md`: `firebase deploy --only functions` +
the staged rules deploy. The two paths are mutually exclusive — disable the
Worker's cron if you do so (comment `[triggers]` in `wrangler.toml` and
`wrangler deploy`, or pause it from the Cloudflare Workers dashboard). They
won't conflict because `functions/` are Firestore triggers, the Worker polls.