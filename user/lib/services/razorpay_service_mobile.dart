export 'razorpay_models.dart';

import 'dart:async';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'razorpay_models.dart';

/// Online-payment flow for the **native (Android/iOS)** customer app — same
/// server-driven shape as the web version (razorpay_service_web.dart), but
/// opens Razorpay's native checkout SDK instead of checkout.js.
///
///   1. `razorpay-create-order` computes the price from the DB, creates the
///      Razorpay order, and stores a pending order. The client sends only item
///      ids + quantities — never prices.
///   2. Razorpay's native checkout opens for that order.
///   3. `razorpay-verify-payment` validates the signature and finalizes the
///      order server-side. Only a verified payment returns success.
class RazorpayService {
  final _supabase = Supabase.instance.client;

  Future<PlaceOrderResult> placeOnlineOrder({
    required List<Map<String, dynamic>> items, // [{menu_item_id, quantity}]
    required String customerName,
    required String customerPhone,
    required String orderType,
    Map<String, String>? deliveryAddress,
  }) async {
    // 1. Server creates the order + Razorpay order (price computed server-side).
    final String razorpayOrderId, keyId, currency;
    final num amountPaise;
    final String? orderNumber, dbOrderId;
    final double? totalPrice;
    final List<Map<String, dynamic>>? lineItems;
    try {
      final res = await _supabase.functions.invoke(
        'razorpay-create-order',
        body: {
          'payment_method': 'online',
          'order_type': orderType,
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'items': items,
          if (deliveryAddress != null) 'delivery_address': deliveryAddress,
        },
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['razorpayOrderId'] == null || data['keyId'] == null) {
        return PlaceOrderResult.fail(
            data['error']?.toString() ?? 'Could not start order');
      }
      razorpayOrderId = data['razorpayOrderId'] as String;
      keyId = data['keyId'] as String;
      amountPaise = (data['amount'] as num?) ?? 0;
      currency = (data['currency'] as String?) ?? 'INR';
      orderNumber = data['orderNumber']?.toString();
      dbOrderId = data['dbOrderId']?.toString();
      totalPrice = (data['totalPrice'] as num?)?.toDouble();
      lineItems = (data['items'] as List?)?.cast<Map<String, dynamic>>();
    } catch (e) {
      return PlaceOrderResult.fail(cleanErrorMessage(e, 'Could not start order'));
    }

    // 2. Open Razorpay's native checkout for that order.
    final payment = await _openCheckout(
      keyId: keyId,
      amountPaise: amountPaise,
      currency: currency,
      orderId: razorpayOrderId,
      customerName: customerName,
      customerPhone: customerPhone,
    );
    if (payment == null) return PlaceOrderResult.fail('Payment cancelled');

    // 3. Server verifies the signature and finalizes the order.
    try {
      final res = await _supabase.functions.invoke(
        'razorpay-verify-payment',
        body: {
          'razorpay_order_id': payment['razorpay_order_id'],
          'razorpay_payment_id': payment['razorpay_payment_id'],
          'razorpay_signature': payment['razorpay_signature'],
        },
      );
      final v = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (v['verified'] == true) {
        return PlaceOrderResult(
          success: true,
          message: 'Payment successful',
          orderNumber: v['orderNumber']?.toString() ?? orderNumber,
          dbOrderId: v['dbOrderId']?.toString() ?? dbOrderId,
          totalPrice: (v['totalPrice'] as num?)?.toDouble() ?? totalPrice,
          items: (v['items'] as List?)?.cast<Map<String, dynamic>>() ?? lineItems,
        );
      }
      return PlaceOrderResult.fail('Payment verification failed');
    } catch (e) {
      return PlaceOrderResult.fail(cleanErrorMessage(e, 'Verification error'));
    }
  }

  Future<SubscriptionPayResult> paySubscription({required String planId}) async {
    final String razorpayOrderId, keyId, currency;
    final num amountPaise;
    try {
      final res = await _supabase.functions.invoke(
        'subscription-create-order',
        body: {'plan_id': planId},
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['razorpayOrderId'] == null || data['keyId'] == null) {
        return SubscriptionPayResult.fail(
            data['error']?.toString() ?? 'Could not start payment');
      }
      razorpayOrderId = data['razorpayOrderId'] as String;
      keyId = data['keyId'] as String;
      amountPaise = (data['amount'] as num?) ?? 0;
      currency = (data['currency'] as String?) ?? 'INR';
    } catch (e) {
      return SubscriptionPayResult.fail(cleanErrorMessage(e, 'Could not start payment'));
    }

    final payment = await _openCheckout(
      keyId: keyId,
      amountPaise: amountPaise,
      currency: currency,
      orderId: razorpayOrderId,
      customerName: '',
      customerPhone: '',
    );
    if (payment == null) return SubscriptionPayResult.fail('Payment cancelled');

    try {
      final res = await _supabase.functions.invoke(
        'subscription-verify-payment',
        body: {
          'razorpay_order_id': payment['razorpay_order_id'],
          'razorpay_payment_id': payment['razorpay_payment_id'],
          'razorpay_signature': payment['razorpay_signature'],
        },
      );
      final v = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (v['verified'] == true) {
        return SubscriptionPayResult(
          success: true,
          message: 'Payment successful',
          subscriptionId: v['subscriptionId']?.toString(),
          razorpayOrderId: payment['razorpay_order_id'],
          razorpayPaymentId: payment['razorpay_payment_id'],
        );
      }
      return SubscriptionPayResult.fail('Payment verification failed');
    } catch (e) {
      return SubscriptionPayResult.fail(cleanErrorMessage(e, 'Verification error'));
    }
  }

  Future<GymMembershipPayResult> payGymMembership({required String planId}) async {
    final String razorpayOrderId, keyId, currency;
    final num amountPaise;
    try {
      final res = await _supabase.functions.invoke(
        'gym-membership-create-order',
        body: {'plan_id': planId},
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['razorpayOrderId'] == null || data['keyId'] == null) {
        return GymMembershipPayResult.fail(
            data['error']?.toString() ?? 'Could not start payment');
      }
      razorpayOrderId = data['razorpayOrderId'] as String;
      keyId = data['keyId'] as String;
      amountPaise = (data['amount'] as num?) ?? 0;
      currency = (data['currency'] as String?) ?? 'INR';
    } catch (e) {
      return GymMembershipPayResult.fail(cleanErrorMessage(e, 'Could not start payment'));
    }

    final payment = await _openCheckout(
      keyId: keyId,
      amountPaise: amountPaise,
      currency: currency,
      orderId: razorpayOrderId,
      customerName: '',
      customerPhone: '',
    );
    if (payment == null) return GymMembershipPayResult.fail('Payment cancelled');

    return GymMembershipPayResult(
      success: true,
      message: 'Payment successful',
      razorpayOrderId: payment['razorpay_order_id'],
      razorpayPaymentId: payment['razorpay_payment_id'],
      razorpaySignature: payment['razorpay_signature'],
    );
  }

  Future<Map<String, String>?> _openCheckout({
    required String keyId,
    required num amountPaise,
    required String currency,
    required String orderId,
    required String customerName,
    required String customerPhone,
  }) async {
    final razorpay = Razorpay();
    final completer = Completer<Map<String, String>?>();
    void complete(Map<String, String>? v) {
      if (!completer.isCompleted) completer.complete(v);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      complete({
        'razorpay_payment_id': r.paymentId ?? '',
        'razorpay_order_id': r.orderId ?? '',
        'razorpay_signature': r.signature ?? '',
      });
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse _) {
      complete(null); // includes user-cancelled
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) {
      complete(null); // unhandled external wallet — surfaces as "cancelled"
    });

    razorpay.open({
      'key': keyId,
      'amount': amountPaise.toInt(),
      'currency': currency,
      'name': 'Proti Bowls',
      'order_id': orderId,
      'description': 'Order Payment',
      'theme': {'color': '#9F402D'},
      if (customerName.isNotEmpty || customerPhone.isNotEmpty)
        'prefill': {
          if (customerName.isNotEmpty) 'name': customerName,
          if (customerPhone.isNotEmpty) 'contact': customerPhone,
        },
    });

    final result = await completer.future;
    razorpay.clear();
    return result;
  }
}
