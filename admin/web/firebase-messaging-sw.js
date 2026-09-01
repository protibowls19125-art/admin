// Background message handler — this is what shows a normal OS notification
// when the admin app tab isn't open. Must live at the web root (not under
// firebase_options.dart) because the browser registers it as a top-level
// service worker script, separate from the Flutter app itself.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBIUCu-97rS7GuHkbdBnjcEVVQ_kBGk6xY',
  authDomain: 'protibowls-3c575.firebaseapp.com',
  projectId: 'protibowls-3c575',
  storageBucket: 'protibowls-3c575.firebasestorage.app',
  messagingSenderId: '1035551222498',
  appId: '1:1035551222498:web:668bc75a3f866fb2b9ccbb',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? 'New order received';
  const body = payload.notification?.body ?? '';
  return self.registration.showNotification(title, {
    body,
    icon: 'logo.png',
  });
});
