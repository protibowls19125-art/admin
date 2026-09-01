import 'package:supabase_flutter/supabase_flutter.dart';

/// A server rejection (FunctionException) carries its own customer-facing
/// message in `details.error` — surface just that, not the raw exception
/// dump (status code, reason phrase, etc.) that `e.toString()` produces.
String cleanErrorMessage(Object e, [String fallback = 'Something went wrong']) {
  if (e is FunctionException) {
    final detail = (e.details as Map?)?['error']?.toString();
    if (detail != null && detail.isNotEmpty) return detail;
  }
  return fallback;
}

/// Result of placing an online order (create → pay → verify).
class PlaceOrderResult {
  final bool success;
  final String message;
  final String? orderNumber;
  final String? dbOrderId;
  final double? totalPrice;
  final List<Map<String, dynamic>>? items;

  const PlaceOrderResult({
    required this.success,
    required this.message,
    this.orderNumber,
    this.dbOrderId,
    this.totalPrice,
    this.items,
  });

  factory PlaceOrderResult.fail(String message) =>
      PlaceOrderResult(success: false, message: message);
}

/// Result of paying for a subscription plan (create → pay → verify).
class SubscriptionPayResult {
  final bool success;
  final String message;
  final String? subscriptionId;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;

  const SubscriptionPayResult({
    required this.success,
    required this.message,
    this.subscriptionId,
    this.razorpayOrderId,
    this.razorpayPaymentId,
  });

  factory SubscriptionPayResult.fail(String message) =>
      SubscriptionPayResult(success: false, message: message);
}

/// Result of paying for a Gold membership plan (create → pay only — unlike
/// subscriptions, signature verification happens inside
/// `gym-membership-activate` together with account creation, so the raw
/// Razorpay ids are handed back unverified for that one call to consume).
class GymMembershipPayResult {
  final bool success;
  final String message;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? razorpaySignature;

  const GymMembershipPayResult({
    required this.success,
    required this.message,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.razorpaySignature,
  });

  factory GymMembershipPayResult.fail(String message) =>
      GymMembershipPayResult(success: false, message: message);
}
