import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';

class CustomerInfoProvider extends ChangeNotifier {
  String? _customerId;
  String? _name;
  String? _phone;
  String? _gender;
  String? _preference;
  bool _isLoading = false;
  String? _error;

  String? get customerId => _customerId;
  String? get name => _name;
  String? get phone => _phone;
  String? get gender => _gender;
  String? get preference => _preference;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInfoComplete => _customerId != null;

  Future<bool> submitCustomerInfo({
    required String name,
    required String phone,
    required String gender,
    required String preference,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await SupabaseService.client.functions.invoke(
        'submit-guest-customer',
        body: {
          'name': name,
          'phone': phone,
          'gender': gender,
          'preference': preference,
        },
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['id'] == null) {
        throw Exception(data['error']?.toString() ?? 'Could not save customer info');
      }

      _customerId = data['id'];
      _name = name;
      _phone = phone;
      _gender = gender;
      _preference = preference;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void reset() {
    _customerId = null;
    _name = null;
    _phone = null;
    _gender = null;
    _preference = null;
    _error = null;
    notifyListeners();
  }
}
