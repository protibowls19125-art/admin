# Proti Bowls

A contactless-dining system: two Flutter web apps sharing one Supabase backend.

- **`user/`** — customer app (`mpro_dining_user`). Public, no login. Browse the
  menu, order dine-in/takeaway/delivery, and separately buy a recurring meal
  subscription.
- **`admin/`** — staff console (`mpro_dining_admin`). Supabase-Auth login,
  gated by role.
- **Supabase** — Postgres (RLS-scoped tables), edge functions, a `pg_cron`
  nightly job, and a Meta WhatsApp Cloud API integration for the subscription
  side.

The restaurant-ordering side and the subscription side share the database and
the admin app, but otherwise run as separate features — separate tables,
separate edge functions, separate customer-app screens, and (as of this
session's role split) separate staff roles.

---

## Repo layout

```
Billing/
├── user/                    Customer Flutter app (source)
├── admin/                   Staff Flutter app (source + committed build — see Deployment)
├── gh-pages-deploy/         Separate git worktree: user/'s built output, on the gh-pages branch
├── supabase/functions/      Edge functions (Deno)
├── credentials/             Local-only credentials template + notes (gitignored actual values)
├── *.sql (repo root)        Migration history — see "SQL files" below before running any
└── PROJECT_INDEX/           Older reference docs — check dates before trusting; several are stale
```

### SQL files — read before running

The repo root has many `.sql` files from different points in the project's
history (`SUPABASE_SETUP.sql`, `SUPABASE_SETUP_FIXED.sql`, `SUPABASE_SIMPLE.sql`
are three **competing early versions** of the same base schema; `ROLES.sql`,
`SECURITY_HARDENING.sql`, `SUBSCRIPTION_SETUP.sql` are the ones that actually
layer on top of whatever base got run). If you're setting up a fresh project,
don't run the old `SUPABASE_SETUP*`/`SIMPLE` variants blindly — check what's
already applied first. `credentials/RUN_THIS_IN_SQL_EDITOR.sql` duplicates
parts of `SUBSCRIPTION_SETUP.sql`; prefer the latter.

---

## Running locally

Both apps are standard Flutter web apps:

```bash
cd user   && flutter pub get && flutter run -d chrome
cd admin  && flutter pub get && flutter run -d chrome
```

Both read Supabase credentials via `.env` (see `credentials/credentials.template.env`
for the full list) with fallback values baked into `SupabaseService` for web
builds where `.env` isn't bundled.

## Deployment

The two apps deploy differently — this tripped us up more than once this
session, worth knowing:

- **`user/`** — `flutter build web --base-href /protibowl/`, then copy
  `build/web/*` into the **separate git worktree** at `gh-pages-deploy/`
  (checked out to the `gh-pages` branch of the same repo), commit, push.
  Pushing `user/`'s `main` branch alone does **not** update the live site.
- **`admin/`** — the built output (`index.html`, `main.dart.js`, etc.) is
  committed **directly into `admin/`'s own `main` branch root**, alongside
  the Dart source, and served by GitHub Pages from that branch
  (`flutter build web --base-href /admin/`, copy `build/web/*` over the
  tracked root files, commit, push). No separate worktree/branch here.

---

## Roles & access

`profiles.role` (plain `TEXT`, validated by a CHECK constraint added this
session — see `is_staff()`/`is_sub_staff()` in `ROLES.sql`/`SUBSCRIPTION_SETUP.sql`):

| Role | Admin app routes | Database access |
|---|---|---|
| `admin` | everything | full read/write everywhere |
| `sub_manager` | `/subs`, `/subs-members`, `/subs-kitchen`, `/subs-delivery`, `/subs-meals`, `/subs-settings` | subscription tables, full manager access |
| `gym_chef` | `/kds` only | restaurant `orders`/`order_items` (via `is_staff()`) |
| `gym_delivery` | `/orders`, `/orders/:id` only | restaurant `orders`/`order_items` (via `is_staff()`) |
| `subs_chef` | `/subs-kitchen` only | subscription tables (via `is_sub_staff()`) |
| `subs_delivery` | `/subs-delivery` only | subscription tables (via `is_sub_staff()`) |
| `member` | none (customer-app only) | own subscription row only; meal status changes only via the `confirm_meal` RPC |
| anything else (null, unrecognized, or a retired value) | none — signed out, sent to `/login` | — |

All routing enforcement lives in one place: `admin/lib/router.dart`'s
`_authGuard`. No individual admin page re-checks the role itself, so a new
route added there needs a matching case in that switch or it falls through to
the fail-closed default.

The subscription kitchen/delivery screens used to be one combined page
(`/subs-kds`) — split this session into `/subs-kitchen` (prep only) and
`/subs-delivery` (dispatch only) so `subs_chef` and `subs_delivery` are
actually confined to their own concern, mirroring how the gym side already
separated `/kds` from `/orders`.

---

## Core flows

### Placing a restaurant order

1. `MenuProvider.fetchAll()` loads `menu_items` directly (no edge function).
2. Add to cart (persisted locally) or use the product page's own single-item
   "Add to Order" shortcut (dine-in/takeaway only, skips add-on pricing —
   a known inconsistency with the main cart flow, not yet reconciled).
3. Checkout collects name/phone/order type (gated by service hours)/payment
   method. Only item IDs + quantities are sent to the server — pricing is
   always computed server-side in `razorpay-create-order`.
4. Online payment: Razorpay checkout → `razorpay-verify-payment` (HMAC
   signature check). COD: created directly as `pending`.
5. `/my-orders` polls `get-order-status` every 10s for live status.
6. **Cancellation** (`cancel-order` edge function, added this session): only
   allowed while `status ∈ {pending, confirmed}`; the server re-checks the
   status itself before writing — the client's belief about status is never
   trusted. Once cancelled, the order drops off the Kitchen Display
   automatically (KDS filters to `pending`/`confirmed`/`preparing`).

### Subscribing + the nightly WhatsApp reminder

1. Pick a plan → pay (`subscription-create-order` → Razorpay →
   `subscription-verify-payment`) → fill onboarding details
   (`subscription-submit-details` — proof of access here is just knowing the
   Razorpay order/payment id pair, since there's no login yet).
2. A `sub_manager`/`admin` approves in `/subs`, which creates the member's
   login (`admin-manage-member`) and sends a WhatsApp welcome.
3. Member logs into the customer app's `/member` and sees their premium card;
   can confirm/skip tomorrow's meal via the `confirm_meal` RPC.
4. `pg_cron` calls `send-daily-meal-whatsapp` every 5 minutes; it only
   actually sends once past the admin-configured reminder time (default 8 PM
   IST) and once per day. Sends as an **approved Meta message template**
   (not free text) since it's business-initiated and the member may not have
   messaged in the last 24 hours — free text would be silently rejected.
5. Replies land on `whatsapp-webhook` (public, verified by a shared secret),
   update `meal_confirmations`, and trigger a free-text acknowledgment (fine
   here since the member just opened the 24-hour window by messaging first).
6. Confirmed meals surface on `/subs-kitchen`; dispatch happens on
   `/subs-delivery`.

---

## Edge functions

| Function | Trigger | Auth |
|---|---|---|
| `razorpay-create-order` | Checkout (online or COD) | Public, rate-limited |
| `razorpay-verify-payment` | Razorpay callback | HMAC signature |
| `get-order-status` | Order-tracking poll | Gateway JWT only, no PII returned |
| `cancel-order` | Cancel button | Public — order UUID is the proof of access |
| `subscription-create-order` | "Subscribe" button | Public, rate-limited |
| `subscription-submit-details` | Onboarding form | Razorpay order/payment id pair |
| `subscription-verify-payment` | Razorpay callback | HMAC signature |
| `admin-manage-member` | Approve/reject/remove in `/subs` | JWT, `admin`/`sub_manager` only |
| `send-daily-meal-whatsapp` | `pg_cron` every 5 min, or "Send now" | Cron secret, or manager/admin JWT |
| `whatsapp-webhook` | Meta (inbound replies) | Public by deploy flag; verify-token + signature |

`print-to-thermal-printer` and `send-whatsapp-notification` existed earlier
but were dead code (no callers anywhere) — removed this session.

---

## Known limitations

- **The order-confirmation page's "✅ Order submitted to business API"
  message is not real.** `user/lib/services/order_api_service.dart` is a
  self-documented template — no real endpoint or credentials exist anywhere
  in the codebase for it. Flagged, not yet fixed (needs a decision: wire up
  a real integration, or make the UI stop claiming a success that didn't
  happen).
- The single-item "Add to Order" shortcut on the product page bypasses
  add-on pricing and service-hours checks that the main cart checkout
  enforces — a pre-existing inconsistency, not yet reconciled.
- `is_staff()` (`ROLES.sql`) includes a hardcoded email bypass that
  `is_admin()` (`SECURITY_HARDENING.sql`) doesn't — two separate
  "is this an admin" checks that could be consolidated.
