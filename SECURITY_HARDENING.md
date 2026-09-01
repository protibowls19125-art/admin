# 🔐 Security Hardening — Runbook

Closes the three criticals from the security review:
- **C1** open RLS (anyone could read/write the whole DB)
- **C2** payment bypass (write a completed order without paying)
- **C3** client-controlled price (pay ₹1 for a ₹1000 order)

**How:** the price is now computed **server-side** from the DB, all order writes go
through **edge functions using the service-role key**, and RLS is locked so the anon
key can only **read the menu**.

## New architecture

```
Customer app  ──(item ids + qty, NO prices)──►  razorpay-create-order (service role)
                                                  · looks up real prices in menu_items
                                                  · computes total
                                                  · online → creates Razorpay order + pending row
                                                  · cod    → writes order row
        ◄── razorpayOrderId / orderNumber ───────┘
   checkout.js ──pay──►  razorpay-verify-payment (service role)
                          · verifies HMAC signature
                          · flips awaiting_payment → pending (paid)
   my-orders  ──order ids──►  get-order-status (service role)  ← only id/status, no PII
```

## ⚠️ Apply in THIS order (avoids a breakage window)

The old anon-write path stops working once RLS is applied, and the new functions
replace the old ones, so deploy functions + the new app build **before** the SQL.

### 1. Deploy the 3 edge functions (all `verify_jwt = false`)
- `razorpay-create-order`  (rewritten)
- `razorpay-verify-payment` (rewritten)
- `get-order-status`        (new)

They need these secrets (already set, except confirm the Supabase ones exist):
`RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`.

### 2. Deploy the rebuilt customer app
`user/build/web/` is already built (base href `/protibowl/`). Publish it.

### 3. Run `SECURITY_HARDENING.sql` in the Supabase SQL editor
This drops the open policies and adds locked-down ones. **Then edit step 9** of the
SQL (uncomment + set your real admin email) so `is_admin()` returns true for your
admin login.

### 4. Confirm the admin app still works
The admin app reads/writes orders as an **authenticated admin**. After step 3, the
signed-in admin user must have `profiles.role = 'admin'` (step 9 does this). No admin
code change is required, but the admin **must be logged in**.

## What each piece enforces

| Threat | Before | After |
|--------|--------|-------|
| Read all customers' PII | anyone w/ anon key | admins only (RLS); customers get their own status via `get-order-status` |
| Write/delete any row | anyone | service-role functions + admins only |
| Order without paying | trivial direct insert | impossible — only functions write orders |
| Pay less than total | client sent `amount` | server computes amount from DB prices |
| Tamper menu prices | anyone | admins only |
| Upload to storage | anyone | admins only |

## Known limitations / follow-ups
- **Add-on / spice pricing** (product detail "quick order") is **not yet priced
  server-side** — it now charges the base menu price. To price add-ons securely, add
  an `add_ons` table and include them in the server total. (Flagged in code.)
- **Customer cancel** updates only the local mirror now (anon can't write `orders`).
  Add a `cancel-order` edge function (verify ownership by order id + phone) to also
  flip the DB row.
- Consider **rate limiting** on the public functions.
- **Rotate the Razorpay key secret** and **revoke the Supabase PAT** that were shared
  in chat.

## Rollback
If something breaks, re-running the original `SUPABASE_SETUP_FIXED.sql` policy block
(`FOR ALL USING (true)`) restores the old open behavior. Keep that handy during cutover.
