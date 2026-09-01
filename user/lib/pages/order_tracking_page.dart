import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/order_provider.dart';
import '../services/bill_service.dart';
import 'bill_sheet.dart';
import '../theme/bauhaus_theme.dart';
import 'package:go_router/go_router.dart';

class OrderTrackingPage extends StatefulWidget {
  const OrderTrackingPage({super.key});

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    context.read<OrderProvider>().fetchOrders();
    // Poll Supabase every 10 seconds for live status updates
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<OrderProvider>().fetchOrders();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Any back action (system/browser back, swipe) goes Home, not back
      // through the order/confirmation flow.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: BauhausTheme.primaryBlack),
          tooltip: 'Home',
          onPressed: () => context.go('/'),
        ),
        title: Text(
          'My Orders',
          style: BauhausTheme.heading(size: 22, weight: FontWeight.w700),
        ),
        backgroundColor: BauhausTheme.background,
        elevation: 0,
      ),
      body: Consumer<OrderProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.orders.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => context.read<OrderProvider>().fetchOrders(),
              color: BauhausTheme.primaryBlack,
              child: ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_outlined,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'NO ORDERS YET',
                          style: GoogleFonts.inter(
                              fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pull down to refresh',
                          style: GoogleFonts.inter(
                              fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => context.read<OrderProvider>().fetchOrders(),
            color: BauhausTheme.primaryBlack,
            child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.orders.length,
            itemBuilder: (context, index) {
              final order = provider.orders[index];
              final items =
                  (order['items'] ?? order['order_items'] ?? []) as List;
              final status = order['status'] ?? 'pending';
              final statusColor = _getStatusColor(status);
              final statusLabel = status == 'awaiting_payment'
                  ? 'YOUR ORDER IS IN WAITING'
                  : status.toString().toUpperCase();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: BauhausTheme.white,
                  borderRadius: BorderRadius.circular(BauhausTheme.radiusLg),
                  boxShadow: BauhausTheme.cardShadow,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #${order['id'].toString().toUpperCase()}',
                                style: BauhausTheme.heading(
                                    size: 16, weight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(
                                      BauhausTheme.radiusPill),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '₹${order['total_price']}',
                            style: BauhausTheme.body(
                              size: 18,
                              weight: FontWeight.w600,
                              color: BauhausTheme.accentRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                        height: 1,
                        thickness: 1,
                        color: BauhausTheme.patternGrey),
                    // Items
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...items.map((item) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${item['quantity']}x Item - ₹${item['price']}',
                                style: GoogleFonts.inter(fontSize: 12),
                              ),
                            );
                          }),
                          if (order['special_instructions']?.isNotEmpty ??
                              false) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: BauhausTheme.lightGrey,
                                borderRadius: BorderRadius.circular(
                                    BauhausTheme.radiusSm),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'NOTES',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    order['special_instructions'],
                                    style: GoogleFonts.inter(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // No bill for a cancelled order — nothing was
                          // actually fulfilled or charged to invoice. Same
                          // for one still awaiting payment — nothing's been
                          // charged yet either.
                          if (status != 'cancelled' &&
                              status != 'awaiting_payment') ...[
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () => kIsWeb
                                  ? BillService.download(order)
                                  : showBillSheet(context, order),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                      BauhausTheme.radiusMd),
                                  border: Border.all(
                                      color: BauhausTheme.primaryBlack,
                                      width: 1),
                                ),
                                child: Center(
                                  child: Text(
                                    kIsWeb ? 'DOWNLOAD E-BILL' : 'VIEW E-BILL',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: BauhausTheme.primaryBlack,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          // Cancel button — only before the kitchen confirms.
                          if (status == 'pending') ...[
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () => _cancelOrder(context, order),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                      BauhausTheme.radiusMd),
                                  border: Border.all(
                                      color: Colors.red[700]!, width: 1),
                                ),
                                child: Center(
                                  child: Text(
                                    'CANCEL ORDER',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.red[700],
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          );
        },
      ),
      ),
    );
  }

  Future<void> _cancelOrder(
      BuildContext context, Map<String, dynamic> order) async {
    final orderId = order['id'].toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'CANCEL ORDER',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to cancel order #${orderId.toUpperCase()}?',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('NO', style: GoogleFonts.inter(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('YES, CANCEL',
                style: GoogleFonts.inter(
                    color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // null = cancelled successfully; otherwise an honest, specific reason
      // from the server (e.g. already being prepared) — never a fake success.
      final error = await context.read<OrderProvider>().cancelOrder(order);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error ?? 'Order cancelled.',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: error == null ? Colors.black : Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'awaiting_payment':
        return Colors.amber[800]!;
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return const Color(0xFF1565C0); // dark blue
      case 'preparing':
        return const Color(0xFF6A1B9A); // purple
      case 'ready':
        return const Color(0xFF2E7D32); // dark green
      case 'completed':
        return const Color(0xFF1B5E20); // deep green
      case 'cancelled':
        return Colors.red[700]!;
      default:
        return Colors.grey[700]!;
    }
  }
}
