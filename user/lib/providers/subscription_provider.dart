import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/razorpay_service.dart';

/// A purchasable meal-plan (rows of `subscription_plans`).
class SubscriptionPlan {
  final String id;
  final String name;
  final String tagline;
  final String description;
  final double price;

  /// The "normal" price for the same meals bought individually — set by the
  /// admin. When higher than [price], the app shows a strikethrough anchor
  /// and an auto-computed "SAVE X%" pill.
  final double compareAtPrice;
  final int durationDays;
  final int mealsPerDay;
  final List<String> features;
  final String badge;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.price,
    required this.compareAtPrice,
    required this.durationDays,
    required this.mealsPerDay,
    required this.features,
    required this.badge,
  });

  factory SubscriptionPlan.fromMap(Map<String, dynamic> m) => SubscriptionPlan(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        tagline: (m['tagline'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        compareAtPrice: (m['compare_at_price'] as num?)?.toDouble() ?? 0,
        durationDays: (m['duration_days'] as num?)?.toInt() ?? 0,
        mealsPerDay: (m['meals_per_day'] as num?)?.toInt() ?? 1,
        features: ((m['features'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        badge: (m['badge'] ?? '') as String,
      );

  /// ₹ per meal — used for value framing ("₹166 per meal").
  double get perMeal =>
      durationDays * mealsPerDay == 0 ? 0 : price / (durationDays * mealsPerDay);

  /// Whole-number % saved vs [compareAtPrice]; 0 when no anchor is set.
  int get discountPercent => compareAtPrice > price && compareAtPrice > 0
      ? (((compareAtPrice - price) / compareAtPrice) * 100).round()
      : 0;
}

/// Promotional banner (rows of `subscription_banners`).
class PromoBanner {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String ctaText;
  final String ctaRoute;
  final String bgColorHex;

  const PromoBanner({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.ctaText,
    required this.ctaRoute,
    required this.bgColorHex,
  });

  factory PromoBanner.fromMap(Map<String, dynamic> m) => PromoBanner(
        title: (m['title'] ?? '') as String,
        subtitle: (m['subtitle'] ?? '') as String,
        imageUrl: (m['image_url'] ?? '') as String,
        ctaText: (m['cta_text'] ?? 'Explore') as String,
        ctaRoute: (m['cta_route'] ?? '/subscribe') as String,
        bgColorHex: (m['bg_color'] ?? '#1B3A2D') as String,
      );
}

/// One day in the member's meal calendar (rows of `meal_confirmations`).
class MealDay {
  final String id;
  final DateTime date;
  final String status;

  const MealDay({required this.id, required this.date, required this.status});
}

/// Everything subscription-related in the customer app:
/// the public sales data (plans, banners), the payment → onboarding flow,
/// and the logged-in member's own subscription + meal calendar.
class SubscriptionProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _razorpay = RazorpayService();
  late final StreamSubscription<AuthState> _authSub;

  SubscriptionProvider() {
    // On web, session restore from localStorage after a fresh page load can
    // complete slightly after Supabase.initialize() returns — a synchronous
    // isMemberLoggedIn check at that exact moment can miss it, leaving the
    // member page stuck on "no active membership" even though they're really
    // still logged in. Listening here instead reacts once the session is
    // actually known (same fix already applied to GymMembershipProvider).
    _authSub = _supabase.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        loadMemberData();
      } else {
        _mySubscription = null;
        _mealDays = [];
        _todayDish = null;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  // ── Public sales data ──────────────────────────────────────────────────────
  List<SubscriptionPlan> _plans = [];
  List<PromoBanner> _banners = [];
  bool _loadingPlans = false;
  String _enquiryFormUrl = '';

  List<SubscriptionPlan> get plans => _plans;
  List<PromoBanner> get banners => _banners;
  bool get loadingPlans => _loadingPlans;
  String get enquiryFormUrl => _enquiryFormUrl;

  Future<void> fetchPlans() async {
    _loadingPlans = true;
    notifyListeners();
    try {
      final rows = await _supabase
          .from('subscription_plans')
          .select()
          .eq('active', true)
          .order('sort_order');
      _plans = (rows as List)
          .map((r) => SubscriptionPlan.fromMap((r as Map).cast()))
          .toList();
    } catch (_) {
      // keep whatever we had — sales page shows a retry
    }
    // Also fetch the Google Form enquiry URL from app_config.
    try {
      final cfgRow = await _supabase
          .from('app_config')
          .select('value')
          .eq('key', 'subscription_enquiry_form_url')
          .maybeSingle();
      debugPrint('[SubscriptionProvider] enquiry cfgRow = $cfgRow');
      if (cfgRow != null) {
        final rawValue = cfgRow['value'];
        debugPrint('[SubscriptionProvider] rawValue type=${rawValue.runtimeType} val=$rawValue');
        if (rawValue is String) {
          _enquiryFormUrl = rawValue.replaceAll('"', '').trim();
        } else if (rawValue is Map) {
          // If JSONB returned a map, try common keys.
          _enquiryFormUrl = (rawValue['url'] ?? rawValue['value'] ?? '').toString().trim();
        } else {
          _enquiryFormUrl = rawValue?.toString().replaceAll('"', '').trim() ?? '';
        }
      }
      debugPrint('[SubscriptionProvider] final enquiryFormUrl = $_enquiryFormUrl');
    } catch (e) {
      debugPrint('[SubscriptionProvider] enquiry URL fetch error: $e');
    }
    _loadingPlans = false;
    notifyListeners();
  }

  Future<void> fetchBanners() async {
    try {
      final rows = await _supabase
          .from('subscription_banners')
          .select()
          .eq('active', true)
          .order('sort_order');
      _banners = (rows as List)
          .map((r) => PromoBanner.fromMap((r as Map).cast()))
          .toList();
      notifyListeners();
    } catch (_) {/* banners are decorative — fail silently */}
  }

  // ── Purchase flow (pay first, then details) ────────────────────────────────
  SubscriptionPayResult? _payment;
  SubscriptionPlan? _paidPlan;
  bool _paying = false;

  bool get paying => _paying;
  bool get hasPaid => _payment?.success == true;
  SubscriptionPlan? get paidPlan => _paidPlan;

  /// Step 1: pay for the plan. On success the onboarding form is unlocked.
  Future<String?> payForPlan(SubscriptionPlan plan) async {
    _paying = true;
    notifyListeners();
    final result = await _razorpay.paySubscription(planId: plan.id);
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

  /// Step 2: submit the onboarding answers. Returns null on success.
  Future<String?> submitDetails({
    required String name,
    required String phone,
    required String email,
    required String foodPreference,
    required String healthGoal,
    required String healthNotes,
    required Map<String, String> address,
  }) async {
    final p = _payment;
    if (p == null || !p.success) return 'Please complete the payment first';
    try {
      final res = await _supabase.functions.invoke(
        'subscription-submit-details',
        body: {
          'razorpay_order_id': p.razorpayOrderId,
          'razorpay_payment_id': p.razorpayPaymentId,
          'customer_name': name,
          'phone': phone,
          'email': email,
          'food_preference': foodPreference,
          'health_goal': healthGoal,
          'health_notes': healthNotes,
          'delivery_address': address,
        },
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] == true) {
        _payment = null; // consumed — prevents double submissions
        _paidPlan = null;
        notifyListeners();
        return null;
      }
      return data['error']?.toString() ?? 'Could not save your details';
    } catch (e) {
      return 'Could not save your details: $e';
    }
  }

  // ── Member area (Supabase auth) ────────────────────────────────────────────
  Map<String, dynamic>? _mySubscription; // joined row incl. plan
  List<MealDay> _mealDays = [];
  Map<String, dynamic>? _todayDish; // scheduled dish for my preference
  bool _loadingMember = false;

  bool get isMemberLoggedIn => _supabase.auth.currentUser != null;
  String? get memberEmail => _supabase.auth.currentUser?.email;
  Map<String, dynamic>? get mySubscription => _mySubscription;
  List<MealDay> get mealDays => _mealDays;

  /// Today's scheduled dish for the member's food preference
  /// (name / description / image_url / kcal) — null if not planned yet.
  Map<String, dynamic>? get todayDish => _todayDish;
  bool get loadingMember => _loadingMember;

  MealDay? get todayMeal {
    final t = DateTime.now();
    for (final d in _mealDays) {
      if (d.date.year == t.year && d.date.month == t.month && d.date.day == t.day) {
        return d;
      }
    }
    return null;
  }

  /// Returns null on success, else an error message.
  Future<String?> memberLogin(String email, String password) async {
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.session == null) return 'Login failed — please try again';
      await loadMemberData();
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
    _mySubscription = null;
    _mealDays = [];
    notifyListeners();
  }

  Future<void> loadMemberData() async {
    if (!isMemberLoggedIn) return;
    _loadingMember = true;
    notifyListeners();
    try {
      Map<String, dynamic>? sub;
      try {
        // Preferred: includes price/compare_at_price for the "Total Savings"
        // figure on the premium card.
        sub = await _supabase
            .from('subscriptions')
            .select(
                '*, subscription_plans(name,meals_per_day,duration_days,price,compare_at_price)')
            .eq('auth_user_id', _supabase.auth.currentUser!.id)
            .inFilter('status', ['active', 'paused'])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      } catch (_) {
        // Falls back if compare_at_price/price aren't on this DB yet (older
        // schema) — the member's plan must still load even without those
        // two columns; savings just won't show.
        sub = await _supabase
            .from('subscriptions')
            .select('*, subscription_plans(name,meals_per_day,duration_days)')
            .eq('auth_user_id', _supabase.auth.currentUser!.id)
            .inFilter('status', ['active', 'paused'])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }
      _mySubscription = sub;
      if (sub != null) {
        final today = DateTime.now();
        final from =
            DateTime(today.year, today.month, today.day).toIso8601String();
        final rows = await _supabase
            .from('meal_confirmations')
            .select(
                'id,meal_date,status,meal_id,subscription_meals(name,description,image_url,kcal)')
            .eq('subscription_id', sub['id'])
            .gte('meal_date', from.substring(0, 10))
            .order('meal_date');
        _mealDays = (rows as List).map((r) {
          final m = (r as Map).cast<String, dynamic>();
          return MealDay(
            id: m['id'] as String,
            date: DateTime.parse(m['meal_date'] as String),
            status: (m['status'] ?? 'awaiting') as String,
          );
        }).toList();
        // Today's dish — whichever specific dish the manager assigned this
        // member (individually or via their group), read straight off that
        // row rather than re-derived from the preference-wide daily menu.
        final todayStr = from.substring(0, 10);
        final todayRow =
            (rows).cast<Map>().where((r) => r['meal_date'] == todayStr);
        _todayDish = todayRow.isEmpty
            ? null
            : (todayRow.first['subscription_meals'] as Map?)
                ?.cast<String, dynamic>();
      } else {
        _mealDays = [];
        _todayDish = null;
      }
    } catch (_) {/* shown as empty state */}
    _loadingMember = false;
    notifyListeners();
  }

  /// Confirm or skip TODAY's meal from inside the app — same-day cycle,
  /// matching the WhatsApp reminder/webhook and the manager's manual
  /// override. Goes through the `confirm_meal` RPC (SECURITY DEFINER — own
  /// row only), which also enforces the 1 PM in-app cutoff server-side.
  Future<String?> confirmToday(bool confirm) async {
    try {
      final today = DateTime.now();
      final dateStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      await _supabase.rpc('confirm_meal', params: {
        'p_meal_date': dateStr,
        'p_confirm': confirm,
      });
      await loadMemberData();
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('kitchen')) {
        return 'Today\'s meal is already with the kitchen and can\'t be changed here';
      }
      if (msg.contains('1 PM')) {
        return 'The app confirm window has closed for today (1 PM)';
      }
      return 'Could not update — please try again';
    }
  }
}
