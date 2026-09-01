// Non-web build (e.g. `flutter run` on desktop for local dev) — the
// admin/customer apps only ship as web, so this is a no-op stub to satisfy
// the conditional import in browser_notify.dart.
class BrowserNotifier {
  void notify(String title, String body) {}
}
