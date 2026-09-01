Subject: Manual Integrity review requested — WhatsApp Flow publish blocked (139000 / 4233020)

Hello,

I'm requesting a manual review from the WhatsApp Integrity team. I was previously advised via Business Help Center chat support to file this ticket after adding a payment method did not resolve the issue.

Issue: Publishing a WhatsApp Flow fails every attempt with:

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
- Latest Trace ID: AfH785C9GCskJ5KxEWblQr4

I have already added a valid payment method and confirmed active WhatsApp Business messaging billing on this exact account:
- Account ID on invoice: 1764090017942543 (matches WABA ID above)
- Service: Business messaging (SAC 998319)
- Document date: 3 Aug 2026
- Reference number: GTHAHYMTQ2
- Transaction ID: 28157060373983090-28227058116983312

The error is unchanged after this payment was processed (retried and reproduced today with a fresh trace ID: AfH785C9GCskJ5KxEWblQr4), which suggests the payment method was not the actual cause — please treat this as a new-account manual integrity review rather than a billing issue.

The Flow itself is fully built and passes validation (0 validation errors), and the data endpoint's health check succeeds — the block only occurs at the /publish step.

Please proceed with the manual integrity review and notify me of the outcome via my Support Inbox or email.

Thank you.
