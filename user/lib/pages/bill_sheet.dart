import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/bill_calc.dart';
import '../theme/bauhaus_theme.dart';

/// Native e-bill view for mobile/desktop — the web app opens a printable
/// HTML invoice in a new tab instead (see BillService), which has no
/// equivalent outside a browser.
Future<void> showBillSheet(BuildContext context, Map<String, dynamic> order) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: BauhausTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) => FutureBuilder<BillData>(
        future: BillData.load(order),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final b = snap.data!;
          String money(num v) => '₹${v.toStringAsFixed(2)}';
          final gstLabel = b.gstPct % 1 == 0
              ? b.gstPct.toStringAsFixed(0)
              : b.gstPct.toString();

          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text(b.business,
                  style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              if (b.address.isNotEmpty)
                Text(b.address,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: BauhausTheme.mediumGrey)),
              if (b.gstNo.isNotEmpty)
                Text('GSTIN: ${b.gstNo}',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: BauhausTheme.mediumGrey)),
              const Divider(height: 28),
              Text('Order #${b.orderNo}  ·  ${b.createdAt}',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w700)),
              if (b.custName.isNotEmpty)
                Text('${b.custName} · ${b.custPhone}',
                    style: GoogleFonts.inter(fontSize: 12)),
              Text(b.orderType, style: GoogleFonts.inter(fontSize: 12)),
              const SizedBox(height: 16),
              ...b.rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('${r.name}  x${r.qty}',
                              style: GoogleFonts.inter(fontSize: 12)),
                        ),
                        Text(money(r.amount),
                            style: GoogleFonts.inter(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  )),
              const Divider(height: 28),
              _row('Subtotal', money(b.subtotal)),
              if (b.delivery > 0) _row('Delivery charge', money(b.delivery)),
              if (b.gstPct > 0) _row('GST @ $gstLabel%', money(b.gstAmt)),
              const Divider(height: 16),
              _row('TOTAL', money(b.total), bold: true),
              const SizedBox(height: 20),
              Text(b.footer,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: BauhausTheme.mediumGrey)),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    ),
  );
}

Widget _row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: bold ? 15 : 12,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: bold ? 15 : 12,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
