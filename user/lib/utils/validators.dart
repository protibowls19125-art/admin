/// Shared customer-details validation — used by both checkout entry points
/// (order_form_page.dart's full form and product_detail_page.dart's quick
/// "Buy Now" dialog) so the rules can't drift between the two.
library;

final _nameRegex = RegExp(r'^[a-zA-Z ]{2,}$');
final _phoneRegex = RegExp(r'^\d{10}$');

/// Null when valid, otherwise a user-facing error message.
String? validateName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Please enter your name';
  if (!_nameRegex.hasMatch(trimmed)) {
    return 'Name should only contain letters (at least 2 characters)';
  }
  return null;
}

/// Null when valid, otherwise a user-facing error message. Rejects a valid
/// 10-digit number where every digit repeats (e.g. 1111111111) — not a real
/// phone number, just filler someone typed to get past the length check.
String? validatePhone(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Please enter phone number';
  if (!_phoneRegex.hasMatch(trimmed)) {
    return 'Enter a valid 10-digit phone number';
  }
  if (trimmed.split('').toSet().length == 1) {
    return 'Enter a valid phone number';
  }
  return null;
}
