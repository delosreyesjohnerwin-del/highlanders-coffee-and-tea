# Free push relay — Cloudflare Workers (no Blaze, no Firebase Functions)

The Firebase free (Spark) plan cannot run Cloud Functions. This relay does the
same job: every minute, it finds orders that changed (via `updatedAt`) and
sends real FCM pushes to admins (new order) and to the customer (status
changes). The copy, deduplication and dead-token cleanup all match
`functions/src/notifications.ts`.

The trade-off: **up to ~60 seconds of latency** (cron granularity), not
event-driven. Everything else — "new order" to the café, "your order is…"
to the customer, foreground banner, tap deep-linking, works exactly the same.

## 1. Prerequisites
- [Cloudflare account](https://dash.cloudflare.com/) — free tier is enough
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/install-and-update/) (one-off: `npm i -g wrangler`)
- Logged into wrangler: `wrangler login`
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

Open `push-relay/wrangler.toml` and replace `PASTE_KV_NAMESPACE_ID_HERE` with
the printed `id`.

## 3. Add the Firebase service account (secret)
In the Firebase console: **Project settings → Service accounts → Generate new
private key**. Download the JSON (keep it safe, it has admin-ish access).

Add it to the Worker as a secret. Wrangler will encrypt it:

```bash
cd push-relay
wrangler secret put FIREBASE_SERVICE_ACCOUNT
# paste the entire JSON, then Ctrl+D (or Enter) as prompted
```

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
     push with title `New order` and a short body (`Name · N items · ₱XX.XX`)
     within ~60s. Tapping it should deep-link to the admin orders board.
5. As an admin, change the order status (confirmed → preparing → ready/pickup)
   from the admin panel. The customer should get a status push for each real
   status change, also within ~60s. Tapping it should deep-link to that
   specific order's tracking screen.
6. Uninstall/reinstall on the same phone: token rotates, the Worker deletes the
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