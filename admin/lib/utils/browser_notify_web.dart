import 'package:web/web.dart' as web;

/// Shows a browser `Notification` for an FCM message received while this tab
/// is open — foreground FCM messages don't auto-popup like background ones
/// do (see push_notification_service.dart). Permission is requested by
/// FirebaseMessaging.requestPermission() before this is ever called.
class BrowserNotifier {
  void notify(String title, String body) {
    if (web.Notification.permission != 'granted') return;
    web.Notification(title, web.NotificationOptions(body: body));
  }
}
