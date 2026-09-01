import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'bill_calc.dart';

/// Builds a printable HTML invoice for an order and opens it in a new tab,
/// auto-triggering the browser print dialog (so the customer can Save as PDF).
class BillService {
  static Future<void> download(Map<String, dynamic> order) async {
    final b = await BillData.load(order);
    final doc = _build(b);
    final blob = web.Blob(
      [doc.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html'),
    );
    final url = web.URL.createObjectURL(blob);
    web.window.open(url, '_blank');
  }

  static String _money(num v) => '₹${v.toStringAsFixed(2)}';

  static String _build(BillData b) {
    final rows = StringBuffer();
    for (final r in b.rows) {
      rows.write('<tr><td>${r.name}</td><td class="c">${r.qty}</td>'
          '<td class="r">${_money(r.price)}</td>'
          '<td class="r">${_money(r.amount)}</td></tr>');
    }
    final gstLabel =
        b.gstPct % 1 == 0 ? b.gstPct.toStringAsFixed(0) : b.gstPct.toString();

    return '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<title>Bill #${b.orderNo}</title>
<style>
  *{box-sizing:border-box;}
  body{font-family:Arial,Helvetica,sans-serif;color:#111;max-width:480px;margin:16px auto;padding:0 12px;font-size:14px;}
  h1{font-size:18px;margin:0;}
  .muted{color:#666;font-size:11px;}
  .hdr{border-bottom:2px solid #111;padding-bottom:10px;}
  .meta{margin-top:10px;font-size:12px;line-height:1.6;}
  table{width:100%;border-collapse:collapse;margin-top:14px;font-size:12px;}
  th,td{padding:5px 3px;border-bottom:1px solid #eee;text-align:left;word-break:break-word;}
  th{border-bottom:2px solid #111;font-size:11px;}
  .r{text-align:right;} .c{text-align:center;}
  .tot td{border:none;padding:3px 4px;font-size:13px;}
  .grand td{font-weight:bold;font-size:14px;border-top:2px solid #111;padding-top:8px;}
  .foot{margin-top:18px;text-align:center;}
  button{margin-top:18px;padding:10px 18px;background:#111;color:#fff;border:none;cursor:pointer;font-size:13px;border-radius:6px;width:100%;}
  @media print{button{display:none;}}
  @media (max-width:400px){body{padding:0 8px;font-size:13px;} h1{font-size:16px;} table{font-size:11px;} .tot td{font-size:12px;} .grand td{font-size:13px;}}
</style></head><body>
<div class="hdr">
  <h1>${b.business}</h1>
  ${b.address.isNotEmpty ? '<div class="muted">${b.address}</div>' : ''}
  ${b.gstNo.isNotEmpty ? '<div class="muted">GSTIN: ${b.gstNo}</div>' : ''}
</div>
<div class="meta">
  <strong>TAX INVOICE</strong><br>
  Order #${b.orderNo} &nbsp;&middot;&nbsp; ${b.createdAt}<br>
  ${b.custName.isNotEmpty ? '${b.custName} &nbsp;&middot;&nbsp; ${b.custPhone}<br>' : ''}
  Type: ${b.orderType}
</div>
<table>
  <thead><tr><th>Item</th><th class="c">Qty</th><th class="r">Rate</th><th class="r">Amount</th></tr></thead>
  <tbody>$rows</tbody>
</table>
<table class="tot">
  <tr><td>Subtotal</td><td class="r">${_money(b.subtotal)}</td></tr>
  ${b.delivery > 0 ? '<tr><td>Delivery charge</td><td class="r">${_money(b.delivery)}</td></tr>' : ''}
  ${b.gstPct > 0 ? '<tr><td>GST @ $gstLabel%</td><td class="r">${_money(b.gstAmt)}</td></tr>' : ''}
  <tr class="grand"><td>TOTAL</td><td class="r">${_money(b.total)}</td></tr>
</table>
<div class="foot muted">${b.footer}</div>
<button onclick="window.print()">Download / Save as PDF</button>
</body></html>''';
  }
}
