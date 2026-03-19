import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;

  static Future<void> inicializar() async {
    if (_initialized) return;

    await _tts.setSharedInstance(true);
    await _tts.awaitSpeakCompletion(true);
    final langResult = await _tts.setLanguage('es-MX');
    if (langResult != 1) {
      await _tts.setLanguage('es-ES');
    }
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _initialized = true;
  }

  static Future<bool> hablar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty) return false;

    await inicializar();
    await _tts.stop();
    final result = await _tts.speak(limpio);
    return result == 1;
  }

  static Future<void> detener() async {
    await _tts.stop();
  }
}
