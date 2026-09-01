import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/razorpay_service.dart';

/// A purchasable Gold plan (rows of `gym_membership_plans`).
class GymMembershipPlan {
  final String id;
  final String name;
  final String tagline;
  final String description;
  final double price;
  final double compareAtPrice;
  final int durationDays;
  final double discountPercent;
  final List<String> features;
  final String badge;
  final bool freeDelivery;
  final bool deliveryEnabled;
  final int maxFreeOrdersPerDay;

  const GymMembershipPlan({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.price,
    required this.compareAtPrice,
    required this.durationDays,
    required this.discountPercent,
    required this.features,
    required this.badge,
    required this.freeDelivery,
    required this.deliveryEnabled,
    required this.maxFreeOrdersPerDay,
  });

  factory GymMembershipPlan.fromMap(Map<String, dynamic> m) => GymMembershipPlan(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        tagline: (m['tagline'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        compareAtPrice: (m['compare_at_price'] as num?)?.toDouble() ?? 0,
        durationDays: (m['duration_days'] as num?)?.toInt() ?? 0,
        discountPercent: (m['discount_percent'] as num?)?.toDouble() ?? 0,
        features: ((m['features'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        badge: (m['badge'] ?? '') as String,
        freeDelivery: m['free_delivery'] != false,
        deliveryEnabled: m['delivery_enabled'] != false,
        maxFreeOrdersPerDay: (m['max_free_orders_per_day'] as num?)?.toInt() ?? 0,
      );
}

/// Gold membership: gym-model-only paid membership giving a standing
/// discount + free delivery on regular gym orders. Deliberately separate
/// from SubscriptionProvider (Elite) — own tables, own auth state, no
/// meal-calendar/WhatsApp concepts, since those are Elite-only.
class GymMembershipProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _razorpay = RazorpayService();
  late final StreamSubscription<AuthState> _authSub;

  GymMembershipProvider() {
    // On web, session restore from localStorage after a fresh page load
    // (e.g. the reload triggered by switching browser tabs) can complete
    // slightly after Supabase.initialize() returns — a synchronous
    // isMemberLoggedIn check at that exact moment can miss it. Listening
    // here instead reacts once the session is actually known, so the
    // membership loads reliably instead of showing "no active membership".
    _authSub = _supabase.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        loadMemberData();
      } else {
        _myMembership = null;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  List<GymMembershipPlan> _plans = [];
  bool _loadingPlans = false;

  List<GymMembershipPlan> get plans => _plans;
  bool get loadingPlans => _loadingPlans;

  Future<void> fetchPlans() async {
    _loadingPlans = true;
    notifyListeners();
    try {
      final rows = await _supabase
          .from('gym_membership_plans')
          .select()
          .eq('active', true)
          .order('sort_order');
      _plans = (rows as List)
          .map((r) => GymMembershipPlan.fromMap((r as Map).cast()))
          .toList();
    } catch (_) {
      // keep whatever we had — page shows a retry
    }
    _loadingPlans = false;
    notifyListeners();
  }

  // ── Purchase flow (pay first, then set login details) ──────────────────────
  GymMembershipPayResult? _payment;
  GymMembershipPlan? _paidPlan;
  bool _paying = false;

  bool get paying => _paying;
  bool get hasPaid => _payment?.success == true;
  GymMembershipPlan? get paidPlan => _paidPlan;

  Future<String?> payForPlan(GymMembershipPlan plan) async {
    _paying = true;
    notifyListeners();
    final result = await _razorpay.payGymMembership(planId: plan.id);
    _paying = false;
    if (result.success) {
      _payment = result;
      _paidPlan = plan;
      notifyListeners();
      return null;
    }
    notifyListeners();
    return result.message;
  }

  /// Step 2: set login details. Verifies the payment, creates the account,
  /// and activates the membership in one call, then signs the member in.
  Future<String?> activate({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final p = _payment;
    if (p == null || !p.success) return 'Please complete the payment first';
    try {
      final res = await _supabase.functions.invoke(
        'gym-membership-activate',
        body: {
          'razorpay_order_id': p.razorpayOrderId,
          'razorpay_payment_id': p.razorpayPaymentId,
          'razorpay_signature': p.razorpaySignature,
          'name': name,
          'phone': phone,
          'email': email,
          'password': password,
        },
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] != true) {
        return data['error']?.toString() ?? 'Could not activate membership';
      }
      _payment = null; // consumed — prevents double submissions
      _paidPlan = null;
      final err = await memberLogin(email, password);
      return err;
    } catch (e) {
      return 'Could not activate membership: $e';
    }
  }

  // ── Member area (Supabase auth) ────────────────────────────────────────────
  Map<String, dynamic>? _myMembership; // joined row incl. plan
  bool _loadingMember = false;

  bool get isMemberLoggedIn => _supabase.auth.currentUser != null;
  String? get memberEmail => _supabase.auth.currentUser?.email;
  Map<String, dynamic>? get myMembership => _myMembership;
  bool get loadingMember => _loadingMember;

  Future<String?> memberLogin(String email, String password) async {
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final uid = res.user?.id;
      if (res.session == null || uid == null) {
        return 'Login failed — please try again';
      }
      await _loadMembershipFor(uid);
      return null;
    } catch (e) {
      final msg = e
          .toString()
          .replaceAll('AuthException: ', '')
          .replaceAll('Exception: ', '');
      return msg.contains('Invalid login')
          ? 'Incorrect email or password'
          : msg;
    }
  }

  Future<void> memberLogout() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {}
    _myMembership = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _fetchMembership(String userId) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _supabase
        .from('gym_memberships')
        .select('*, gym_membership_plans(name,discount_percent,duration_days)')
        .eq('auth_user_id', userId)
        .eq('status', 'active')
        .gte('end_date', today)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<void> _loadMembershipFor(String userId) async {
    _loadingMember = true;
    notifyListeners();
    try {
      _myMembership = await _fetchMembership(userId);
    } catch (e) {
      debugPrint('GymMembershipProvider._loadMembershipFor error: $e');
    }
    _loadingMember = false;
    notifyListeners();
  }

  Future<void> loadMemberData() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    await _loadMembershipFor(uid);
  }
}
