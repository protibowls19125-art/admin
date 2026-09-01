export 'razorpay_models.dart';

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import 'razorpay_models.dart';

/// Typed handle to the global `Razorpay` checkout object (from checkout.js).
@JS('Razorpay')
extension type _RazorpayJS._(JSObject _) implements JSObject {
  external _RazorpayJS(JSObject options);
  external void open();
  external void on(JSString event, JSFunction handler);
}

/// Online-payment flow for the **web** customer app — fully server-driven.
///
///   1. `razorpay-create-order` computes the price from the DB, creates the
///      Razorpay order, and stores a pending order. The client sends only item
///      ids + quantities — never prices.
///   2. Razorpay checkout.js opens for that order (JS interop).
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
    if (!globalContext.has('Razorpay')) {
      return PlaceOrderResult.fail(
          'Payment library not loaded. Please refresh and try again.');
    }

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

    // 2. Open Razorpay checkout for that order.
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

  /// Pays for a subscription PLAN — same server-driven shape as orders:
  ///   1. `subscription-create-order` (price from DB, plan id only),
  ///   2. Razorpay checkout.js,
  ///   3. `subscription-verify-payment` (signature verified server-side).
  /// The returned order/payment ids act as the bearer proof for the
  /// onboarding-details submission that follows.
  Future<SubscriptionPayResult> paySubscription({required String planId}) async {
    if (!globalContext.has('Razorpay')) {
      return SubscriptionPayResult.fail(
          'Payment library not loaded. Please refresh and try again.');
    }

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

  /// Pays for a Gold membership PLAN — same server-driven shape as
  /// subscriptions, but stops after checkout: `gym-membership-activate`
  /// does signature verification + account creation in one call, so there's
  /// no separate verify step here.
  Future<GymMembershipPayResult> payGymMembership({required String planId}) async {
    if (!globalContext.has('Razorpay')) {
      return GymMembershipPayResult.fail(
          'Payment library not loaded. Please refresh and try again.');
    }

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

  /// Detect if running on a mobile browser.
  bool get _isMobile {
    try {
      final ua = globalContext.getProperty('navigator'.toJS) as JSObject?;
      if (ua == null) return false;
      final userAgent = (ua.getProperty('userAgent'.toJS) as JSString?)?.toDart ?? '';
      return RegExp(r'Android|iPhone|iPad|iPod|Opera Mini|IEMobile|WPDesktop', caseSensitive: false)
          .hasMatch(userAgent);
    } catch (_) {
      return false;
    }
  }

  /// Aggressively clean up Razorpay's DOM leftovers and force Flutter to
  /// repaint. Razorpay injects overlay `<div>`s (backdrop, container, iframe)
  /// that can cover the Flutter canvas and freeze the screen black/white.
  void _forceRepaint() {
    try {
      // 1. Remove Razorpay's injected DOM elements that cover the canvas.
      _removeRazorpayOverlays();

      // 2. Reset body overflow — Razorpay sets it to 'hidden'.
      web.document.body?.style.setProperty('overflow', 'auto');

      // 3. Force Flutter canvas repaint via opacity toggle.
      final canvas = web.document.querySelector('flt-glass-pane') ??
          web.document.querySelector('flutter-view');
      if (canvas != null) {
        final el = canvas as web.HTMLElement;
        el.style.setProperty('opacity', '0.99');
        Future.delayed(const Duration(milliseconds: 50), () {
          try { el.style.setProperty('opacity', '1'); } catch (_) {}
        });
      }

      // 4. Dispatch resize events at staggered intervals to ensure
      //    Flutter's rendering pipeline fully recovers.
      web.window.dispatchEvent(web.Event('resize'));
      for (final ms in [50, 150, 300, 600, 1200]) {
        Future.delayed(Duration(milliseconds: ms), () {
          try {
            _removeRazorpayOverlays();
            web.window.dispatchEvent(web.Event('resize'));
          } catch (_) {}
        });
      }
    } catch (_) {}
  }

  /// Remove any Razorpay-injected overlays from the DOM.
  void _removeRazorpayOverlays() {
    try {
      // Razorpay uses these class names / selectors for its overlay.
      for (final selector in [
        '.razorpay-container',
        '.razorpay-backdrop',
        '.razorpay-checkout-frame',
        'iframe[src*="razorpay"]',
        // Fallback: any iframe with razorpay in the name attribute
        'iframe[name*="razorpay"]',
      ]) {
        final elements = web.document.querySelectorAll(selector);
        for (var i = 0; i < elements.length; i++) {
          final node = elements.item(i);
          if (node != null) {
            node.parentNode?.removeChild(node);
          }
        }
      }
    } catch (_) {}
  }

  Future<Map<String, String>?> _openCheckout({
    required String keyId,
    required num amountPaise,
    required String currency,
    required String orderId,
    required String customerName,
    required String customerPhone,
  }) async {
    final completer = Completer<Map<String, String>?>();
    void complete(Map<String, String>? v) {
      if (!completer.isCompleted) completer.complete(v);
    }

    // Listen for visibility changes — when returning from an external UPI
    // app on mobile, the Razorpay dismiss callback may not fire, leaving
    // the canvas covered by the backdrop. This listener catches that.
    void Function(web.Event)? visibilityHandler;
    visibilityHandler = (web.Event _) {
      if (web.document.visibilityState == 'visible') {
        // Delay slightly to let Razorpay's own callbacks fire first.
        Future.delayed(const Duration(milliseconds: 300), () {
          try { _forceRepaint(); } catch (_) {}
        });
      }
    };
    web.document.addEventListener('visibilitychange', visibilityHandler.toJS);

    // Clean up the visibility listener once the checkout completes.
    void cleanup() {
      try {
        web.document.removeEventListener(
            'visibilitychange', visibilityHandler!.toJS);
      } catch (_) {}
    }

    final prefill = JSObject()
      ..setProperty('name'.toJS, customerName.toJS)
      ..setProperty('contact'.toJS, customerPhone.toJS);
    final theme = JSObject()..setProperty('color'.toJS, '#9F402D'.toJS);
    final modal = JSObject()
      ..setProperty('ondismiss'.toJS, (() {
        _forceRepaint();
        cleanup();
        complete(null);
      }).toJS)
      ..setProperty('confirm_close'.toJS, true.toJS)
      ..setProperty('escape'.toJS, false.toJS);

    final options = JSObject()
      ..setProperty('key'.toJS, keyId.toJS)
      ..setProperty('amount'.toJS, amountPaise.toDouble().toJS)
      ..setProperty('currency'.toJS, currency.toJS)
      ..setProperty('name'.toJS, 'Proti Bowls'.toJS)
      ..setProperty('image'.toJS,
          'https://mithunvas86-ui.github.io/protibowl/icons/Icon-512.png'.toJS)
      ..setProperty('description'.toJS, 'Order Payment'.toJS)
      ..setProperty('order_id'.toJS, orderId.toJS)
      ..setProperty('prefill'.toJS, prefill)
      ..setProperty('theme'.toJS, theme)
      ..setProperty('modal'.toJS, modal)
      ..setProperty(
        'handler'.toJS,
        ((JSObject resp) {
          _forceRepaint();
          cleanup();
          String read(String k) =>
              (resp.getProperty(k.toJS) as JSString?)?.toDart ?? '';
          complete({
            'razorpay_payment_id': read('razorpay_payment_id'),
            'razorpay_order_id': read('razorpay_order_id'),
            'razorpay_signature': read('razorpay_signature'),
          });
        }).toJS,
      );

    // On mobile, set retry to true so Razorpay shows a "retry" option
    // instead of closing the checkout when returning from UPI apps.
    if (_isMobile) {
      final retry = JSObject()..setProperty('enabled'.toJS, true.toJS);
      options.setProperty('retry'.toJS, retry);
    }

    final rzp = _RazorpayJS(options);
    rzp.on('payment.failed'.toJS, ((JSObject _) {
      _forceRepaint();
      cleanup();
      complete(null);
    }).toJS);
    rzp.open();
    return completer.future;
  }
}
