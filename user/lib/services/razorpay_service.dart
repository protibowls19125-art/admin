// Online-payment flow — web uses Razorpay checkout.js (JS interop);
// Android/iOS use the native razorpay_flutter SDK; anything else (desktop)
// falls back to a stub that reports payment as unavailable. See
// razorpay_service_web.dart / razorpay_service_mobile.dart /
// razorpay_service_stub.dart.
export 'razorpay_service_stub.dart'
    if (dart.library.js_interop) 'razorpay_service_web.dart'
    if (dart.library.io) 'razorpay_service_mobile.dart';
