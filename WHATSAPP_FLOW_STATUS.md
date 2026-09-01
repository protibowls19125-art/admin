# WhatsApp Meal Survey Flow — Status

## Prompt to check status later

Paste this to Claude in this repo whenever you want to check:

```
Check the WhatsApp Flow publish status. Flow ID 1000968709654938, WABA ID
1764090017942543. GET its status/validation_errors, then try POST .../publish
again and report whether it's still "Blocked by Integrity" or has gone
through.
```

## What's blocked

Flow `1000968709654938` ("tomorrow_meal_survey") is fully built and validated
(0 validation errors) but stuck in `DRAFT`. Publishing fails with:

```
Blocked by Integrity (code 139000, subcode 4233020)
```

This is a Meta-side hold on brand-new WhatsApp Business accounts publishing
Flows — not a bug in our code. It clears with account age, or can be
escalated via Meta's Business Help Center (reference any `fbtrace_id` from a
publish attempt). Confirmed a static (no-endpoint) Flow doesn't dodge it
either — this account's Flow validator doesn't support conditional (`if`)
branching, so a real branching survey needs the data endpoint regardless,
which is what's gated.

Once it publishes: task 5 below (Flow-button template) can go out — that's
the only remaining step, and the curl command for it is already proven
working (fails today only because Meta rejects a FLOW button pointing at an
unpublished Flow).

## What's done (this session's build)

1. **DB**: `subscriptions.morning_preference` / `evening_preference` columns added.
2. **Encryption**: RSA keypair generated; public key registered with Meta for phone number `1258254477370342`. Private key stored as edge secret `WHATSAPP_FLOW_PRIVATE_KEY`.
3. **Edge function** `whatsapp-flow-endpoint` — deployed, decrypts/encrypts per Meta's Flow protocol, handles screens `MEAL → PREFERENCE → (MIXED_TIME) → SUCCESS`. Crypto round-trip and full screen routing tested against a real subscriber and verified correct.
4. **Flow JSON** authored and uploaded to Flow `1000968709654938`, version `7.2`, 0 validation errors. `endpoint_uri` set and health-checked successfully by Meta.
5. **Template**: `daily_meal_survey` — ready to submit (body wording validated), blocked only on the Flow publish above.
6. **`send-daily-meal-whatsapp`**: updated to send the Flow-button template with each subscriber's id as `flow_token`.
7. **`whatsapp-webhook`**: catches the Flow's completion message (`nfm_reply`) and sends the member a confirmation text.
8. **Admin UI** (`subscription_chef_page.dart`): kitchen summary bar now shows MORNING VEG / MORNING NON-VEG / EVENING VEG / EVENING NON-VEG / WHOLE-DAY VEG / WHOLE-DAY NON-VEG counts.

## Key IDs

| What | Value |
|---|---|
| WABA ID | `1764090017942543` |
| Phone number ID | `1258254477370342` |
| Flow ID | `1000968709654938` (name `tomorrow_meal_survey`) |
| Flow-button template name | `daily_meal_survey` |
