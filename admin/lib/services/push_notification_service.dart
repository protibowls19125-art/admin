// Conditional import: default → Android (Supabase Realtime + local
// notifications); override → web (Firebase Cloud Messaging).
// Follows the same pattern as browser_notify.dart and new_order_sound.dart.
export 'push_notification_service_io.dart'
    if (dart.library.js_interop) 'push_notification_service_web.dart';
