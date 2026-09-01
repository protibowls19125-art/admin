# Project Rules

## Architecture-First Rule

**MANDATORY**: Before scanning the codebase or making any changes, ALWAYS check if `ARCHITECTURE.md` exists in the project root (`c:\Final_protibowl\ARCHITECTURE.md`).

1. **READ FIRST**: Open and read `ARCHITECTURE.md` before doing any file searches or code scans.
2. **USE AS REFERENCE**: Use the architecture document to locate files, understand patterns, and find the right place to make changes.
3. **UPDATE AFTER CHANGES**: After completing any task, update the following sections in `ARCHITECTURE.md`:
   - **Changelog** (Section 16) — add a row with date, change description, and files modified.
   - **Any structural changes** — new pages, providers, edge functions, tables, etc.
   - **Any new patterns** discovered or established.

This saves significant time by avoiding redundant codebase scanning on every session.

## Code Conventions
- Flutter apps use **Provider** (ChangeNotifier) for state management.
- Routing via **go_router** in both apps.
- Edge functions are **Deno** (TypeScript) deployed via `npx supabase functions deploy`.
- Database migrations are `.sql` files run manually in the Supabase SQL Editor.
- Platform-specific code uses conditional imports (`*_web.dart`, `*_io.dart`, `*_stub.dart`).
- Price is always computed server-side in `razorpay-create-order` — never trust client-side totals.
