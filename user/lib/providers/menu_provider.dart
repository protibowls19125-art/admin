import 'package:flutter/material.dart';
import '../models/menu_item.dart';
import '../services/supabase_service.dart';

class MenuProvider extends ChangeNotifier {
  List<MenuItem> _items = [];
  bool _isLoading = false;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  // Title above the featured-items hero — admin-editable (app_config
  // menu_featured_label), was hardcoded "FEATURED CREATION".
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
      if (label != null && label.isNotEmpty) {
        featuredLabel = label;
        notifyListeners();
      }
    } catch (_) {}
  }

  List<String> get categories {
    final cats = _items.map((item) => item.category).toSet().toList();
    return ['All', ...cats.cast<String>()];
  }

  String get searchQuery => _searchQuery;

  List<MenuItem> get filteredItems {
    var list = _selectedCategory == 'All'
        ? List<MenuItem>.from(_items)
        : _items.where((item) => item.category == _selectedCategory).toList();
    if (_searchQuery.isNotEmpty) {
      // While searching, reveal matches even if they're sold out (so a customer
      // can find a specific dish and see it's currently unavailable).
      final q = _searchQuery.toLowerCase();
      list = list
          .where((item) =>
              item.name.toLowerCase().contains(q) ||
              item.description.toLowerCase().contains(q))
          .toList();
    } else {
      // Normal browsing: hide sold-out / disabled items entirely.
      list = list.where((item) => !item.isSoldOut).toList();
    }
    return list;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> fetchAll() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await SupabaseService.client
          .from(SupabaseService.tableMenuItems)
          .select()
          .order('category');

      _items = (response as List)
          .map((json) => MenuItem.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching menu: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  void selectCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  MenuItem? getItemById(String id) {
    try {
      return _items.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }
}
