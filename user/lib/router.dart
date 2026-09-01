import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'pages/home_page.dart';
import 'pages/product_detail_page.dart';
import 'pages/order_form_page.dart';
import 'pages/confirmation_page.dart';
import 'pages/orders_page.dart';
import 'pages/order_tracking_page.dart';
import 'pages/customer_info_page.dart';
import 'pages/faq_page.dart';
import 'pages/subscription_page.dart';
import 'pages/subscription_onboarding_page.dart';
import 'pages/member_page.dart';
import 'pages/member_chooser_page.dart';
import 'pages/gold_membership_page.dart';
import 'providers/customer_info_provider.dart';

String? _redirectLogic(BuildContext context, GoRouterState state) {
  final customerInfo = context.read<CustomerInfoProvider>();

  // Redirect away from customer-info if already filled
  if (customerInfo.isInfoComplete && state.matchedLocation == '/customer-info') {
    return '/';
  }

  return null;
}

final router = GoRouter(
  // Force home page on every reload — the user expects to land on the menu,
  // not whichever route was last visited (e.g. /order or /confirmation).
  initialLocation: '/',
  redirect: _redirectLogic,
  routes: [
    GoRoute(
      path: '/customer-info',
      builder: (context, state) => const CustomerInfoPage(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: '/menu',
      builder: (context, state) => const HomePage(initialTab: 1),
    ),
    GoRoute(
      path: '/product/:id',
      builder: (context, state) => ProductDetailPage(
        itemId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/order',
      builder: (context, state) => const OrderFormPage(),
    ),
    GoRoute(
      path: '/confirmation',
      builder: (context, state) {
        final orderId = state.uri.queryParameters['orderId'] ?? '';
        return ConfirmationPage(orderId: orderId);
      },
    ),
    GoRoute(
      path: '/orders',
      builder: (context, state) => const OrdersPage(),
    ),
    GoRoute(
      path: '/my-orders',
      builder: (context, state) => const OrderTrackingPage(),
    ),
    GoRoute(
      path: '/faq',
      builder: (context, state) => const FaqPage(),
    ),
    GoRoute(
      path: '/subscribe',
      builder: (context, state) => const SubscriptionPage(),
    ),
    GoRoute(
      path: '/subscribe/details',
      builder: (context, state) => const SubscriptionOnboardingPage(),
    ),
    GoRoute(
      path: '/member',
      builder: (context, state) => const MemberChooserPage(),
    ),
    GoRoute(
      path: '/member/gold',
      builder: (context, state) => const GoldMembershipPage(),
    ),
    GoRoute(
      path: '/member/elite',
      builder: (context, state) => const MemberPage(),
    ),
  ],
);
