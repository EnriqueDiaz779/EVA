import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';

class AlarmaNativaService {
  static Future<void> crearAlarmaEnReloj({
    required int hour,
    required int minute,
    required String mensaje,
  }) async {
    if (!Platform.isAndroid) {
      throw Exception('Esta función solo está disponible en Android.');
    }

    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE': mensaje,
        // false = muestra la pantalla de reloj para confirmación
        'android.intent.extra.alarm.SKIP_UI': false,
      },
    );

    await intent.launch();
  }
}