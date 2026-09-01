# 06 · Build & Deployment

Both apps are **Flutter web** builds (CanvasKit renderer) deployed to **GitHub Pages**. Each app
deploys to a **different repo** and is served from a **sub-path**, so the `--base-href` matters.

## Deploy targets

| App | Source | Served from path | Deployed to |
|-----|--------|------------------|-------------|
| Customer | `user/` | `/protibowl/` | `protibowl` repo, **gh-pages** branch |
| Admin | `admin/` | `/admin/` | admin repo, **main** branch (`/admin/`) |

`web/index.html` uses the `$FLUTTER_BASE_HREF` placeholder, replaced at build time by `--base-href`.
The committed `gh-pages-deploy/index.html` shows the result: `<base href="/protibowl/">` (customer).

## Build commands (PowerShell on Windows)

> Use the full Flutter/Dart `.bat` paths and `py` per the environment setup. Adjust the base-href
> per target.

**Customer app → `/protibowl/`:**
```powershell
cd user
flutter build web --release --base-href /protibowl/
# output: user/build/web/  → publish to protibowl repo's gh-pages branch
```

**Admin app → `/admin/`:**
```powershell
cd admin
flutter build web --release --base-href /admin/
# output: admin/build/web/ → publish to admin repo main under /admin/
```

## `gh-pages-deploy/`

A **staged, already-built** web bundle (the customer app, base href `/protibowl/`) kept at the repo
root for publishing. It is generated output (`main.dart.js`, `flutter_service_worker.js`,
`assets/`, `canvaskit/`) — **do not hand-edit**; rebuild from `user/` instead. It has its own
`.git` so it can be pushed to the Pages repo independently. The `admin/` folder likewise contains a
committed built bundle + its own `.git` pointing at the admin repo.

## Environment / secrets

- `.env` (gitignored) supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY` (and `CLERK_PUBLISHABLE_KEY` in
  the admin example). See `admin/.env.example`.
- On **web**, `.env` is absent by design — `SupabaseService` falls back to **hardcoded** URL + anon
  key, so web builds work without a bundled `.env`.

## Assets

- App logo: `assets/images/logo.png` in each app (declared in `pubspec.yaml`).
- Root has spare brand images: `logo.png`, `Logo_Secondary_Vertical-2048x2048.png`.
