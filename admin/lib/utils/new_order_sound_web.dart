import 'package:web/web.dart' as web;
import 'dart:js_interop';

/// Browser-compatible notification sound. Handles the autoplay-policy issue
/// that causes Chrome/Edge/Firefox to silently reject `audio.play()` when the
/// page hasn't received a user gesture yet.
///
/// Strategy: the actual play() call awaits the JS Promise and catches the
/// rejection so it logs a warning instead of silently failing. The KDS page
/// user will have already clicked (login/navigation) before the first order
/// arrives, so autoplay is generally unlocked by then.
class NewOrderSound {
  final web.HTMLAudioElement _audio = web.HTMLAudioElement()
    ..src = 'sounds/new-order.mp3'
    ..preload = 'auto';

  bool _isPlaying = false;

  void play({bool loop = false}) {
    _isPlaying = true;
    _audio.loop = loop;
    _audio.currentTime = 0;
    // play() returns a JS Promise — must await it to catch autoplay rejection.
    // Without .toDart.catchError, the rejected promise is unhandled and the
    // sound just silently doesn't play (no error, no crash, no clue).
    _audio.play().toDart.then((_) {
      // If stop() was called while the play() promise was resolving, pause immediately
      if (!_isPlaying) {
        _audio.pause();
        _audio.currentTime = 0;
      }
    }).catchError((e) {
      web.console.warn(
          'New-order sound blocked by autoplay policy — tap anywhere to unlock: $e'
              .toJS);
      return null;
    });
  }

  void stop() {
    _isPlaying = false;
    _audio.loop = false;
    _audio.pause();
    _audio.currentTime = 0;
  }
}
