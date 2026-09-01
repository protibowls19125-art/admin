Business use case:
Proti Bowls is a meal-subscription service. This WhatsApp Business Account sends
delivery-related utility messages to subscribed members only (daily meal
confirmation, food preference collection, order status). The Flow below is a
short in-chat form used to collect a member's next-day meal preference —
no marketing content, no unsolicited messaging.

Issue:
Publishing a WhatsApp Flow fails every attempt with:

    {
      "error": {
        "message": "Blocked by Integrity",
        "type": "OAuthException",
        "code": 139000,
        "error_subcode": 4233020,
        "is_transient": false,
        "error_user_title": "Flow publishing failed",
        "error_user_msg": "Integrity requirements not met."
      }
    }

Details:
- WABA ID: 1764090017942543
- Flow ID: 1000968709654938 (tomorrow_meal_survey)
- Phone Number ID: 1258254477370342
- Business name: Proti Bowls
- Error Code: 139000 (subcode 4233020)

Steps already taken:
- Added and confirmed a valid payment method on this account (Account ID
  1764090017942543, Service: Business messaging SAC 998319, Document date
  3 Aug 2026, Reference GTHAHYMTQ2). The error is unchanged after payment
  was processed and confirmed active.
- Filed a manual Integrity review request via Business Help Center chat
  support; still awaiting a response as of this submission.
- Flow passes validation with 0 errors, and its data endpoint's health
  check reports AVAILABLE for FLOW, WABA, BUSINESS, and APP entities. The
  block occurs only at the /publish step.

This appears to be a new-account Integrity hold rather than a billing or
Flow-content issue. Requesting manual review and reinstatement of Flow
publishing for this account.
