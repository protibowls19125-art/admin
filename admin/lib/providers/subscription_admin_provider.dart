import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../services/supabase_service.dart';

/// State + actions for the whole subscription section of the admin panel:
/// approvals, members, the subscription KDS, delivery assignment, and the
/// no-code editors (plans / banners / WhatsApp templates / credentials).
///
/// Privileged actions (create login, remove member…) go through the
/// `admin-manage-member` edge function, which re-verifies the caller's role
/// server-side — the client role check is only for UX.
class SubscriptionAdminProvider extends ChangeNotifier {
  final _client = SupabaseService.client;

  bool isLoading = false;
  String? error;

  List<Map<String, dynamic>> pending = [];
  List<Map<String, dynamic>> members = [];
  List<Map<String, dynamic>> plans = [];
  List<Map<String, dynamic>> banners = [];
  List<Map<String, dynamic>> templates = [];
  List<Map<String, dynamic>> agents = [];
  List<Map<String, dynamic>> meals = []; // meal_confirmations for [kdsDate]
  List<Map<String, dynamic>> mealLibrary = []; // subscription_meals catalog
  List<Map<String, dynamic>> foodPreferences = []; // admin-editable veg/non-veg/etc.
  List<Map<String, dynamic>> groups = []; // member_groups
  /// Daily menu for [kdsDate] / the schedule editor: preference → that day's
  /// scheduled dish OPTIONS (with joined meal). Kept in sync by fetchSchedule.
  Map<String, List<Map<String, dynamic>>> scheduleByPref = {};

  /// The date the kitchen is looking at (defaults to today).
  DateTime kdsDate = DateTime.now();

  Timer? _refreshTimer;

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Fetchers ───────────────────────────────────────────────────────────────

  Future<void> fetchSubscriptions() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final rows = await _client
          .from('subscriptions')
          .select('*, subscription_plans(name,duration_days,meals_per_day,price)')
          .inFilter('status',
              ['pending_approval', 'active', 'paused', 'payment_received'])
          .order('created_at', ascending: false);
      final all = (rows as List).cast<Map<String, dynamic>>();
      pending = all
          .where((s) =>
              s['status'] == 'pending_approval' ||
              s['status'] == 'payment_received')
          .toList();
      members = all
          .where((s) => s['status'] == 'active' || s['status'] == 'paused')
          .toList();
    } catch (e) {
      error = 'Could not load subscriptions: $e';
    }
    isLoading = false;
    notifyListeners();
  }

  /// Meal ids in the Subscription KDS's working queue on the previous fetch
  /// — same new-arrival diffing AdminOrdersProvider does for the main KDS.
  Set<String> _knownKitchenMealIds = {};
  bool _mealsBaselineSet = false;
  bool _isAutoPushing = false;

  static bool _isTimeDue(String deliveryTimeStr) {
    final str = deliveryTimeStr.trim();
    if (str.isEmpty) return false;
    if (str.startsWith('{')) {
      try {
        final map = jsonDecode(str) as Map;
        for (final v in map.values) {
          if (v != null && _isTimeDue(v.toString())) return true;
        }
        return false;
      } catch (_) {}
    }
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*([AP]M)?$', caseSensitive: false)
        .firstMatch(str);
    if (m == null) return false;
    var hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    final period = m.group(3)?.toUpperCase();
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;

    final now = DateTime.now();
    return (now.hour > hour) || (now.hour == hour && now.minute >= minute);
  }

  /// Helper to extract delivery time for a specific dish index (0, 1, 2...)
  String getDishDeliveryTime(dynamic rawDeliveryTime, int dishIndex) {
    if (rawDeliveryTime == null) return '';
    final str = rawDeliveryTime.toString().trim();
    if (str.startsWith('{')) {
      try {
        final map = jsonDecode(str) as Map;
        return (map[dishIndex.toString()] ?? map[dishIndex] ?? '').toString();
      } catch (_) {}
    }
    if (dishIndex == 0) return str;
    return '';
  }

  /// Called when a meal newly enters the kitchen queue (freshly pushed from
  /// Today's Meal, or freshly confirmed/preparing/prepared) — mirrors
  /// AdminOrdersProvider.onNewOrder; subscription_chef_page.dart uses it for
  /// the same kind of ringtone alert the main KDS has.
  VoidCallback? onNewMeal;

  Future<void> fetchMeals() async {
    try {
      final rows = await _client
          .from('meal_confirmations')
          .select(
              '*, meal_id, subscription_meals(name,description,image_url,kcal), subscriptions(customer_name,phone,food_preference,morning_preference,evening_preference,health_goal,health_notes,delivery_address,member_code,is_test, subscription_plans(name,meals_per_day)), delivery_agents(name)')
          .eq('meal_date', _d(kdsDate))
          .order('priority', ascending: false)
          .order('created_at');
      final fetchedMeals = (rows as List).cast<Map<String, dynamic>>();

      // Resolve manual entries
      Map<String, Map<String, dynamic>> manualMap = {};
      try {
        final mRows = await _client
            .from('manual_subscription_entries')
            .select('id, customer_name, phone, plan_name, notes, amount')
            .order('created_at', ascending: false)
            .limit(100);
        final mList = (mRows as List).cast<Map<String, dynamic>>();
        for (final mr in mList) {
          manualMap[mr['id'].toString()] = mr;
        }

        // Positional / name fallback for older entries missing manual_entry_id
        final unlinkedManuals = mList.toList();
        int unlinkedIdx = 0;
        for (var m in fetchedMeals) {
          if (m['subscription_id'] == null) {
            final mId = m['manual_entry_id']?.toString();
            if (mId == null || !manualMap.containsKey(mId)) {
              // Try match by reply_text if it holds customer name
              final reply = (m['reply_text'] as String?)?.trim() ?? '';
              final match = unlinkedManuals.firstWhere(
                (mr) =>
                    reply.isNotEmpty &&
                    mr['customer_name']?.toString().toLowerCase() ==
                        reply.toLowerCase(),
                orElse: () => unlinkedIdx < unlinkedManuals.length
                    ? unlinkedManuals[unlinkedIdx++]
                    : const {},
              );
              if (match.isNotEmpty) {
                manualMap[m['id'].toString()] = match;
              }
            }
          }
        }
      } catch (_) {}

      meals = fetchedMeals.map((m) {
        final mEntryId = m['manual_entry_id']?.toString();
        if (mEntryId != null && manualMap.containsKey(mEntryId)) {
          return {
            ...m,
            'manual_subscription_entries': manualMap[mEntryId],
          };
        }
        if (manualMap.containsKey(m['id'].toString())) {
          return {
            ...m,
            'manual_subscription_entries': manualMap[m['id'].toString()],
          };
        }
        return m;
      }).toList();

      // Sort meals: P1 (Highest) -> P2 (Moderate) -> P3 (Low)
      meals.sort((a, b) {
        int rank(dynamic p) {
          final val = (p as num?)?.toInt() ?? 2;
          if (val == 1) return 1;
          if (val == 2) return 2;
          return 3;
        }
        final rA = rank(a['priority']);
        final rB = rank(b['priority']);
        if (rA != rB) return rA.compareTo(rB);
        final cA = a['created_at']?.toString() ?? '';
        final cB = b['created_at']?.toString() ?? '';
        return cA.compareTo(cB);
      });

      error = null;

      // Auto-push confirmed meals that have reached their scheduled time
      if (_d(kdsDate) == _d(DateTime.now()) && !_isAutoPushing) {
        final dueIds = meals
            .where((m) =>
                m['status'] == 'confirmed' &&
                m['pushed_to_kitchen'] != true &&
                _isTimeDue((m['delivery_time'] ?? '').toString()))
            .map((m) => m['id']?.toString())
            .whereType<String>()
            .toList();
        if (dueIds.isNotEmpty) {
          _isAutoPushing = true;
          try {
            await pushToKitchen(dueIds);
            return; // pushToKitchen already refetches meals
          } finally {
            _isAutoPushing = false;
          }
        }
      }

      // Same "active" queue subscription_chef_page.dart computes: confirmed
      // rows only once pushed to kitchen, plus anything already preparing/
      // prepared — a fresh id in that set is a genuinely new arrival, not
      // just a status edit on one the chef already saw.
      final activeIds = meals
          .where((m) =>
              ['confirmed', 'preparing', 'prepared'].contains(m['status']) &&
              (m['status'] != 'confirmed' || m['pushed_to_kitchen'] == true))
          .map((m) => m['id']?.toString())
          .whereType<String>()
          .toSet();
      final hasNewMeal =
          activeIds.any((id) => !_knownKitchenMealIds.contains(id));
      _knownKitchenMealIds = activeIds;
      if (_mealsBaselineSet && hasNewMeal) onNewMeal?.call();
      _mealsBaselineSet = true;
    } catch (e) {
      error = 'Could not load meals: $e';
    }
    notifyListeners();
  }

  /// Survey responses for the Survey Responses page, for an arbitrary
  /// [date] — independent of [kdsDate]/[meals], which the Kitchen Display
  /// page owns, so viewing responses for a future date here can't leave the
  /// kitchen page defaulted to the wrong day. Includes plan dates so the
  /// page can show each member's meals-consumed/meals-left profile too.
  List<Map<String, dynamic>> responseMeals = [];

  Future<void> fetchResponseMeals(DateTime date) async {
    try {
      final rows = await _client
          .from('meal_confirmations')
          .select('*, subscriptions(customer_name,food_preference,'
              'morning_preference,evening_preference,start_date,end_date,is_test,'
              'meals_remaining,subscription_plans(duration_days,meals_per_day))')
          .eq('meal_date', _d(date))
          .order('created_at');
      responseMeals = (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {
      responseMeals = [];
    }
    notifyListeners();
  }

  // ── Meal library + daily schedule (customizable meal plan) ────────────────

  List<String> get mealCategories {
    final cats = <String>{};
    for (final m in mealLibrary) {
      final c = (m['category'] as String?)?.trim();
      if (c != null && c.isNotEmpty) cats.add(c);
    }
    final sorted = cats.toList()..sort();
    return sorted;
  }

  Future<void> fetchMealLibrary() async {
    try {
      final rows = await _client
          .from('subscription_meals')
          .select()
          .order('sort_order')
          .order('name');
      final list = (rows as List).cast<Map<String, dynamic>>();

      // Enrich with category from menu_items if not already present
      try {
        final menuRows = await _client
            .from('menu_items')
            .select('name, category, badge');
        final catMap = <String, Map<String, dynamic>>{};
        for (final m in (menuRows as List)) {
          final n = (m['name'] as String?)?.toLowerCase().trim();
          if (n != null && n.isNotEmpty) {
            catMap[n] = m as Map<String, dynamic>;
          }
        }
        for (final d in list) {
          final n = (d['name'] as String?)?.toLowerCase().trim();
          if (n != null && catMap.containsKey(n)) {
            final match = catMap[n]!;
            d['category'] ??= match['category'];
            d['badge'] ??= match['badge'];
          }
          d['category'] ??= 'General';
        }
      } catch (_) {
        for (final d in list) {
          d['category'] ??= 'General';
        }
      }

      mealLibrary = list;
      error = null;
    } catch (e) {
      error = 'Could not load meal library: $e';
    }
    notifyListeners();
  }

  /// The admin-editable set of dietary categories (veg/non-veg/vegan/…),
  /// used to tag dishes and members — replaces what used to be a hardcoded
  /// list in the UI. Not the same as the WhatsApp survey's veg/non-veg/mixed
  /// choice, which is fixed by the published Flow's own screens.
  Future<void> fetchFoodPreferences() async {
    try {
      final rows = await _client
          .from('food_preferences')
          .select()
          .order('sort_order')
          .order('label');
      foodPreferences = (rows as List).cast<Map<String, dynamic>>();
      error = null;
    } catch (e) {
      error = 'Could not load food preferences: $e';
    }
    notifyListeners();
  }

  Future<String?> saveFoodPreference(Map<String, dynamic> pref) async {
    try {
      final data = Map<String, dynamic>.from(pref);
      final id = data.remove('id');
      if (id == null) {
        await _client.from('food_preferences').insert(data);
      } else {
        await _client.from('food_preferences').update(data).eq('id', id);
      }
      await fetchFoodPreferences();
      return null;
    } catch (e) {
      return 'Could not save food preference: $e';
    }
  }

  Future<String?> deleteFoodPreference(String id) async {
    try {
      await _client.from('food_preferences').delete().eq('id', id);
      await fetchFoodPreferences();
      return null;
    } catch (e) {
      return 'Could not delete food preference: $e';
    }
  }

  Future<void> fetchSchedule(DateTime date) async {
    try {
      final rows = await _client
          .from('meal_schedule')
          .select('*, subscription_meals(name,description,image_url,kcal)')
          .eq('meal_date', _d(date));
      final byPref = <String, List<Map<String, dynamic>>>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        byPref.putIfAbsent(r['food_preference'] as String, () => []).add(r);
      }
      scheduleByPref = byPref;
      notifyListeners();
    } catch (_) {/* schedule is optional — KDS still works without it */}
  }

  /// Add a dish to a date + preference's list of options (one of possibly
  /// several — this is no longer a single pick).
  Future<String?> addDishToSchedule(
      DateTime date, String preference, String mealId) async {
    try {
      await _client.from('meal_schedule').insert({
        'meal_date': _d(date),
        'food_preference': preference,
        'meal_id': mealId,
      });
      await fetchSchedule(date);
      return null;
    } catch (e) {
      if (e.toString().contains('23505')) return null; // already on the menu
      return 'Could not add the dish: $e';
    }
  }

  /// Remove one dish option from a date + preference's menu.
  Future<String?> removeDishFromSchedule(
      DateTime date, String preference, String mealId) async {
    try {
      await _client
          .from('meal_schedule')
          .delete()
          .eq('meal_date', _d(date))
          .eq('food_preference', preference)
          .eq('meal_id', mealId);
      await fetchSchedule(date);
      return null;
    } catch (e) {
      return 'Could not remove the dish: $e';
    }
  }

  // ── Groups + per-member/group meal assignment ──────────────────────────────

  Future<void> fetchGroups() async {
    try {
      final rows =
          await _client.from('member_groups').select().order('name');
      groups = (rows as List).cast<Map<String, dynamic>>();
      notifyListeners();
    } catch (_) {/* groups are optional to load — UI shows empty list */}
  }

  Future<String?> saveGroup(Map<String, dynamic> group) async {
    try {
      final data = Map<String, dynamic>.from(group);
      final id = data.remove('id');
      if (id == null) {
        await _client.from('member_groups').insert(data);
      } else {
        await _client.from('member_groups').update(data).eq('id', id);
      }
      await fetchGroups();
      return null;
    } catch (e) {
      return 'Could not save group: $e';
    }
  }

  Future<void> deleteGroup(String id) async {
    try {
      await _client.from('member_groups').delete().eq('id', id);
      await fetchGroups();
    } catch (_) {}
  }

  /// Which group (if any) a member belongs to.
  Future<void> setMemberGroup(String subscriptionId, String? groupId) async {
    try {
      await _client
          .from('subscriptions')
          .update({'group_id': groupId}).eq('id', subscriptionId);
      await fetchSubscriptions();
    } catch (_) {}
  }

  /// Create/update a dish. [imageFile] is a File (mobile) or Uint8List (web),
  /// uploaded to the shared menu-images bucket like the dining menu does.
  Future<String?> saveMealDish(Map<String, dynamic> dish,
      {dynamic imageFile}) async {
    try {
      final data = Map<String, dynamic>.from(dish);
      final id = data.remove('id');
      if (imageFile != null) {
        try {
          data['image_url'] = await _uploadImage('submeal', imageFile);
        } catch (e) {
          return 'Image upload failed: $e';
        }
      }
      data['updated_at'] = DateTime.now().toIso8601String();
      if (id == null) {
        await _client.from('subscription_meals').insert(data);
      } else {
        await _client.from('subscription_meals').update(data).eq('id', id);
      }
      await fetchMealLibrary();
      return null;
    } catch (e) {
      return 'Could not save dish: $e';
    }
  }

  Future<void> deleteMealDish(String id) async {
    try {
      await _client.from('subscription_meals').delete().eq('id', id);
      await fetchMealLibrary();
    } catch (e) {
      error = 'Could not delete dish: $e';
      notifyListeners();
    }
  }

  /// Copies all dishes from the gym model's menu_items table into the
  /// subscription_meals table. Deduplicates by name to avoid double-imports.
  /// Only copies fields relevant to subscriptions (e.g. ignores price since
  /// subscription meals are prepaid via the plan).
  Future<String?> importFromGymMenu() async {
    try {
      final gymRows = await _client.from('menu_items').select();
      final gymDishes = (gymRows as List).cast<Map<String, dynamic>>();

      final subRows = await _client.from('subscription_meals').select('name');
      final subNames = (subRows as List)
          .map((r) => (r['name'] as String).toLowerCase().trim())
          .toSet();

      int count = 0;
      for (final gymDish in gymDishes) {
        final name = (gymDish['name'] as String).trim();
        if (subNames.contains(name.toLowerCase())) continue;

        final rawKcal = gymDish['kcal'];
        final kcalVal = (rawKcal is num)
            ? rawKcal.toInt()
            : int.tryParse('$rawKcal') ?? 0;

        await _client.from('subscription_meals').insert({
          'name': name,
          'description': gymDish['description'] ?? '',
          'kcal': kcalVal,
          'image_url': gymDish['image_url'],
          'active': gymDish['available'] ?? true,
          'protein': gymDish['protein'] ?? 0,
          'carbs': gymDish['carbs'] ?? 0,
          'fat': gymDish['fat'] ?? 0,
          'updated_at': DateTime.now().toIso8601String(),
        });
        count++;
      }
      await fetchMealLibrary();
      return '$count dish(es) imported from gym menu ✅';
    } catch (e) {
      return 'Could not import from gym menu: $e';
    }
  }

  /// Uploads a File (mobile) or Uint8List (web) to the shared menu-images
  /// bucket, like the dining menu does. [prefix] just keeps filenames
  /// readable per use (dish photo vs banner image) — same bucket either way.
  Future<String> _uploadImage(String prefix, dynamic imageFile) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String fileName;
    dynamic uploadData;
    if (imageFile is File) {
      fileName = '${prefix}_${timestamp}_${p.basename(imageFile.path)}';
      uploadData = imageFile;
    } else if (imageFile is Uint8List) {
      fileName = '${prefix}_${timestamp}_image.jpg';
      uploadData = imageFile;
    } else {
      throw Exception('Invalid image type');
    }
    if (uploadData is File) {
      await _client.storage.from('menu-images').upload(fileName, uploadData);
    } else {
      await _client.storage
          .from('menu-images')
          .uploadBinary(fileName, uploadData as Uint8List);
    }
    return _client.storage.from('menu-images').getPublicUrl(fileName);
  }

  /// True while today's kitchen queue still has an unprepared meal — used by
  /// subscription_chef_page.dart to know when to stop the new-meal ringtone.
  /// Same "active minus prepared" set as toPrepareList there.
  bool get hasMealsAwaitingPrep => meals.any((m) =>
      ['confirmed', 'preparing'].contains(m['status']) &&
      (m['status'] != 'confirmed' || m['pushed_to_kitchen'] == true));

  void setKdsDate(DateTime d) {
    kdsDate = d;
    // A different date is a different queue, not a "new arrival" — without
    // this, switching dates would diff against the old date's ids and false-
    // trigger the ringtone.
    _knownKitchenMealIds = {};
    _mealsBaselineSet = false;
    fetchMeals();
  }

  void startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => fetchMeals());
  }

  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }

  Future<void> fetchEditors() async {
    try {
      final results = await Future.wait([
        _client.from('subscription_plans').select().order('sort_order'),
        _client.from('subscription_banners').select().order('sort_order'),
        _client.from('whatsapp_templates').select().order('title'),
        _client.from('delivery_agents').select().order('name'),
      ]);
      plans = (results[0] as List).cast<Map<String, dynamic>>();
      banners = (results[1] as List).cast<Map<String, dynamic>>();
      templates = (results[2] as List).cast<Map<String, dynamic>>();
      agents = (results[3] as List).cast<Map<String, dynamic>>();
      error = null;
    } catch (e) {
      error = 'Could not load settings: $e';
    }
    notifyListeners();
  }

  // ── Member lifecycle (edge function — server re-checks the role) ──────────

  Future<String?> _manage(Map<String, dynamic> body) async {
    try {
      final res =
          await _client.functions.invoke('admin-manage-member', body: body);
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] == true) return null;
      return data['error']?.toString() ?? 'Action failed';
    } catch (e) {
      final msg = e.toString();
      // FunctionsHttpError carries the server's message in details.
      return msg.length > 160 ? 'Action failed — check logs' : msg;
    }
  }

  Future<String?> approve({
    required String subscriptionId,
    required String email,
    required String password,
  }) async {
    final err = await _manage({
      'action': 'approve',
      'subscription_id': subscriptionId,
      'email': email,
      'password': password,
    });
    if (err == null) await fetchSubscriptions();
    return err;
  }

  Future<String?> reject(String subscriptionId, String reason) async {
    final err = await _manage({
      'action': 'reject',
      'subscription_id': subscriptionId,
      'reason': reason,
    });
    if (err == null) await fetchSubscriptions();
    return err;
  }

  Future<String?> removeMember(String subscriptionId) async {
    final err = await _manage({
      'action': 'remove',
      'subscription_id': subscriptionId,
    });
    if (err == null) await fetchSubscriptions();
    return err;
  }

  Future<String?> addMember(Map<String, dynamic> fields) async {
    final err = await _manage({'action': 'add_manual', ...fields});
    if (err == null) await fetchSubscriptions();
    return err;
  }

  // ── Manual entries ───────────────────────────────────────────────────────
  // Offline leads/payments a manager wants on record WITHOUT creating a real
  // member (no login, no WhatsApp automation) — see manual_subscription_entries.
  // Direct table access (RLS: is_sub_manager()), unlike addMember above which
  // must go through admin-manage-member to create an auth login.

  List<Map<String, dynamic>> manualEntries = [];

  /// Deduplicated customer list for the Manual Entries page picker — merges
  /// past manual entries + order customers into a unique-by-phone list.
  List<Map<String, String>> existingCustomers = [];

  Future<void> fetchManualEntries() async {
    try {
      final rows = await _client
          .from('manual_subscription_entries')
          .select()
          .order('created_at', ascending: false);
      manualEntries = (rows as List).cast<Map<String, dynamic>>();
      error = null;
    } catch (e) {
      error = 'Could not load manual entries: $e';
    }
    notifyListeners();
  }

  /// Fetches unique customers from manual_subscription_entries + orders,
  /// deduplicated by phone number (most recent entry wins).
  Future<void> fetchExistingCustomers() async {
    final seen = <String>{};
    final result = <Map<String, String>>[];
    try {
      // Manual entries first (more recent / relevant)
      final manualRows = await _client
          .from('manual_subscription_entries')
          .select('customer_name, phone')
          .order('created_at', ascending: false);
      for (final r in (manualRows as List)) {
        final name = (r['customer_name'] as String?)?.trim() ?? '';
        final phone = (r['phone'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final key = phone.isNotEmpty ? phone : name.toLowerCase();
        if (seen.add(key)) {
          result.add({'name': name, 'phone': phone});
        }
      }
      // Then orders for broader reach
      final orderRows = await _client
          .from('orders')
          .select('customer_name, customer_phone')
          .order('created_at', ascending: false)
          .limit(200);
      for (final r in (orderRows as List)) {
        final name = (r['customer_name'] as String?)?.trim() ?? '';
        final phone = (r['customer_phone'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final key = phone.isNotEmpty ? phone : name.toLowerCase();
        if (seen.add(key)) {
          result.add({'name': name, 'phone': phone});
        }
      }
    } catch (_) {}
    existingCustomers = result;
    notifyListeners();
  }

  Future<String?> addManualEntry(Map<String, dynamic> fields) async {
    try {
      final insertData = <String, dynamic>{
        'customer_name': fields['customer_name'] ?? '',
        'phone': fields['phone'] ?? '',
        'plan_name': fields['plan_name'] ?? '',
        'amount': fields['amount'] ?? 0,
        'notes': fields['notes'] ?? '',
        'added_by': _client.auth.currentUser?.email ?? '',
      };
      // Payment method (cod/prepaid) — stored in manual_subscription_entries
      // for record-keeping. The field may not exist in older schemas, so we
      // attempt it and fall back gracefully.
      final paymentMethod = fields['payment_method'] as String?;
      if (paymentMethod != null && paymentMethod.isNotEmpty) {
        insertData['payment_method'] = paymentMethod;
      }

      Map<String, dynamic> res;
      try {
        res = await _client
            .from('manual_subscription_entries')
            .insert(insertData)
            .select('id')
            .single();
      } catch (insertErr) {
        // If 'payment_method' column doesn't exist yet in the database schema cache,
        // retry insert without it and tag payment method into notes so data is preserved.
        if (insertData.containsKey('payment_method')) {
          final pm = insertData.remove('payment_method') as String?;
          if (pm != null && pm.isNotEmpty) {
            final curNotes = (insertData['notes'] as String?) ?? '';
            insertData['notes'] = curNotes.isEmpty
                ? '[${pm.toUpperCase()}]'
                : '[${pm.toUpperCase()}] $curNotes';
          }
          res = await _client
              .from('manual_subscription_entries')
              .insert(insertData)
              .select('id')
              .single();
        } else {
          rethrow;
        }
      }
      final entryId = res['id'] as String;

      // When the manager picked dishes, also create a meal_confirmations row
      // so this entry can flow through Today's Meal → KDS like a real member's
      // meal. The row uses the manual entry's id as a reference and gets
      // status 'confirmed' (the member already said yes by the manager adding
      // them) with pushed_to_kitchen=false (manager must still push).
      final dishIds = (fields['selected_dish_ids'] as List?)?.cast<String>();
      final mealDate = fields['meal_date'] as String?;
      final autoPush = fields['auto_push'] == true;
      // Special instructions flow as reply_text into meal_confirmations so
      // they're visible on the subscription KDS in red bold.
      final specialInstructions = (fields['notes'] as String?)?.trim() ?? '';
      String? mealConfirmationId;
      if (dishIds != null && dishIds.isNotEmpty && mealDate != null) {
        final mcData = <String, dynamic>{
          'meal_date': mealDate,
          'status': 'confirmed',
          'pushed_to_kitchen': autoPush,
          if (autoPush) 'pushed_at': DateTime.now().toIso8601String(),
          'meal_count': fields['meal_count'] ?? dishIds.length,
          'selected_dish_ids': dishIds,
          'reply_text': specialInstructions.isNotEmpty
              ? specialInstructions
              : (((fields['customer_name'] as String?)?.trim().isNotEmpty ?? false)
                  ? fields['customer_name'].trim()
                  : 'manual entry'),
          'manual_entry_id': entryId,
        };
        Map<String, dynamic> mcRes;
        try {
          mcRes = await _client
              .from('meal_confirmations')
              .insert(mcData)
              .select('id')
              .single();
        } catch (_) {
          mcData.remove('manual_entry_id');
          mcRes = await _client
              .from('meal_confirmations')
              .insert(mcData)
              .select('id')
              .single();
        }
        mealConfirmationId = mcRes['id'] as String;
      }
      await fetchManualEntries();
      await fetchMeals();
      // Auto-push: skip Today's Meal review — push directly to the subscription
      // KDS so the chef sees it immediately with the timer running.
      if (autoPush && mealConfirmationId != null) {
        // pushToKitchen is idempotent — it sets pushed_to_kitchen=true again
        // which is harmless since we already set it above, but it also sets
        // pushed_at and refetches, triggering the new-meal alert sound.
        await pushToKitchen([mealConfirmationId]);
      }
      return null;
    } catch (e) {
      return 'Could not add entry: $e';
    }
  }

  Future<String?> resetPassword(String subscriptionId, String password) =>
      _manage({
        'action': 'reset_password',
        'subscription_id': subscriptionId,
        'password': password,
      });

  Future<String?> editMemberDetails(
      String subscriptionId, Map<String, dynamic> fields) async {
    final err = await _manage({
      'action': 'edit_details',
      'subscription_id': subscriptionId,
      ...fields,
    });
    if (err == null) await fetchSubscriptions();
    return err;
  }

  /// Manually confirms/skips a meal on the member's behalf — e.g. their
  /// WhatsApp reply was free text that didn't parse as yes/no. Goes through
  /// admin-confirm-meal (not a direct table update) because it also sends
  /// the member the same confirm_ack/skip_ack WhatsApp message a real
  /// yes/no reply would have triggered.
  Future<String?> confirmMealManually(
      String mealConfirmationId, {required bool yes}) async {
    try {
      final res = await _client.functions.invoke('admin-confirm-meal', body: {
        'meal_confirmation_id': mealConfirmationId,
        'decision': yes ? 'yes' : 'no',
      });
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] != true) return data['error']?.toString() ?? 'Action failed';
      return null;
    } catch (e) {
      final msg = e.toString();
      return msg.length > 160 ? 'Action failed — check logs' : msg;
    }
  }

  // ── KDS / delivery actions (RLS: staff update) ─────────────────────────────

  Future<String?> updateMeal(String id, Map<String, dynamic> fields) async {
    try {
      await _client
          .from('meal_confirmations')
          .update({...fields, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', id);
      await fetchMeals();
      return null;
    } catch (e) {
      error = 'Update failed: $e';
      notifyListeners();
      return 'Update failed: $e';
    }
  }

  /// Adjusts a member's meals_remaining balance by [delta].
  /// Positive = restore meals, negative = deduct more.
  /// Used when a manager overrides meal_count on Today's Meal page after the
  /// initial confirmation already deducted the plan's default meals_per_day.
  Future<void> adjustMealsRemaining(String subscriptionId, int delta) async {
    if (delta == 0) return;
    try {
      await _client.rpc('adjust_meals_remaining',
          params: {'sub_id': subscriptionId, 'delta': delta});
    } catch (e) {
      error = 'Could not adjust meal balance: $e';
      notifyListeners();
    }
  }

  Future<void> setMealStatus(String id, String status) {
    final fields = <String, dynamic>{'status': status};
    if (status == 'prepared') {
      fields['prepared_at'] = DateTime.now().toIso8601String();
    }
    if (status == 'delivered') {
      fields['delivered_at'] = DateTime.now().toIso8601String();
    }
    return updateMeal(id, fields);
  }

  Future<void> setPriority(String id, int priority) =>
      updateMeal(id, {'priority': priority});

  Future<void> assignAgent(String id, String? agentId) =>
      updateMeal(id, {'delivery_agent_id': agentId});

  Future<String?> recordPayment(
    String id, {
    required String method,
    required double amount,
    String? manualEntryId,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      // Try full payment tracking fields first
      var err = await updateMeal(id, {
        'payment_method': method,
        'payment_status': 'paid',
        'payment_amount': amount,
        'payment_collected_at': now,
        'status': 'delivered',
        'delivered_at': now,
      });

      // If schema cache doesn't have payment columns yet, fallback to status & delivered_at
      if (err != null && (err.contains('PGRST204') || err.contains('payment_') || err.contains('schema cache'))) {
        err = await updateMeal(id, {
          'status': 'delivered',
          'delivered_at': now,
        });
      }

      if (err != null) return err;

      if (manualEntryId != null && manualEntryId.isNotEmpty) {
        try {
          await _client.from('manual_subscription_entries').update({
            'amount': amount,
          }).eq('id', manualEntryId);
        } catch (_) {}
      }

      // Update in-memory meal state so UI reflects paid & delivered immediately
      final mealIdx = meals.indexWhere((m) => m['id'] == id);
      if (mealIdx != -1) {
        meals[mealIdx]['payment_status'] = 'paid';
        meals[mealIdx]['payment_method'] = method;
        meals[mealIdx]['payment_amount'] = amount;
        meals[mealIdx]['status'] = 'delivered';
      }

      await fetchMeals();
      notifyListeners();
      return null;
    } catch (e) {
      error = 'Could not record payment: $e';
      notifyListeners();
      return error;
    }
  }

  /// Calls Razorpay backend API (delivery-create-qr Edge Function) to create
  /// a dynamic Razorpay QR Code / Payment Link for on-the-spot meal delivery collection.
  Future<Map<String, dynamic>?> createDeliveryQr({
    required String mealId,
    required double amount,
    required String customerName,
    required String phone,
    String? manualEntryId,
  }) async {
    try {
      final res = await _client.functions.invoke('delivery-create-qr', body: {
        'meal_id': mealId,
        'amount': amount,
        'customer_name': customerName,
        'phone': phone,
        'manual_entry_id': manualEntryId,
      });

      if (res.status == 200 && res.data != null) {
        return (res.data as Map).cast<String, dynamic>();
      } else {
        final err = res.data?['error']?.toString() ?? 'Could not create QR code';
        error = err;
        notifyListeners();
        return null;
      }
    } catch (e) {
      error = 'Could not generate Razorpay QR: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> setDeliveryTime(String id, String time) async {
    await updateMeal(id, {'delivery_time': time});
    if (_isTimeDue(time)) {
      await pushToKitchen([id]);
    }
  }

  Future<void> setDishDeliveryTime(String id, int dishIndex, String time) async {
    final meal = meals.firstWhere((m) => m['id'] == id, orElse: () => const {});
    final rawTime = (meal['delivery_time'] ?? '').toString();
    Map<String, dynamic> timesMap = {};
    if (rawTime.startsWith('{')) {
      try {
        timesMap = Map<String, dynamic>.from(jsonDecode(rawTime));
      } catch (_) {}
    } else if (rawTime.isNotEmpty) {
      timesMap['0'] = rawTime;
    }
    timesMap[dishIndex.toString()] = time;
    final encoded = jsonEncode(timesMap);
    await setDeliveryTime(id, encoded);
  }

  /// Moves confirmed orders from the Today's Meal review queue into the
  /// Kitchen Display's queue. One update + one refetch for the whole batch,
  /// rather than looping updateMeal (which refetches after every call).
  Future<String?> pushToKitchen(List<String> mealConfirmationIds) async {
    if (mealConfirmationIds.isEmpty) return null;
    try {
      final now = DateTime.now().toIso8601String();
      await _client
          .from('meal_confirmations')
          .update({
            'pushed_to_kitchen': true,
            'pushed_at': now,
            'updated_at': now,
          })
          .inFilter('id', mealConfirmationIds);
      await fetchMeals();
      return null;
    } catch (e) {
      return 'Could not push to kitchen: $e';
    }
  }

  // ── Delivery agents ────────────────────────────────────────────────────────

  Future<String?> addAgent(String name, String phone) async {
    try {
      await _client.from('delivery_agents').insert({
        'name': name,
        'phone': phone,
      });
      await fetchEditors();
      return null;
    } catch (e) {
      return 'Could not add agent: $e';
    }
  }

  Future<void> toggleAgent(String id, bool active) async {
    try {
      await _client
          .from('delivery_agents')
          .update({'active': active}).eq('id', id);
      await fetchEditors();
    } catch (_) {}
  }

  // ── No-code editors ────────────────────────────────────────────────────────

  Future<String?> savePlan(Map<String, dynamic> plan) async {
    try {
      final data = Map<String, dynamic>.from(plan);
      final id = data.remove('id');
      data['updated_at'] = DateTime.now().toIso8601String();
      if (id == null) {
        await _client.from('subscription_plans').insert(data);
      } else {
        await _client.from('subscription_plans').update(data).eq('id', id);
      }
      await fetchEditors();
      return null;
    } catch (e) {
      return 'Could not save plan: $e';
    }
  }

  Future<String?> saveBanner(Map<String, dynamic> banner, {dynamic imageFile}) async {
    try {
      final data = Map<String, dynamic>.from(banner);
      final id = data.remove('id');
      if (imageFile != null) {
        try {
          data['image_url'] = await _uploadImage('banner', imageFile);
        } catch (e) {
          return 'Image upload failed: $e';
        }
      }
      if (id == null) {
        await _client.from('subscription_banners').insert(data);
      } else {
        await _client.from('subscription_banners').update(data).eq('id', id);
      }
      await fetchEditors();
      return null;
    } catch (e) {
      return 'Could not save banner: $e';
    }
  }

  Future<void> deleteBanner(String id) async {
    try {
      await _client.from('subscription_banners').delete().eq('id', id);
      await fetchEditors();
    } catch (_) {}
  }

  Future<String?> saveTemplate(String id, String text, bool active) async {
    try {
      await _client.from('whatsapp_templates').update({
        'message_text': text,
        'active': active,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      await fetchEditors();
      return null;
    } catch (e) {
      return 'Could not save template: $e';
    }
  }

  // ── WhatsApp credentials (app_config) ──────────────────────────────────────

  Future<Map<String, dynamic>> loadWhatsAppConfig() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'whatsapp_credentials')
          .maybeSingle();
      return (row?['value'] as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<String?> saveWhatsAppConfig(Map<String, dynamic> value) async {
    try {
      await _client.from('app_config').upsert({
        'key': 'whatsapp_credentials',
        'value': value,
        'description': 'WhatsApp Business API credentials',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      return null;
    } catch (e) {
      return 'Could not save credentials: $e';
    }
  }

  // ── Nightly reminder time (app_config) ──────────────────────────────────────
  // The edge function polls every 5 minutes and only actually sends once past
  // this IST time each day — see send-daily-meal-whatsapp. Defaults to 8 PM,
  // the original fixed schedule, until changed here.

  Future<Map<String, int>> loadMealReminderTime() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'meal_reminder_time')
          .maybeSingle();
      final v = (row?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      return {
        'hour': (v['hour'] as num?)?.toInt() ?? 20,
        'minute': (v['minute'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return {'hour': 20, 'minute': 0};
    }
  }

  Future<String?> saveMealReminderTime(int hour, int minute) async {
    try {
      await _client.from('app_config').upsert({
        'key': 'meal_reminder_time',
        'value': {'hour': hour, 'minute': minute},
        'description': 'Nightly meal-reminder WhatsApp send time (IST)',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      return null;
    } catch (e) {
      return 'Could not save time: $e';
    }
  }

  // ── Reply-by cutoff shown in the message text (app_config) ─────────────────
  // Fills the {{cutoff_time}} placeholder — was a hardcoded "11:00 PM tonight"
  // in the edge function; now admin-settable same as the send time above.

  Future<Map<String, int>> loadMealReminderCutoff() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'meal_reminder_cutoff_time')
          .maybeSingle();
      final v = (row?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      return {
        'hour': (v['hour'] as num?)?.toInt() ?? 23,
        'minute': (v['minute'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      return {'hour': 23, 'minute': 0};
    }
  }

  Future<String?> saveMealReminderCutoff(int hour, int minute) async {
    try {
      await _client.from('app_config').upsert({
        'key': 'meal_reminder_cutoff_time',
        'value': {'hour': hour, 'minute': minute},
        'description':
            'Reply-by deadline (IST) shown in the meal-reminder message',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      return null;
    } catch (e) {
      return 'Could not save cutoff time: $e';
    }
  }

  // ── Auto-confirm time (app_config) ─────────────────────────────────────────
  // At this IST time, every 'awaiting' meal_confirmations row for today is
  // automatically promoted to 'confirmed' — treating no-response as YES so
  // members still get their meals even if they forgot to reply on WhatsApp.
  // Runs BEFORE the cutoff (which skips anything still 'awaiting' after this).

  Future<Map<String, int>> loadAutoConfirmTime() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'meal_auto_confirm_time')
          .maybeSingle();
      final v = (row?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      return {
        'hour': (v['hour'] as num?)?.toInt() ?? 11,
        'minute': (v['minute'] as num?)?.toInt() ?? 0,
        'enabled': (v['enabled'] as bool? ?? true) ? 1 : 0,
      };
    } catch (_) {
      return {'hour': 11, 'minute': 0, 'enabled': 1};
    }
  }

  Future<String?> saveAutoConfirmTime(int hour, int minute,
      {bool enabled = true}) async {
    try {
      await _client.from('app_config').upsert({
        'key': 'meal_auto_confirm_time',
        'value': {'hour': hour, 'minute': minute, 'enabled': enabled},
        'description':
            'IST time to auto-confirm unanswered meal responses (treat no-reply as YES)',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      return null;
    } catch (e) {
      return 'Could not save auto-confirm time: $e';
    }
  }

  // ── Which Meta template name to actually send (app_config) ─────────────────
  // do_you_need_meal_today is PENDING Meta approval as of writing — this lets
  // a manager point the send at whichever template IS currently approved,
  // without a code deploy, the moment one clears review.

  Future<String> loadMealReminderTemplateName() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'meal_reminder_template_name')
          .maybeSingle();
      final v = (row?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      return (v['name'] as String?) ?? 'do_you_need_meal_today';
    } catch (_) {
      return 'do_you_need_meal_today';
    }
  }

  Future<String?> saveMealReminderTemplateName(String name) async {
    try {
      await _client.from('app_config').upsert({
        'key': 'meal_reminder_template_name',
        'value': {'name': name},
        'description': 'Meta template name sent for the nightly meal reminder',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      return null;
    } catch (e) {
      return 'Could not save template name: $e';
    }
  }

  /// Manual trigger of the nightly job ("Send now" in the panel). Sends to
  /// every active member when [subscriptionIds] is omitted/empty, or only to
  /// the given members otherwise.
  Future<String?> sendTonightNow({List<String>? subscriptionIds}) async {
    try {
      final res = await _client.functions.invoke('send-daily-meal-whatsapp',
          body: {
            'source': 'manual',
            if (subscriptionIds != null && subscriptionIds.isNotEmpty)
              'subscription_ids': subscriptionIds,
          });
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] == true) {
        final sent = data['sent'] ?? 0;
        final failed = data['failed'] ?? 0;
        final noPhone = data['skippedNoPhone'] ?? 0;
        final n = data['members'] ?? 0;
        final cfg = data['configured'] == true;
        if (!cfg) {
          return 'Meal rows created for $n members, but WhatsApp is NOT configured yet.';
        }
        final lastError = data['lastError']?.toString();
        final suffix = [
          if (failed > 0 && lastError != null) '$failed failed: $lastError',
          if (noPhone > 0) '$noPhone with no phone on file',
        ].join(', ');
        return suffix.isEmpty
            ? 'Done — $sent of $n members messaged.'
            : 'Done — $sent of $n messaged, $suffix';
      }
      return data['error']?.toString() ?? 'Job failed';
    } catch (e) {
      return 'Job failed: $e';
    }
  }

  /// Manual trigger for the veg/non-veg/mixed preference ask. Sends to every
  /// active member when [subscriptionIds] is omitted/empty, or only to the
  /// given members otherwise. See send-food-preference-whatsapp.
  Future<String?> sendFoodPreferenceNow({List<String>? subscriptionIds}) async {
    try {
      final res = await _client.functions.invoke('send-food-preference-whatsapp',
          body: {
            if (subscriptionIds != null && subscriptionIds.isNotEmpty)
              'subscription_ids': subscriptionIds,
          });
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] == true) {
        final sent = data['sent'] ?? 0;
        final failed = data['failed'] ?? 0;
        final noPhone = data['skippedNoPhone'] ?? 0;
        final n = data['members'] ?? 0;
        final cfg = data['configured'] == true;
        if (!cfg) {
          return 'WhatsApp is NOT configured yet — nothing sent.';
        }
        final lastError = data['lastError']?.toString();
        final suffix = [
          if (failed > 0 && lastError != null) '$failed failed: $lastError',
          if (noPhone > 0) '$noPhone with no phone on file',
        ].join(', ');
        return suffix.isEmpty
            ? 'Done — $sent of $n members messaged.'
            : 'Done — $sent of $n messaged, $suffix';
      }
      return data['error']?.toString() ?? 'Job failed';
    } catch (e) {
      return 'Job failed: $e';
    }
  }

  // ── Automation member selection (app_config) ────────────────────────────────
  // Which members the nightly cron run should cover: everyone active (default)
  // or an admin-picked subset. See send-daily-meal-whatsapp.

  Future<Map<String, dynamic>> loadMealReminderMembers() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'meal_reminder_members')
          .maybeSingle();
      final v = (row?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      return {
        'mode': (v['mode'] as String?) ?? 'all',
        'subscriptionIds': ((v['subscription_ids'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
      };
    } catch (_) {
      return {'mode': 'all', 'subscriptionIds': <String>[]};
    }
  }

  Future<String?> saveMealReminderMembers(
      String mode, List<String> subscriptionIds) async {
    try {
      await _client.from('app_config').upsert({
        'key': 'meal_reminder_members',
        'value': {'mode': mode, 'subscription_ids': subscriptionIds},
        'description': 'Which members the nightly WhatsApp reminder covers',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      return null;
    } catch (e) {
      return 'Could not save member selection: $e';
    }
  }

  // ── Off-days: skip automation on specific days of the week ─────────────────
  // Stored as a list of day-of-week numbers (0=Sunday, 1=Monday, ... 6=Saturday)
  // matching Dart's DateTime.sunday etc. The edge function reads this config and
  // skips sending on those days entirely.

  Future<List<int>> loadMealReminderOffDays() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'meal_reminder_off_days')
          .maybeSingle();
      final v = (row?['value'] as Map?)?.cast<String, dynamic>() ?? {};
      return ((v['days'] as List?) ?? [])
          .map((e) => (e as num).toInt())
          .toList();
    } catch (_) {
      return <int>[];
    }
  }

  Future<String?> saveMealReminderOffDays(List<int> days) async {
    try {
      await _client.from('app_config').upsert({
        'key': 'meal_reminder_off_days',
        'value': {'days': days},
        'description':
            'Days of the week the WhatsApp meal reminder is skipped '
            '(0=Sun, 1=Mon, ..., 6=Sat)',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      return null;
    } catch (e) {
      return 'Could not save off-days: $e';
    }
  }

  // ── Store UPI ID for Direct Delivery Payments (app_config) ──────────────────

  String storeUpiId = 'Q943344060@ybl';

  Future<String> fetchStoreUpiId() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'store_upi_id')
          .maybeSingle();
      if (row != null && row['value'] != null) {
        final val = (row['value'] as Map?)?['upi_id']?.toString() ??
            row['value']?.toString() ??
            '';
        if (val.isNotEmpty) {
          storeUpiId = val;
          notifyListeners();
          return storeUpiId;
        }
      }
    } catch (_) {}
    return storeUpiId;
  }

  Future<String?> saveStoreUpiId(String upiId) async {
    try {
      storeUpiId = upiId.trim();
      notifyListeners();
      await _client.from('app_config').upsert({
        'key': 'store_upi_id',
        'value': {'upi_id': storeUpiId},
        'description': 'Direct Store UPI VPA used for delivery collection QR codes',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'key');
      return null;
    } catch (e) {
      return 'Could not save store UPI ID: $e';
    }
  }

  // ── Google Sheets Export Triggers ──────────────────────────────────────────

  /// Manually syncs pending subscription meals to Google Sheets (Sheet2).
  Future<String?> pushSubscriptionMealsToSheetNow() async {
    try {
      final res = await _client.functions
          .invoke('export-subscription-meals-to-sheets', body: {'source': 'manual'});
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['error'] != null) return data['error'].toString();
      final exported = data['exported'] ?? 0;
      final pruned = data['pruned'] ?? 0;
      return 'Exported $exported meal(s) to Sheet2'
          '${pruned > 0 ? ', pruned $pruned old row(s) from database' : ''}.';
    } catch (e) {
      return 'Meals export failed: $e';
    }
  }

  /// Manually syncs pending manual subscription entries to Google Sheets (Sheet3).
  Future<String?> pushManualEntriesToSheetNow() async {
    try {
      final res = await _client.functions
          .invoke('export-manual-entries-to-sheets', body: {'source': 'manual'});
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['error'] != null) return data['error'].toString();
      final exported = data['exported'] ?? 0;
      return 'Exported $exported manual entry/entries to Sheet3.';
    } catch (e) {
      return 'Manual entries export failed: $e';
    }
  }
}
