# Session Status — continue from here

## Prompt to paste into a fresh session

```
Read C:\Final_protibowl\SESSION_STATUS.md for full context on what's been
built and what's outstanding, then:
1. Check daily_meal_confirm template approval status (WABA 1764090017942543,
   template id 1551784033404670 — YES/NO quick-reply buttons).
2. Check WhatsApp Flow publish status (Flow ID 1000968709654938) — still
   blocked by Meta Integrity review as of last check; manual review ticket
   was filed, awaiting their response.
Report both, then ask what to work on next.
```

## What's currently outstanding

1. **`do_you_need_meal_today` template** (was `daily_meal_confirm`, briefly
   `meal_confirmation` — went through two renames on 2026-08-05: first to
   fix a body-text encoding bug where an emoji had been mangled into
   literal `??`, then per explicit request to `do_you_need_meal_today`).
   Plain UTILITY template, YES/NO quick-reply buttons, id
   `1057025516722402`. **2026-08-07: confirmed APPROVED via Graph API.**
   Code (`send-daily-meal-whatsapp`) defaults to this name already —
   double-check Admin → Subscriptions → Settings → WHATSAPP SEND still
   points at it (it may have been switched to a stopgap while pending).
2. **WhatsApp Flow** (`tomorrow_meal_survey`, id `1000968709654938`) —
   fully built, 0 validation errors, but stuck in `DRAFT`. Publish fails
   with `Blocked by Integrity` (code 139000/4233020) — a new-account Meta
   review hold, unrelated to our code. Manual-review ticket filed via Meta
   Business Help Center chat (see `META_SUPPORT_TICKET_DRAFT.md` /
   `META_SUPPORT_REPLY_DRAFT.md`). **2026-08-05: Meta support agent
   confirmed they're proceeding with the manual integrity review** and
   will notify via Support Inbox/email — no fixed ETA given. Agent also
   suggested (as due diligence, not a stated cause) re-checking the Flow
   against WhatsApp Flow design principles, ToS, Business Messaging
   Policy, and Commerce Policy while waiting. Re-checked status via Graph
   API same day: still `DRAFT`, still 0 validation errors — no change yet.
   **The daily meal flow no longer depends on this Flow** — see below.

## Current design: daily meal confirmation (no Flow needed)

Reverted away from the Flow to a simpler, working-today approach:
1. Nightly job (`send-daily-meal-whatsapp`) sends `do_you_need_meal_today`
   (YES/NO quick-reply buttons) to every active member.
2. `whatsapp-webhook` already handles the button tap like a typed
   "yes"/"no" reply — flips `meal_confirmations.status`, sends
   `confirm_ack`/`skip_ack`.
3. On YES (if the member has no `food_preference` yet), it also sends
   `food_preference_confirm` (veg/non-veg/mixed) — **already Meta-approved
   and working**.

The Flow infrastructure (RSA keypair, `whatsapp-flow-endpoint`, the draft
Flow itself) is left in place, dormant — not deleted, in case Meta's
review eventually clears it.

## Everything else built this session (all done, deployed, `flutter analyze`
clean at last check)

- Subscription model: Survey Responses page, Today's Meal review/push-to-
  kitchen queue (new `pushed_to_kitchen`/`delivery_time` columns on
  `meal_confirmations`), veg/non-veg/morning/evening breakdown on Kitchen
  Display, admin-editable `food_preferences` table (replacing the old
  hardcoded veg/non-veg/vegan/eggetarian list), meals-left-in-plan on
  member cards.
- Gym model: delivery orders now stop at `prepared` on KDS (not
  `completed`) and hand off to a new **Gym Delivery** page for agent
  assignment (reuses the same `delivery_agents` roster as the subscription
  model, shared read RLS added for gym roles).
- **Agent Performance** page (`/agent-performance`) — deliveries per agent,
  today/this week/this month + daily breakdown, combined across both
  models. Needs real rows in `delivery_agents` to show anything — confirm
  agents have actually been added (checked empty as of last verification;
  "+ NEW AGENT" buttons exist on both delivery pages now).
- Fixed a real "notify during build" console-error bug on the Subscription
  Dashboard, Members, Settings, KDS, and Orders pages' `initState`.
- Fixed the delivery-charge-on-dine-in-orders billing bug (e-bill now
  reads a stored `delivery_charge`/`gst_amount` instead of inferring via
  subtraction).
- Removed the kitchen notification sound from the subscription KDS
  specifically (kept on the restaurant KDS and Today's Meal page).
- Hid MEMBERSHIP REVENUE from `sub_manager` on the Subscription Dashboard.
- Cancelled/not done: replacing the delivery location picker
  (`location_picker.dart`) with Google Maps — was waiting on an API key
  when cancelled.

## Key IDs

| What | Value |
|---|---|
| WABA ID | `1764090017942543` |
| Phone number ID | `1258254477370342` |
| Flow ID | `1000968709654938` (`tomorrow_meal_survey`, DRAFT, blocked) |
| `do_you_need_meal_today` template id | `1057025516722402` (APPROVED) |
| `food_preference_confirm` template | APPROVED, working |
