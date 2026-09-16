import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/supabase_service.dart';
import 'services/shared_orders_service.dart';
import 'providers/auth_provider.dart';
import 'providers/admin_menu_provider.dart';
import 'providers/admin_order_provider.dart';
import 'providers/admin_orders_provider.dart';
import 'providers/customer_info_provider.dart';
import 'providers/subscription_admin_provider.dart';
import 'providers/gym_membership_admin_provider.dart';
import 'providers/staff_admin_provider.dart';
import 'theme/app_theme.dart';
import 'router.dart';

// Firebase imports — only used on web. On Android, the push notification
// service uses Supabase Realtime + flutter_local_notifications instead.
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// Admin app entry point
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Dotenv removed — credentials are hardcoded in SupabaseService.
  // flutter_dotenv caused 403 errors on web hosting (Apache blocks dotfiles).
  await SupabaseService.initialize();
  await SharedOrdersService().init();

  // Firebase is web-only. On Android, notifications are handled natively via
  // Supabase Realtime + flutter_local_notifications (see
  // push_notification_service_io.dart). There is no google-services.json for
  // Android, so Firebase.initializeApp would fail on non-web platforms.
  if (kIsWeb) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  }

  runApp(const MPROTIDiningAdminApp());
}

class MPROTIDiningAdminApp extends StatelessWidget {
  const MPROTIDiningAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: adminAuth),
        ChangeNotifierProvider(create: (_) => AdminMenuProvider()),
        ChangeNotifierProvider(create: (_) => AdminOrderProvider()),
        ChangeNotifierProvider(create: (_) => AdminOrdersProvider()),
        ChangeNotifierProvider(create: (_) => CustomerInfoProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionAdminProvider()),
        ChangeNotifierProvider(create: (_) => GymMembershipAdminProvider()),
        ChangeNotifierProvider(create: (_) => StaffAdminProvider()),
      ],
      child: MaterialApp.router(
        title: 'Proti Bowls Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        routerConfig: router,
      ),
    );
  }
}
