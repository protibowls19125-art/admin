// Printable HTML invoice — opens a browser tab and triggers window.print(),
// so the real implementation is web-only. Other platforms get a no-op stub;
// callers should gate the "Download Bill" action behind kIsWeb.
export 'bill_service_stub.dart'
    if (dart.library.js_interop) 'bill_service_web.dart';
