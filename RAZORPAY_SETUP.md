# 💳 Razorpay Online Payment — Setup

Server-verified Razorpay integration for the **customer web app** (`user/`). The customer pays
online; the order is created **only after the payment signature is verified server-side**. No
Razorpay secret ever ships in the browser.

## How it works

```
Customer taps "Place Order" (Online Payment)
   │
   ├─1► razorpay-create-order  (edge fn, uses KEY_SECRET) ──► returns { orderId, keyId }
   │
   ├─2► Razorpay checkout.js opens in the browser  ──► customer pays (UPI/Card/NetBanking)
   │
   ├─3► razorpay-verify-payment (edge fn, uses KEY_SECRET) ──► verifies HMAC signature
   │
   └─4► verified ✅ → OrderProvider.createOrder(...) runs; payment info saved on the order
        verified ❌ / cancelled → order is NOT created, customer sees a message
```

## Pieces added

| Piece | Path |
|-------|------|
| Create-order function | `supabase/functions/razorpay-create-order/index.ts` |
| Verify-payment function | `supabase/functions/razorpay-verify-payment/index.ts` |
| Web payment service | `user/lib/services/razorpay_service.dart` (`RazorpayService.payAndVerify`) |
| checkout.js include | `user/web/index.html` |
| Checkout hook | `user/lib/pages/order_form_page.dart` (runs payment before `createOrder`) |
| Payment record | `user/lib/providers/order_provider.dart` (`paymentDetails` → `customer_info.payment`) |

## One-time setup

### 1. Set the secrets on Supabase (server-side only)
Use your **test** keys from the Razorpay dashboard. These are stored as edge-function secrets —
they are never bundled into the web app.

```bash
supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxxxx
supabase secrets set RAZORPAY_KEY_SECRET=your_test_key_secret
```

### 2. Deploy the edge functions — with JWT verification OFF

```bash
supabase functions deploy razorpay-create-order --no-verify-jwt
supabase functions deploy razorpay-verify-payment --no-verify-jwt
```

> ⚠️ **`--no-verify-jwt` is required.** These functions are called from the browser, so the CORS
> **preflight (OPTIONS)** request carries no JWT. With JWT verification on, Supabase's gateway
> rejects the preflight with **401 before the function runs** — the browser reports this as a CORS
> error: *"preflight … does not have HTTP ok status."* Disabling JWT verification lets the
> `OPTIONS` handler (which returns the CORS headers) run. The Razorpay **secret still never leaves
> the server** — it lives only in function secrets. `supabase/config.toml` also sets
> `verify_jwt = false` for both so future CLI deploys keep this setting.
>
> **Dashboard equivalent:** Edge Functions → open the function → Details/Settings → toggle
> **"Verify JWT" OFF** for both functions.

### 3. Build & deploy the customer web app
No code changes needed — just rebuild so `index.html` (with checkout.js) ships:

```bash
cd user
flutter build web --release --base-href /protibowl/
# publish user/build/web → protibowl repo gh-pages   (see PROJECT_INDEX/06_DEPLOYMENT.md)
```

## Testing (test mode)

Razorpay **test cards / UPI** (only work with `rzp_test_` keys):
- **Card:** `4111 1111 1111 1111`, any future expiry, any CVV, any name.
- **UPI success:** `success@razorpay`  ·  **UPI failure:** `failure@razorpay`

Flow to check:
1. Add items → cart → **Place Order** → choose **Online Payment** → **Place Order**.
2. Razorpay modal opens → pay with a test card.
3. On success you land on `/confirmation` and the order appears with
   `customer_info.payment = { provider: razorpay, status: paid, payment_id, order_id }`.
4. Cancel/close the modal → no order is created, you see "Payment cancelled".

## Notes & guarantees

- **Secret safety:** `KEY_SECRET` lives only in Supabase edge-function env. The browser receives
  only the publishable `KEY_ID` (returned by the create-order function).
- **No order without payment:** for `online`, `createOrder` runs **only** after server-side
  signature verification passes.
- **COD unchanged:** cash-on-delivery skips Razorpay entirely.
- **Going live:** swap the secrets for `rzp_live_...` keys and redeploy the functions.
- See `PROJECT_INDEX/04_BACKEND.md` for where this sits in the backend, and `credentials/` for the
  credential template.

## Webhook (server-side reconciliation)

`razorpay-verify-payment` only runs if the customer's browser stays open long enough to call it.
`razorpay-webhook` (`supabase/functions/razorpay-webhook/index.ts`) is Razorpay calling **us**
directly, so a payment still gets finalized (`awaiting_payment` → `pending`) even if the tab closes
right after paying. It's idempotent — if `razorpay-verify-payment` already finalized the order, the
webhook is a no-op.

### 1. Set the webhook secret and deploy

```bash
supabase secrets set RAZORPAY_WEBHOOK_SECRET=your_webhook_secret
supabase functions deploy razorpay-webhook --no-verify-jwt
```

### 2. Webhook URL for the Razorpay Dashboard

```
https://esiatypehvnyeemvnzbl.supabase.co/functions/v1/razorpay-webhook
```

Dashboard → **Settings → Webhooks → Add New Webhook** (do this in **Test Mode**, top-right toggle,
so it pairs with your `rzp_test_` keys):
- **Webhook URL:** the link above
- **Secret:** any string you choose — put the *same* value in `RAZORPAY_WEBHOOK_SECRET` above
- **Active events:** `payment.captured`, `payment.failed`

### 3. Test it

Razorpay's dashboard has a **"Test Webhook"** button next to the saved webhook that sends a signed
sample `payment.captured` event — use it first to confirm the signature check passes (function logs
should show no `Bad signature` error, `supabase functions logs razorpay-webhook`).

For an end-to-end test, place a real online order in test mode (see **Testing** above) — the
`razorpay-verify-payment` call will normally finalize it first, but you can confirm the webhook path
independently by checking `supabase functions logs razorpay-webhook` after the payment; you should
see the event come in and (since the order is already `pending`) do nothing, proving the idempotency
guard works.
