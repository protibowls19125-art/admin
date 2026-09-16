import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Android-only push notification service. Uses Supabase Realtime to listen
/// for new orders and shows native Android notifications via
/// flutter_local_notifications. Firebase is NOT used on Android.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  RealtimeChannel? _channel;
  bool _initialized = false;

  /// Order ids we've already notified about — prevents duplicate alerts
  /// when Realtime replays events or the subscription reconnects.
  final Set<String> _notifiedOrderIds = {};

  Future<void> _initNotifications() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    // Request POST_NOTIFICATIONS permission on Android 13+ (API 33+).
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Subscribe to Supabase Realtime on the orders table and fire a local
  /// notification whenever a new pending order appears.
  Future<void> registerForCurrentUser(String userId) async {
    try {
      await _initNotifications();

      // Tear down any existing subscription (e.g. session restore after
      // the user was already registered on a previous login).
      _channel?.unsubscribe();

      _channel = SupabaseService.client.channel('admin-new-orders');
      _channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (payload) {
              final rec = payload.newRecord;
              final id = rec['id']?.toString();
              final status = rec['status']?.toString();
              // Fire for any order that enters 'pending' (INSERT or UPDATE
              // from awaiting_payment → pending after payment verification).
              if (id != null &&
                  status == 'pending' &&
                  _notifiedOrderIds.add(id)) {
                final orderNum =
                    rec['order_number']?.toString() ??
                    (id.length > 8 ? id.substring(0, 8) : id);
                _showNotification(
                  'New Order Received',
                  'Order #$orderNum is ready to prepare',
                );
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'new_orders',
      'New Orders',
      channelDescription: 'Notifications for new incoming orders',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  /// Clean up the Realtime subscription on logout.
  Future<void> unregister(String userId) async {
    try {
      _channel?.unsubscribe();
      _channel = null;
      _notifiedOrderIds.clear();
    } catch (e) {
      debugPrint('Push unregister failed: $e');
    }
  }
}
