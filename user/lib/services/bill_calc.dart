import 'supabase_service.dart';

/// One line item on the bill.
class BillRow {
  final String name;
  final int qty;
  final double price;
  BillRow(this.name, this.qty, this.price);
  double get amount => price * qty;
}

/// Computed bill numbers shared by the web (HTML/print) and native
/// (in-app sheet) bill views, so the GST/discount math lives in one place.
class BillData {
  final String business, address, gstNo, footer, orderNo, createdAt;
  final String custName, custPhone, orderType;
  final List<BillRow> rows;
  final double subtotal, delivery, gstPct, gstAmt, total;

  const BillData({
    required this.business,
    required this.address,
    required this.gstNo,
    required this.footer,
    required this.orderNo,
    required this.createdAt,
    required this.custName,
    required this.custPhone,
    required this.orderType,
    required this.rows,
    required this.subtotal,
    required this.delivery,
    required this.gstPct,
    required this.gstAmt,
    required this.total,
  });

  static Future<BillData> load(Map<String, dynamic> order) async {
    Map<String, dynamic> cfg = {};
    try {
      final res = await SupabaseService.client
          .from('app_config')
          .select('value')
          .eq('key', 'bill_config')
          .maybeSingle();
      cfg = (res?['value'] as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) {/* defaults */}

    final items = (order['items'] as List?) ?? const [];
    double subtotal = 0;
    final rows = <BillRow>[];
    for (final it in items) {
      final name = (it['name'] ?? 'Item').toString();
      final qty = (it['quantity'] as num?)?.toInt() ?? 1;
      final price = (it['price'] as num?)?.toDouble() ?? 0;
      subtotal += price * qty;
      rows.add(BillRow(name, qty, price));
    }

    final total = (order['total_price'] as num?)?.toDouble() ?? subtotal;
    final ci = (order['customer_info'] as Map?)?.cast<String, dynamic>() ?? {};

    final goldDiscountPct =
        (ci['gold_discount_percent'] as num?)?.toDouble() ?? 0;
    final discountedSubtotal = subtotal * (1 - goldDiscountPct / 100);

    final double gstPct;
    final double gstAmt;
    if (ci['gst_amount'] != null) {
      // Exact GST charged at checkout (exclusive — added on top).
      gstAmt = (ci['gst_amount'] as num).toDouble();
      gstPct = (ci['gst_percent'] as num?)?.toDouble() ?? 0;
    } else {
      // Legacy order placed before GST was tracked per-order — best-effort
      // estimate from the current config (inclusive, as it used to be charged).
      gstPct = (cfg['gst_percent'] as num?)?.toDouble() ?? 0;
      gstAmt = gstPct > 0 ? total * gstPct / (100 + gstPct) : 0;
    }

    final orderType = (order['order_type'] ?? '').toString();
    final double delivery;
    if (ci['delivery_charge'] != null) {
      // Exact fee charged at checkout.
      delivery = (ci['delivery_charge'] as num).toDouble();
    } else if (orderType == 'delivery') {
      // Per-order charge not recorded — use bill_config as fallback.
      final configCharge = (cfg['delivery_charge'] as num?)?.toDouble() ?? 0;
      if (configCharge > 0) {
        delivery = configCharge;
      } else {
        // Last resort: estimate by subtraction.
        final leftover = total - discountedSubtotal - gstAmt;
        delivery = leftover > 0.01 ? leftover : 0.0;
      }
    } else {
      delivery = 0.0;
    }

    return BillData(
      business: (cfg['business_name'] ?? 'Bill').toString(),
      address: (cfg['address'] ?? '').toString(),
      gstNo: (cfg['gst_number'] ?? '').toString(),
      footer: (cfg['footer'] ?? 'Thank you!').toString(),
      orderNo: (order['id'] ?? '').toString(),
      createdAt: (order['created_at'] ?? '').toString().split('T').first,
      custName: (ci['name'] ?? '').toString(),
      custPhone: (ci['phone'] ?? '').toString(),
      orderType: (order['order_type'] ?? '')
          .toString()
          .replaceAll('_', ' ')
          .toUpperCase(),
      rows: rows,
      subtotal: subtotal,
      delivery: delivery,
      gstPct: gstPct,
      gstAmt: gstAmt,
      total: total,
    );
  }
}
