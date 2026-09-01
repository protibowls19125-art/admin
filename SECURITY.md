# Security Policy

## Supported Versions

We actively maintain and provide security updates for the following versions of the **Proti Bowls** platform (Customer Web App, Admin Control Panel, and Supabase Edge Functions):

| Version / Component | Supported          | Status |
| ------------------- | ------------------ | ------ |
| **v2.x (Latest)**   | :white_check_mark: | Active Production & Security Updates |
| **v1.x**           | :x:                | Deprecated — End of Life |
| **Edge Functions**  | :white_check_mark: | Continuously Deployed & Monitored |
| **Admin Panel**     | :white_check_mark: | Continuous Deployment (`admin.protibowls.com`) |

---

## Reporting a Vulnerability

The Proti Bowls team takes the security of our infrastructure, customer data, and payment pipelines seriously. If you believe you have discovered a security vulnerability, please report it responsibly by following the instructions below:

### 1. How to Report
- **Email**: Send your findings directly to our security and engineering team at **`security@protibowls.com`** (or **`support@protibowls.com`**).
- **Subject**: `[SECURITY VULNERABILITY] Proti Bowls - <Short Description>`
- **Details to Include**:
  - Description and location of the vulnerability (URL, edge function, API endpoint, or UI component).
  - Step-by-step reproduction steps or Proof of Concept (PoC).
  - Potential impact and severity assessment.
  - Any proposed mitigations or patches if available.

> **Note**: Please do **not** open public GitHub issues or disclose vulnerabilities publicly before we have had the opportunity to investigate and deploy a fix.

---

## Response Timeline & What to Expect

When you submit a vulnerability report:

1. **Initial Acknowledgment**: You will receive an initial response within **24 to 48 hours** confirming receipt of your report.
2. **Triage & Assessment**: Our engineering team will validate and reproduce the reported issue within **3 business days** and notify you of the severity status.
3. **Remediation & Patching**:
   - **Critical / High Severity**: Patched and deployed to production within **24–72 hours**.
   - **Medium / Low Severity**: Addressed in the subsequent deployment sprint.
4. **Resolution Notice**: You will receive confirmation once the fix is live in production.
5. **Responsible Disclosure**: We request that you maintain confidentiality until the fix has been verified and deployed.

---

## Security Architecture & Built-in Controls

Proti Bowls implements multiple layers of defense to safeguard customers, staff, and transactional data:

### 1. Strict Server-Side Pricing & Payments
- **Zero Client Trust**: All order prices and subscription billing amounts are computed server-side directly from the database within isolated Supabase Edge Functions (`razorpay-create-order`, `subscription-create-order`). Client-provided totals are never trusted.
- **Cryptographic Signature Verification**: All Razorpay payment captures, callbacks, and webhooks are verified via HMAC SHA-256 signatures before fulfilling any orders or updating member statuses.

### 2. Zero-Trust Database & Row Level Security (RLS)
- **Granular Access Control**: Row Level Security (RLS) is enabled on all PostgreSQL tables.
- **Anon Key Isolation**: The public anonymous key can only perform `SELECT` queries on active menu items and active plans. Customer PII, order history, financial records, and delivery logs require authenticated staff tokens or service-role edge execution.

### 3. Webhook Authentication & Rate Limiting
- **Meta / WhatsApp Webhooks**: Protected with secure verify tokens (`WHATSAPP_VERIFY_TOKEN`) and app secret proofs.
- **Google Sheets & Cron Endpoints**: Guarded with shared cryptographic secrets (`x-cron-secret`, `SHEETS_WEBHOOK_SECRET`).
- **IP Rate Limiting**: Abuse prevention mechanisms restrict high-frequency API calls on sensitive authentication and ordering endpoints.

---

Thank you for helping us keep Proti Bowls and our customers safe!
