import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/supabase_service.dart';
import 'services/local_storage_service.dart';
import 'services/shared_orders_service.dart';
import 'services/guest_customer_tracking_service.dart';
import 'services/service_hours_service.dart';
import 'providers/menu_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/order_provider.dart';
import 'providers/customer_info_provider.dart';
import 'providers/subscription_provider.dart';
import 'providers/gym_membership_provider.dart';
import 'providers/theme_config_provider.dart';
import 'theme/bauhaus_theme.dart';
import 'router.dart';

/// User/Customer app entry point
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dotenv removed — credentials are hardcoded in SupabaseService.
  // flutter_dotenv caused 403 errors on web hosting (Apache blocks dotfiles).
  await SupabaseService.initialize();
  await LocalStorageService().init();
  await SharedOrdersService().init();
  await GuestCustomerTrackingService().init();
  // Not awaited: a slow/flaky connection to Supabase would otherwise block
  // the entire splash screen on this single best-effort query. It already
  // fails open (isAvailable() defaults to "available" until this resolves),
  // so it's safe to populate in the background after the app is on screen.
  ServiceHoursService().load();

  runApp(const MPROTIDiningUserApp());
}

class MPROTIDiningUserApp extends StatelessWidget {
  const MPROTIDiningUserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CustomerInfoProvider()),
        ChangeNotifierProvider(create: (_) => MenuProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
        ChangeNotifierProvider(create: (_) => GymMembershipProvider()),
        ChangeNotifierProvider(create: (_) => ThemeConfigProvider()..fetch()),
      ],
      child: MaterialApp.router(
        title: 'Proti Bowls',
        debugShowCheckedModeBanner: false,
        theme: BauhausTheme.theme,
        routerConfig: router,
      ),
    );
  }
}
