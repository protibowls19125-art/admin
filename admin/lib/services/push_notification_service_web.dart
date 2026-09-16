import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'supabase_service.dart';
import '../utils/browser_notify.dart';

/// Web-only FCM push notification service. Registers this browser for
/// Firebase Cloud Messaging and re-shows foreground messages as browser
/// Notifications (background messages auto-popup via the service worker).
const String _vapidKey =
    'BIw4wFoRl5zrER8j7K_Mr6xvr_cmp3PKshT6ihxE0O9GbHVTvjVpHyiQF-W3LVm85v6G_0ivXFI8OheXIQTZxSs';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final BrowserNotifier _notifier = BrowserNotifier();
  bool _initialized = false;

  /// Call once after login (and once on session restore) with the signed-in
  /// user's id — ties this browser's token to that admin/staff account.
  Future<void> registerForCurrentUser(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      if (!_initialized) {
        _initialized = true;
        FirebaseMessaging.onMessage.listen((msg) {
          final n = msg.notification;
          if (n == null) return;
          _notifier.notify(n.title ?? 'New order received', n.body ?? '');
        });
        messaging.onTokenRefresh.listen((token) => _saveToken(userId, token));
      }

      final token = await messaging.getToken(vapidKey: _vapidKey);
      if (token != null) await _saveToken(userId, token);
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _saveToken(String userId, String token) async {
    try {
      await SupabaseService.client.from('device_tokens').upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': 'web',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,fcm_token');
    } catch (e) {
      debugPrint('Could not save push token: $e');
    }
  }

  /// Best-effort cleanup on logout — leaves other devices/sessions alone.
  Future<void> unregister(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken(vapidKey: _vapidKey);
      if (token != null) {
        await SupabaseService.client
            .from('device_tokens')
            .delete()
            .eq('user_id', userId)
            .eq('fcm_token', token);
      }
    } catch (e) {
      debugPrint('Push unregister failed: $e');
    }
  }
}
