import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const String _url = 'https://esiatypehvnyeemvnzbl.supabase.co';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVzaWF0eXBlaHZueWVlbXZuemJsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUzMzcxNjEsImV4cCI6MjEwMDkxMzE2MX0.qHC3Nn6E0A5sP0xHK9JPhxTrmD8Zihlft3yM5VB8ef0';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _url,
      publishableKey: _anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;

  static const String tableMenuItems = 'menu_items';
  static const String tableOrders = 'orders';
  static const String tableOrderItems = 'order_items';
  static const String tableProfiles = 'profiles';
  static const String tableGuestCustomers = 'guest_customers';
  static const String tableAnalyticsEvents = 'analytics_events';
  static const String bucketMenuImages = 'menu-images';
}
