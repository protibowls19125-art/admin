import 'package:flutter/material.dart';
import '../models/menu_item.dart';
import '../services/local_storage_service.dart';

class CartItem {
  final MenuItem item;
  int quantity;
  // e.g. "Mild" / "Medium" / "Hot" — chosen on the product page, carried
  // through to the order so the kitchen (KDS) knows how to make it.
  String? spiceLevel;

  CartItem({required this.item, this.quantity = 1, this.spiceLevel});

  double get subtotal => item.price * quantity;

  Map<String, dynamic> toJson() => {
        ...item.toJson(),
        'quantity': quantity,
        if (spiceLevel != null) 'spice_level': spiceLevel,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      item: MenuItem.fromJson(json),
      quantity: (json['quantity'] as int?) ?? 1,
      spiceLevel: json['spice_level'] as String?,
    );
  }
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  final _storage = LocalStorageService();

  List<CartItem> get items => _items;
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);
  double get total => _items.fold(0, (sum, item) => sum + item.subtotal);

  CartProvider() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      await _storage.init();
      final saved = _storage.getCart();
      for (final map in saved) {
        _items.add(CartItem.fromJson(map));
      }
      if (_items.isNotEmpty) notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      await _storage.saveCart(_items.map((e) => e.toJson()).toList());
    } catch (_) {}
  }

  void addItem(MenuItem item, {String? spiceLevel}) {
    final index = _items.indexWhere((i) => i.item.id == item.id);
    if (index > -1) {
      _items[index].quantity++;
      if (spiceLevel != null) _items[index].spiceLevel = spiceLevel;
    } else {
      _items.add(CartItem(item: item, spiceLevel: spiceLevel));
    }
    notifyListeners();
    _persist();
  }

  void removeItem(String itemId) {
    _items.removeWhere((item) => item.item.id == itemId);
    notifyListeners();
    _persist();
  }

  void updateQuantity(String itemId, int quantity) {
    final index = _items.indexWhere((item) => item.item.id == itemId);
    if (index > -1) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      notifyListeners();
      _persist();
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _persist();
  }
}
