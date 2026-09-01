import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase config for the admin app — web only (this app never ships as a
/// native build, see PROJECT_INDEX/06_DEPLOYMENT.md), so there's just the
/// one platform, hand-written from the Firebase console instead of running
/// `flutterfire configure`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBIUCu-97rS7GuHkbdBnjcEVVQ_kBGk6xY',
    authDomain: 'protibowls-3c575.firebaseapp.com',
    projectId: 'protibowls-3c575',
    storageBucket: 'protibowls-3c575.firebasestorage.app',
    messagingSenderId: '1035551222498',
    appId: '1:1035551222498:web:668bc75a3f866fb2b9ccbb',
    measurementId: 'G-CEHZY39NPX',
  );
}
