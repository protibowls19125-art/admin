// ponytail: mobile/desktop have no equivalent to opening a browser print
// dialog; the "Download Bill" button is hidden with kIsWeb so this never
// actually runs. Add a PDF share flow (e.g. package:printing) if needed.
class BillService {
  static Future<void> download(Map<String, dynamic> order) async {}
}
