import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../services/bill_service.dart';
import '../services/local_storage_service.dart';
import '../services/order_api_service.dart';
import '../theme/bauhaus_theme.dart';
import '../widgets/bauhaus_button.dart';
import '../widgets/status_animation.dart';
import 'bill_sheet.dart';

class ConfirmationPage extends StatefulWidget {
  final String orderId;
  const ConfirmationPage({super.key, required this.orderId});

  @override
  State<ConfirmationPage> createState() => _ConfirmationPageState();
}

class _ConfirmationPageState extends State<ConfirmationPage> {
  final _localStorage = LocalStorageService();
  final _apiService = UserOrderAPIService();
  @override
  void initState() {
    super.initState();
    _submitOrderToAPI();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _submitOrderToAPI() async {
    try {
      final order = _localStorage.getCurrentOrder();
      if (order == null) return;

      final customerInfo = order['customer_info'] ?? {};
      final items = order['items'] ?? [];

      final orderRequest = OrderAPIRequest(
        orderId: widget.orderId,
        customerName: customerInfo['name'] ?? 'Guest',
        customerPhone: customerInfo['phone'],
        customerEmail: customerInfo['email'],
        orderType: order['order_type'] ?? 'DINE_IN',
        items: items
            .map<OrderItemData>((item) => OrderItemData(
                  name: item['name'] ?? 'Item',
                  price: (item['price'] as num).toDouble(),
                  quantity: item['quantity'] as int,
                  notes: item['notes'],
                ))
            .toList(),
        totalAmount: (order['total_price'] as num).toDouble(),
        specialNotes: order['special_notes'],
      );

      final result = await _apiService.submitOrder(orderRequest);

      // Result logged but not displayed — the confirmation page no longer
      // shows API submission status to the customer.
      if (result['success'] != true) {
        debugPrint('API submission error: ${result['error']}');
      }
    } catch (e) {
      debugPrint('API submission error: $e');
    }
  }

  Map<String, dynamic>? _getOrderDetails() {
    try {
      final order = _localStorage.getCurrentOrder();
      return order;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/my-orders');
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          'Order Confirmed',
          style: BauhausTheme.heading(size: 22, weight: FontWeight.w700),
        ),
        backgroundColor: BauhausTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/my-orders'),
        ),
      ),
      body: Builder(
        builder: (context) {
          final order = _getOrderDetails();

          if (order == null || order.isEmpty) {
            return Center(
              child: Text(
                'Order #${widget.orderId}',
                style: GoogleFonts.inter(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
            );
          }

          final items = order['items'] ?? [];
          final customerInfo = order['customer_info'] ?? {};
          final totalPrice = order['total_price'] ?? 0;
          final orderType = order['order_type'] ?? 'N/A';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Success Badge
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(BauhausTheme.radiusLg),
                  ),
                  child: Column(
                    children: [
                      const StatusAnimation(success: true, size: 76),
                      const SizedBox(height: 12),
                      Text(
                        'Your Order is Confirmed',
                        style: BauhausTheme.heading(
                            size: 22, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Thank you — your order is on its way to the kitchen.',
                        textAlign: TextAlign.center,
                        style: BauhausTheme.body(
                            size: 13, color: BauhausTheme.mediumGrey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Order ID
                Text(
                  'ORDER NUMBER',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BauhausTheme.mediumGrey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: BauhausTheme.patternGrey, width: 1),
                    borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
                    color: BauhausTheme.lightGrey,
                  ),
                  child: Text(
                    '#${widget.orderId}',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: BauhausTheme.primaryBlack,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Customer Info
                Text(
                  'CUSTOMER DETAILS',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BauhausTheme.mediumGrey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: BauhausTheme.patternGrey, width: 1),
                    borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Name:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BauhausTheme.mediumGrey,
                            ),
                          ),
                          Text(
                            customerInfo['name'] ?? 'N/A',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BauhausTheme.primaryBlack,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Phone:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BauhausTheme.mediumGrey,
                            ),
                          ),
                          Text(
                            customerInfo['phone'] ?? 'N/A',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BauhausTheme.primaryBlack,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Order Type:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BauhausTheme.mediumGrey,
                            ),
                          ),
                          Text(
                            orderType
                                .toString()
                                .replaceAll('_', ' ')
                                .toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BauhausTheme.accentRed,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Order Items
                Text(
                  'ORDER DETAILS',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BauhausTheme.mediumGrey,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: BauhausTheme.patternGrey, width: 1),
                    borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
                  ),
                  child: items.isNotEmpty
                      ? Column(
                          children: [
                            ...List.generate(
                              items.length,
                              (index) {
                                final item =
                                    items[index] as Map<String, dynamic>;
                                final isLast = index == items.length - 1;
                                final itemName = item['name'] ?? 'Item';
                                final itemPrice =
                                    (item['price'] as num).toDouble();
                                final itemQty = item['quantity'] as int;

                                return Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  itemName,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: BauhausTheme
                                                        .primaryBlack,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '₹${(itemPrice * itemQty).toStringAsFixed(0)}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  color: BauhausTheme.accentRed,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'x$itemQty @ ₹${itemPrice.toStringAsFixed(0)}',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                              color: BauhausTheme.mediumGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isLast)
                                      const Divider(
                                        color: BauhausTheme.patternGrey, thickness: 1,
                                        height: 0,
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'No items in order',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: BauhausTheme.mediumGrey,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 24),

                // Total
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: BauhausTheme.white,
                    borderRadius:
                        BorderRadius.circular(BauhausTheme.radiusLg),
                    boxShadow: BauhausTheme.cardShadow,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total Amount',
                        style: BauhausTheme.heading(
                            size: 20, weight: FontWeight.w700),
                      ),
                      Text(
                        '₹${totalPrice.toStringAsFixed(0)}',
                        style: BauhausTheme.body(
                          size: 24,
                          weight: FontWeight.w600,
                          color: BauhausTheme.accentRed,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // E-Bill Button
                GestureDetector(
                  onTap: () {
                    final billOrder = _getOrderDetails();
                    if (billOrder != null) {
                      kIsWeb
                          ? BillService.download(billOrder)
                          : showBillSheet(context, billOrder);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(BauhausTheme.radiusMd),
                      border: Border.all(
                          color: BauhausTheme.primaryBlack, width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long,
                            size: 18, color: BauhausTheme.primaryBlack),
                        const SizedBox(width: 8),
                        Text(
                          kIsWeb ? 'DOWNLOAD E-BILL' : 'VIEW E-BILL',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: BauhausTheme.primaryBlack,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),


                // Action Buttons
                BauhausButton(
                  label: 'VIEW YOUR ORDERS',
                  onPressed: () => context.go('/my-orders'),
                  height: 48,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => context.go('/'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: BauhausTheme.patternGrey, width: 1),
                    borderRadius: BorderRadius.circular(BauhausTheme.radiusMd),
                      color: BauhausTheme.white,
                    ),
                    child: Text(
                      'CONTINUE SHOPPING',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: BauhausTheme.primaryBlack,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/faq'),
                    child: Text(
                      'Payment or order issue?  Help & FAQ',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BauhausTheme.mediumGrey,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
    );
  }
}
