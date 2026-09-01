export 'razorpay_models.dart';

import 'razorpay_models.dart';

/// Fallback for platforms that are neither web nor Android/iOS (i.e. desktop,
/// if a build target for one is ever added) — Razorpay has no SDK there.
class RazorpayService {
  Future<PlaceOrderResult> placeOnlineOrder({
    required List<Map<String, dynamic>> items,
    required String customerName,
    required String customerPhone,
    required String orderType,
    Map<String, String>? deliveryAddress,
  }) async =>
      PlaceOrderResult.fail('Online payment is only available on the web');

  Future<SubscriptionPayResult> paySubscription({required String planId}) async =>
      SubscriptionPayResult.fail('Online payment is only available on the web');

  Future<GymMembershipPayResult> payGymMembership(
          {required String planId}) async =>
      GymMembershipPayResult.fail('Online payment is only available on the web');
}
