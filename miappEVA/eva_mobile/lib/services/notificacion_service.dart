import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/alarma_local.dart';
import 'alarmas_local_service.dart';

class NotificacionService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static const String _channelId = 'eva_alarmas';
  static const String _channelName = 'Alarmas EVA';
  static const String _channelDescription = 'Canal de alarmas reales de EVA';

  static Future<void> inicializar() async {
    tz.initializeTimeZones();

    try {
      final String timezoneName = await FlutterTimezone.getLocalTimezone();
      print('Zona detectada por flutter_timezone: $timezoneName');

      try {
        tz.setLocalLocation(tz.getLocation(timezoneName));
        print('Zona aplicada directamente: $timezoneName');
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
        print('Zona forzada: America/Mexico_City');
      }
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Mexico_City'));
      print('No se detectó zona, usando America/Mexico_City');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    const settings = InitializationSettings(
      android: android,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('alarma_eva'),
      ),
    );
  }

  static NotificationDetails _notificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarma_eva'),
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'tomada',
          'Tomada',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'posponer',
          'Posponer 5 min',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    return const NotificationDetails(android: androidDetails);
  }

  static Future<void> mostrarNotificacionInstantanea({
    required String titulo,
    required String cuerpo,
  }) async {
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      titulo,
      cuerpo,
      _notificationDetails(),
    );
  }

  static Future<void> _onNotificationResponse(
    NotificationResponse response,
  ) async {
    final payload = response.payload;
    final actionId = response.actionId;

    if (payload == null || payload.isEmpty) return;

    final alarmaId = int.tryParse(payload);
    if (alarmaId == null) return;

    if (actionId == 'tomada') {
      await AlarmasLocalService.marcarComoTomada(alarmaId);
      return;
    }

    if (actionId == 'posponer') {
      await AlarmasLocalService.posponer5Min(alarmaId);
      return;
    }
  }

  static Future<void> programarAlarmaLocal(AlarmaLocal alarma) async {
    if (!alarma.activa) return;

    if (alarma.esRecurrente) {
      for (final dia in alarma.diasSemana) {
        final int notificationId = _notificationIdRecurrente(alarma.id, dia);
        final tz.TZDateTime firstDate = _nextInstanceOfWeekday(
          dia,
          alarma.hour,
          alarma.minute,
        );

        if (!firstDate.isAfter(tz.TZDateTime.now(tz.local))) {
          print('Recurrente descartada por fecha pasada: $firstDate');
          continue;
        }

        print(
          'Programando recurrente -> id=$notificationId fecha=$firstDate mensaje=${alarma.mensaje}',
        );

        await _plugin.zonedSchedule(
          notificationId,
          'EVA',
          alarma.mensaje,
          firstDate,
          _notificationDetails(),
          payload: alarma.id.toString(),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
      return;
    }

    final tz.TZDateTime fechaProgramada = _buildOneShotDateTime(alarma);
    final now = tz.TZDateTime.now(tz.local);

    if (!fechaProgramada.isAfter(now)) {
      print('OneShot descartada por fecha pasada: $fechaProgramada');
      return;
    }

    print(
      'Programando una sola vez -> id=${alarma.id} fecha=$fechaProgramada mensaje=${alarma.mensaje}',
    );

    await _plugin.zonedSchedule(
      alarma.id,
      'EVA',
      alarma.mensaje,
      fechaProgramada,
      _notificationDetails(),
      payload: alarma.id.toString(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    final pendientes = await _plugin.pendingNotificationRequests();
    print('Notificaciones pendientes: ${pendientes.length}');
    for (final p in pendientes) {
      print('Pendiente -> id=${p.id}, title=${p.title}, body=${p.body}');
    }
  }

  static Future<void> cancelarAlarmaLocal(AlarmaLocal alarma) async {
    if (alarma.esRecurrente) {
      for (final dia in alarma.diasSemana) {
        await _plugin.cancel(_notificationIdRecurrente(alarma.id, dia));
      }
      return;
    }

    await _plugin.cancel(alarma.id);
  }

  static Future<void> cancelarTodas() async {
    await _plugin.cancelAll();
  }

  static tz.TZDateTime _buildOneShotDateTime(AlarmaLocal alarma) {
    final now = tz.TZDateTime.now(tz.local);

    if (alarma.fechaIso != null && alarma.fechaIso!.isNotEmpty) {
      final fecha = DateTime.parse(alarma.fechaIso!);
      final dt = tz.TZDateTime(
        tz.local,
        fecha.year,
        fecha.month,
        fecha.day,
        alarma.hour,
        alarma.minute,
      );
      print('OneShot con fecha fija -> now=$now programada=$dt');
      return dt;
    }

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      alarma.hour,
      alarma.minute,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    print('OneShot sin fecha fija -> now=$now programada=$scheduled');
    return scheduled;
  }

  static tz.TZDateTime _nextInstanceOfWeekday(
    int weekday,
    int hour,
    int minute,
  ) {
    final now = tz.TZDateTime.now(tz.local);

    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  static int _notificationIdRecurrente(int alarmaId, int weekday) {
    final base = alarmaId.remainder(100000000);
    return base * 10 + weekday;
  }
}