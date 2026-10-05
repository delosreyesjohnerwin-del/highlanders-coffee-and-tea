# Highlanders Coffee & Tea

Android ordering + delivery app for a single café in **Lumban, Laguna**.
Strictly monochrome design, Firebase-ready, PHP currency.

> **Status:** Customer app and admin panel both complete, running against in-app
> mock data. Login, role routing and the Firestore role lookup are wired; the
> Google *runtime* backend still needs `google-services.json` — see
> [Not done yet](#not-done-yet). The app builds and installs today, and falls
> back to a demo sign-in until then.

---

## Run it

```powershell
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
flutter pub get
flutter run                 # needs a connected device or emulator
```

Build installable artifacts:

```powershell
flutter build apk --debug     # 148 MB, fast
flutter build apk --release   # 49 MB, signed with the debug key
```

Verify:

```powershell
flutter analyze   # clean
flutter test      # 55 tests
```

---

## Design system

Every colour comes from one file: `lib/core/theme/bw_colors.dart`. There are no
brand hues anywhere — the UI is built from five greys.

| Token | Value | Used for |
| --- | --- | --- |
| `bg` / `surface` | `#FFFFFF` | page and card background |
| `subtle` | `#F5F5F5` | inactive pills, icon badges, muted chips |
| `border` | `#E5E5E5` | 1px hairline card borders and dividers |
| `borderStrong` / `text` | `#111111` | outlined button strokes, headings, body |
| `textMuted` | `#666666` | secondary copy, timestamps, captions |
| `inverse` | `#000000` | solid CTAs, active tab, promo cards |

A test asserts every token has `r == g == b`, so a stray tint fails CI.

Shared widgets live in `lib/core/widgets/`: `BwCard`, `BwButton`, `BwPill`,
`BwBadge`, `BwSegmented`, `BwAvatar`, `BwMenuRow`, `BwStat`, `BwThumb`,
`BwIconButton`.

> **Known trade-off:** the brief asks for strict monochrome, so form validation
> and errors are signalled with an icon and a heavier border rather than red.
> If you want coloured errors, that's a one-line change in `bw_colors.dart`.

---

## Structure

```
lib/
  main.dart                     Firebase init, portrait lock, system UI
  app.dart                      providers + MaterialApp (withRouter variant)
  core/
    firebase/                   try/catch Firebase bootstrap, test reset
    theme/                      colours, metrics, ThemeData
    utils/formatters.dart       ₱ formatting, dates, distances, ETAs
    widgets/                    the Bw* component library
  data/
    models/                     menu, order, staff, coverage (barangays + fees)
    mock/mock_data.dart         seed menu, promos, users, orders, staff, trading
  services/
    auth_service.dart           AuthService / RoleResolver contracts
    mock_auth_service.dart      demo sign-in, used when Firebase is absent
    google_auth_service.dart    Firebase Auth + Google, Firestore role lookup
  state/
    catalog_provider.dart       menu, categories, promos, stock, open/closed
    cart_provider.dart          cart + pricing (subtotal + delivery fee)
    session_provider.dart       auth state, user, addresses, order history
    admin_provider.dart         shop-wide state + the analytics behind the panel
  features/
    shell/                      IndexedStack + persistent 4-tab nav
    home/                       location header, promo, categories, menu
    menu/                       item detail
    cart/                       cart + the drawn empty state
    checkout/                   payment, address, place order
    orders/                     Active / Past segmented list
    order_tracking/             status stepper, driver card, success screen
    profile/                    black header, stats card, menu rows
    auth/                       login, sign up, root role router
    admin/                      6-section panel shell + sections/
```

### Auth and roles

The login screen is monochrome like everything else: brandmark, a segmented
Customer/Admin toggle, Google as the primary action, then the email/password
form with Remember me and Forgot password.

Which panel opens is decided by `SessionProvider`, not by the toggle — the
toggle only pre-fills a demo address so the admin panel is two taps away.
Roles come from `users/{uid}` in Firestore, so promoting someone is editing one
field in the console, no Cloud Function and no Admin SDK.

`firestore.rules` is hand-written and ready to paste into the console. It lets a
user create their own doc as `customer`, blocks them from changing their own
`role`, and denies everything else by default.

> **Deliberate:** the role lives in Firestore rather than a custom claim. A
> claim is tamper-proof but needs a trusted server to set it, which means
> Admin SDK and billing. For a single café, a locked-down document is the better
> trade. The rules file is where the guarantee lives — review it before launch.

> **Deliberate:** sold-out items stay listed with an "Out of stock" note and
> block Add to cart. Hiding a bestseller because it ran out reads as a bug to a
> regular; saying so plainly does not.

### Admin panel

Six sections behind one scaffold, so switching never builds a back stack:

| Section | What it shows |
| --- | --- |
| Overview | revenue / orders / active users / AOV, 7-day bar chart, top items, restock |
| Inventory | `DataTable` of stock + status chips, add/edit sheet, stock is editable |
| Sales | payment split, transactions, gross, average ticket |
| Orders | in-flight board, filter chips, one-tap advance or cancel |
| Staff | shift roster, role filters, start/end shift |
| Settings | shop config, hours, fees, backend status |

At ≥720dp a persistent `NavigationRail` appears; below that a `Drawer` takes
over. Both are the same `IndexedStack` underneath, so scroll position and filter
state survive a switch.

Inventory uses a `DataTable` inside a horizontal scroller with fixed column
widths. A table is the right control here — the data is tabular, sortable and
compared column-to-column, which a card list is bad at.

### Order lifecycle

`pending → confirmed → preparing → ready → out_for_delivery → delivered`,
plus `failed_delivery` and `cancelled`.

Orders store an `addressSnapshot` — a denormalised copy of the address — so
later edits to a saved address never rewrite order history.

### Delivery pricing

`lib/data/models/coverage.dart` holds the fee schedule and the Lumban barangay
table. Distance is straight-line (haversine) from café to barangay centroid:
no geocoding API, no billing account, no rate limits, works offline. That's a
deliberate fit for a single municipality.

Current placeholder tiers — **these need your real rates**:

| Distance | Fee |
| --- | --- |
| 0 – 1.5 km | ₱25 |
| 1.5 – 3 km | ₱35 |
| 3 – 5 km | ₱45 |
| 5 – 8 km | ₱55 |
| 8 km+ | ₱65 |

Free delivery over ₱500. Coverage radius 10 km.

---

## Not done yet

1. **Firebase runtime wiring.** The Dart side is done — `GoogleAuthService` and
   `FirestoreRoleResolver` exist and the app falls back to `MockAuthService`
   when Firebase is absent. What is missing is `android/app/google-services.json`
   and the Gradle plugin that consumes it. Once the file exists:
   ```powershell
   # settings.gradle.kts -> add com.google.gms.google-services
   # app/build.gradle.kts -> apply it, enable core library desugaring
   dart pub global activate flutterfire_cli
   flutterfire configure --project=highlanderscoffeeandtea-f03fa
   ```
   Until then the login screen says which backend is live, so a dormant Google
   button is never a mystery. **The remaining pieces are deliberately
   Gradle-only** — no Dart has to change.

2. **Firestore data layer.** Auth uses Firestore today for the role lookup only.
   Menu, orders, promos and settings still come from `MockData`. Swapping them
   means rewriting `lib/state/*` and nothing in `lib/features/` — the providers
   are the only place that touches data. Planned collections: `menuCategories`,
   `menuItems`, `orders`, `users` (role: customer | admin), `promos`, `settings`,
   `drivers`, `addresses`. Barangays stay bundled in-app.

3. **Real data.** Placeholder values that must be replaced:
   - Café coordinates — `LumbanCoverage.cafeLat/cafeLng`
   - Barangay centroids — `LumbanCoverage.barangays` (18 invented names)
   - Menu, prices, photos — `MockData.menu` (19 invented items)
   - Fee tiers above

4. **Payments.** PayMongo is the intended aggregator (direct GCash/Maya
   merchant APIs need months of accreditation). Checkout currently simulates a
   ~900 ms round trip. Needs a Cloud Function for the webhook and a
   `PaymentService` interface with a `MockProvider` first.

5. **Security rules.** `firestore.rules` is written and ready to paste into the
   Firestore console, but **has never been deployed or tested**. Review it
   before launch. Note it is stricter than a custom-claim design would need to
   be, which is the point.

6. **Live map.** Deliberately omitted from v1 in favour of the status stepper and
   driver card. Adding one means a Maps API key and billing.

---

## Notes

- Android only, portrait only.
- `ShellNav.index` is process-global static state. Tests must call
  `ShellNav.reset()` between cases (see `test/screens_test.dart`).
- `test/screens_test.dart` renders every screen at 360×780 and fails on layout
  overflow — catch regressions there rather than by eyeballing. It also sweeps
  all six admin sections.
- `test/auth_test.dart` covers behaviour rather than layout: role routing,
  stock semantics and the admin analytics.
- The test font is fixed-width, so every glyph is exactly `fontSize` wide. That
  is useful: it surfaces real overflow at 360dp that a proportional font hides.
  It also means any `Row` holding text needs a `Flexible`/`Expanded` or an
  ellipsis, and any `BwButton` inside a `Row` needs `expand: false`.
- `BwButton` defaults to `expand: true`, i.e. `width: double.infinity`. That is
  an invalid constraint inside a `Row` and throws during layout. Pass
  `expand: false` for inline buttons.
