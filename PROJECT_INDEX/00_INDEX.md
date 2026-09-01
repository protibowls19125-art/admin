# 📖 PROJECT INDEX — Master Guide

> **Purpose:** This folder is the "textbook" for the project. An AI agent (or new developer)
> should read these files **instead of** scanning the entire codebase. Each file documents a
> slice of the system: what it is, where it lives, what each component does, and how the pieces
> connect.
>
> **Keep it current:** When you add/rename/delete a component, update the matching file here.

---

## What is this project?

**M·PROTI Dining** — a contactless restaurant ordering & billing system built with **Flutter (web)**
and a **Supabase** backend. It ships as **two separate Flutter apps** plus serverless edge functions.

| App | Folder | Who uses it | Deployed to |
|-----|--------|-------------|-------------|
| **Customer app** | `user/` | Diners — browse menu, order, track | GitHub Pages → `protibowl` repo (`/protibowl/`) |
| **Admin app** | `admin/` | Staff — dashboard, KDS, menu mgmt, analytics | GitHub Pages → admin repo (`/admin/`) |
| **Backend** | `supabase/` + `*.sql` | Both apps | Supabase project `pahanghosyepfuwcfexg` |

Both apps talk to the **same Supabase project** (shared DB tables) and also use **local browser
storage** (`shared_preferences`) for offline-tolerant order syncing.

---

## How to navigate this index

| File | Read it when you need to… |
|------|---------------------------|
| [01_ARCHITECTURE.md](01_ARCHITECTURE.md) | Understand the big picture, data flow, and tech stack |
| [02_USER_APP.md](02_USER_APP.md) | Work on the **customer** app (`user/`) |
| [03_ADMIN_APP.md](03_ADMIN_APP.md) | Work on the **admin/staff** app (`admin/`) |
| [04_BACKEND.md](04_BACKEND.md) | Touch the database, RPCs, migrations, or edge functions |
| [05_DATA_MODELS.md](05_DATA_MODELS.md) | Understand the data shapes (`Order`, `MenuItem`, etc.) |
| [06_DEPLOYMENT.md](06_DEPLOYMENT.md) | Build & deploy either app |
| [07_CONVENTIONS.md](07_CONVENTIONS.md) | Match existing patterns, naming, and gotchas |

---

## Tech stack (both apps)

- **Flutter** (Dart SDK `^3.5.0`), targeting **web** (CanvasKit)
- **State management:** `provider` (`ChangeNotifier`)
- **Routing:** `go_router`
- **Backend SDK:** `supabase_flutter`
- **Local storage:** `shared_preferences`
- **Env vars:** `flutter_dotenv` (`.env`, with hardcoded fallbacks for web)
- **Fonts:** `google_fonts` · **Charts:** `fl_chart` (admin only) · **Images:** `cached_network_image`, `image_picker` (admin only)

## Repo layout (top level)

```
Billing/
├── user/                 # Customer Flutter app  → see 02_USER_APP.md
├── admin/                # Admin Flutter app     → see 03_ADMIN_APP.md
├── supabase/functions/   # Deno edge functions   → see 04_BACKEND.md
├── *.sql                 # DB schema & migrations → see 04_BACKEND.md
├── gh-pages-deploy/      # Built web bundle staged for GitHub Pages deploy
├── design/               # Design references (Stitch mockups)
├── *.md                  # Historical setup/implementation notes (see below)
└── PROJECT_INDEX/        # ← you are here
```

> **Note on root `*.md` files** (SETUP_GUIDE, IMPLEMENTATION_*, QUICK_*, ORDER_FLOW_COMPLETE, etc.):
> these are **historical, human-written notes** from earlier build phases. They may be stale.
> Treat **this PROJECT_INDEX as the source of truth**; use the root docs only for extra context.
