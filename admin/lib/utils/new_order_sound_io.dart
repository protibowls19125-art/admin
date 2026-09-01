import 'package:audioplayers/audioplayers.dart';

class NewOrderSound {
  final AudioPlayer _player = AudioPlayer();

  void play({bool loop = false}) {
    _player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    _player.play(AssetSource('sounds/new-order.mp3'));
  }

  void stop() {
    _player.stop();
  }
}
