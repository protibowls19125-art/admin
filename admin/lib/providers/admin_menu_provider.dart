import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/menu_item.dart';
import '../services/supabase_service.dart';

const _kCategoriesKey = 'admin_categories';
const _kDefaultCategories = [
  'Appetizers', 'Main', 'Desserts', 'Beverages', 'Snacks', 'Salads'
];

class AdminMenuProvider extends ChangeNotifier {
  List<MenuItem> _items = [];
  List<String> _customCategories = List.from(_kDefaultCategories);
  bool _isLoading = false;
  String _selectedCategory = 'All';
  // Admin-editable badge options (VEG/NON-VEG/PLANT-BASED/...) — see
  // menu_badges table. Not hardcoded like the old two-chip picker.
  List<Map<String, dynamic>> badges = [];
  // Title above the featured-items hero on the customer home page — was
  // hardcoded "FEATURED CREATION"; now app_config-driven (menu_featured_label).
  String featuredLabel = "TODAY'S SPECIAL";

  List<MenuItem> get items => _items;
  bool get isLoading => _isLoading;
  String get selectedCategory => _selectedCategory;

  Future<void> fetchFeaturedLabel() async {
    try {
      final row = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', 'menu_featured_label')
          .maybeSingle();
      final label = (row?['value'] as Map?)?['label'] as String?;
      if (label != null && label.isNotEmpty) featuredLabel = label;
    } catch (_) {}
    notifyListeners();
  }

  Future<String?> saveFeaturedLabel(String label) async {
    try {
      await SupabaseService.client.from('app_config').update({
        'value': {'label': label},
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('key', 'menu_featured_label');
      featuredLabel = label;
      notifyListeners();
      return null;
    } catch (e) {
      return 'Could not save: $e';
    }
  }

  Future<String?> setFeaturedBulk(List<String> itemIds, bool featured) async {
    if (itemIds.isEmpty) return null;
    try {
      await SupabaseService.client
          .from(SupabaseService.tableMenuItems)
          .update({'featured': featured}).inFilter('id', itemIds);
      await fetchAll();
      return null;
    } catch (e) {
      return 'Could not update: $e';
    }
  }

  Future<void> fetchBadges() async {
    try {
      final rows = await SupabaseService.client
          .from('menu_badges')
          .select()
          .order('sort_order');
      badges = (rows as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    notifyListeners();
  }

  List<String> get categories {
    final fromItems = _items.map((i) => i.category).toSet();
    final all = {..._customCategories, ...fromItems}.toList();
    all.sort();
    return all;
  }

  Future<void> _loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kCategoriesKey);
    if (saved != null) _customCategories = saved;
  }

  Future<void> _saveCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kCategoriesKey, _customCategories);
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _customCategories.contains(trimmed)) return;
    _customCategories.add(trimmed);
    await _saveCategories();
    notifyListeners();
  }

  Future<void> removeCategory(String name) async {
    _customCategories.remove(name);
    await _saveCategories();
    notifyListeners();
  }

  Future<void> fetchAll() async {
    _isLoading = true;
    notifyListeners();
    await _loadCategories();
    if (badges.isEmpty) unawaited(fetchBadges());
    unawaited(fetchFeaturedLabel());
    try {
      final response = await SupabaseService.client
          .from(SupabaseService.tableMenuItems)
          .select()
          .order('category');
      _items =
          (response as List).map((json) => MenuItem.fromJson(json)).toList();
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addItem({
    required String name,
    required double price,
    double compareAtPrice = 0,
    required String category,
    String? description,
    String? badge,
    dynamic imageFile,
    bool available = true,
    int kcal = 0,
    String servingSize = '',
    double protein = 0,
    double carbs = 0,
    double fat = 0,
    double fiber = 0,
    int? dailyLimit,
    bool customizable = true,
    List<Map<String, dynamic>> addons = const [],
  }) async {
    String? imageUrl;
    if (imageFile != null &&
        ((imageFile is File) ||
            (imageFile is Uint8List && imageFile.isNotEmpty))) {
      try {
        imageUrl = await _uploadImage(imageFile);
      } catch (_) {}
    }

    await SupabaseService.client.from(SupabaseService.tableMenuItems).insert({
      'name': name,
      'price': price,
      'compare_at_price': compareAtPrice,
      'category': category,
      'description': description ?? '',
      'image_url': imageUrl,
      'available': available,
      'customizable': customizable,
      'addons': addons,
      'kcal': kcal,
      'serving_size': servingSize,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
      if (dailyLimit != null && dailyLimit > 0) 'daily_limit': dailyLimit,
      'orders_today': 0,
      'last_reset_date': '',
      if (badge != null && badge.isNotEmpty) 'badge': badge,
    });
    await fetchAll();
  }

  Future<void> updateItem({
    required String itemId,
    required String name,
    required double price,
    double? compareAtPrice,
    String? description,
    String? category,
    String? badge,
    dynamic imageFile,
    bool? available,
    int? kcal,
    String? servingSize,
    double? protein,
    double? carbs,
    double? fat,
    double? fiber,
    int? dailyLimit,
    bool clearDailyLimit = false,
    bool? customizable,
    List<Map<String, dynamic>>? addons,
  }) async {
    final updateData = <String, dynamic>{
      'name': name,
      'price': price,
      if (compareAtPrice != null) 'compare_at_price': compareAtPrice,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      'badge': (badge != null && badge.isNotEmpty) ? badge : null,
      if (available != null) 'available': available,
      if (customizable != null) 'customizable': customizable,
      if (addons != null) 'addons': addons,
      if (kcal != null) 'kcal': kcal,
      if (servingSize != null) 'serving_size': servingSize,
      if (protein != null) 'protein': protein,
      if (carbs != null) 'carbs': carbs,
      if (fat != null) 'fat': fat,
      if (fiber != null) 'fiber': fiber,
      'daily_limit':
          clearDailyLimit ? null : (dailyLimit != null && dailyLimit > 0 ? dailyLimit : null),
    };

    if (imageFile != null &&
        ((imageFile is File) ||
            (imageFile is Uint8List && imageFile.isNotEmpty))) {
      try {
        final imageUrl = await _uploadImage(imageFile);
        updateData['image_url'] = imageUrl;
      } catch (_) {}
    }

    await SupabaseService.client
        .from(SupabaseService.tableMenuItems)
        .update(updateData)
        .eq('id', itemId);
    await fetchAll();
  }

  Future<void> resetTodayCount(String itemId) async {
    try {
      await SupabaseService.client
          .from(SupabaseService.tableMenuItems)
          .update({'orders_today': 0, 'available': true})
          .eq('id', itemId);
      await fetchAll();
    } catch (_) {}
  }

  Future<String> _uploadImage(dynamic imageFile) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String fileName;
    Uint8List uploadData;

    if (imageFile is File) {
      fileName = 'menu_${timestamp}_${p.basename(imageFile.path)}';
      uploadData = await imageFile.readAsBytes();
    } else if (imageFile is Uint8List) {
      fileName = 'menu_${timestamp}_image.jpg';
      uploadData = imageFile;
    } else {
      throw Exception('Invalid image type');
    }

    await SupabaseService.client.storage
        .from('menu-images')
        .uploadBinary(fileName, uploadData);

    return SupabaseService.client.storage
        .from('menu-images')
        .getPublicUrl(fileName);
  }

  void selectCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  Future<void> toggleAvailability(String itemId, bool available) async {
    try {
      await SupabaseService.client
          .from(SupabaseService.tableMenuItems)
          .update({'available': available})
          .eq('id', itemId);
      await fetchAll();
    } catch (_) {}
  }

  /// Deletes a menu item. Returns null on success, otherwise a user-facing
  /// reason it failed (e.g. it has past orders and can't be removed).
  Future<String?> deleteItem(String itemId) async {
    try {
      await SupabaseService.client
          .from(SupabaseService.tableMenuItems)
          .delete()
          .eq('id', itemId);
      _items.removeWhere((item) => item.id == itemId);
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        return "Can't delete — this item has past orders. "
            'Mark it unavailable instead.';
      }
      return e.message;
    } catch (e) {
      return 'Could not delete item: $e';
    }
  }
}
