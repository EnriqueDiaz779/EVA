import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/alarma_local.dart';
import 'alarmas_local_service.dart';

class NotificacionService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static const String _channelId = 'eva_alarmas';
  static const String _channelName = 'Alarmas EVA';
  static const String _channelDescription = 'Canal de alarmas reales de EVA';

  static const String _emergencyChannelId = 'eva_emergencias_v2';
  static const String _emergencyChannelName = 'Emergencias EVA';
  static const String _emergencyChannelDescription =
      'Canal de emergencias SOS de EVA';

  static const String _chatChannelId = 'eva_chat';
  static const String _chatChannelName = 'Mensajes EVA';
  static const String _chatChannelDescription =
      'Canal para mensajes nuevos del chat de EVA';

  static const String _attentionChannelId = 'eva_alertas_cuidador';
  static const String _attentionChannelName = 'Alertas de seguimiento EVA';
  static const String _attentionChannelDescription =
      'Canal para alertas de seguimiento del cuidador';

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

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _emergencyChannelId,
        _emergencyChannelName,
        description: _emergencyChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('emergencia_sos'),
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _chatChannelId,
        _chatChannelName,
        description: _chatChannelDescription,
        importance: Importance.high,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _attentionChannelId,
        _attentionChannelName,
        description: _attentionChannelDescription,
        importance: Importance.high,
      ),
    );

    _initialized = true;
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

  static NotificationDetails _emergencyNotificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _emergencyChannelId,
      _emergencyChannelName,
      channelDescription: _emergencyChannelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('emergencia_sos'),
      enableVibration: true,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    return const NotificationDetails(android: androidDetails);
  }

  static NotificationDetails _chatNotificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _chatChannelId,
      _chatChannelName,
      channelDescription: _chatChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      category: AndroidNotificationCategory.message,
    );

    return const NotificationDetails(android: androidDetails);
  }

  static NotificationDetails _attentionNotificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _attentionChannelId,
      _attentionChannelName,
      channelDescription: _attentionChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      category: AndroidNotificationCategory.status,
    );

    return const NotificationDetails(android: androidDetails);
  }

  static Future<void> mostrarNotificacionInstantanea({
    required String titulo,
    required String cuerpo,
  }) async {
    if (!await asegurarPermisoNotificaciones()) return;
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      titulo,
      cuerpo,
      _notificationDetails(),
    );
  }

  static Future<void> mostrarNotificacionEmergencia({
    required int id,
    required String titulo,
    required String cuerpo,
  }) async {
    if (!await asegurarPermisoNotificaciones()) return;
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      _emergencyNotificationDetails(),
    );
  }

  static Future<void> mostrarNotificacionChat({
    required int id,
    required String titulo,
    required String cuerpo,
  }) async {
    if (!await asegurarPermisoNotificaciones()) return;
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      _chatNotificationDetails(),
      payload: 'chat:$id',
    );
  }

  static Future<void> mostrarNotificacionMensajeParaAdulto({
    required int id,
    required String cuerpo,
  }) async {
    await mostrarNotificacionChat(
      id: id,
      titulo: 'Nuevo mensaje de tu cuidador',
      cuerpo: cuerpo.trim().isEmpty
          ? 'Tu cuidador te envio un mensaje nuevo.'
          : cuerpo,
    );
  }

  static Future<void> mostrarNotificacionMensajeParaCuidador({
    required int id,
    required String cuerpo,
  }) async {
    await mostrarNotificacionChat(
      id: id,
      titulo: 'Nuevo mensaje del adulto mayor',
      cuerpo: cuerpo.trim().isEmpty
          ? 'El adulto mayor te envio un mensaje nuevo.'
          : cuerpo,
    );
  }

  static Future<void> mostrarNotificacionAtencion({
    required int id,
    required String titulo,
    required String cuerpo,
  }) async {
    if (!await asegurarPermisoNotificaciones()) return;
    await _plugin.show(
      id,
      titulo,
      cuerpo,
      _attentionNotificationDetails(),
      payload: 'attention:$id',
    );
  }

  static Future<void> mostrarNotificacionSinSenal({
    required int id,
    required String nombreAdulto,
  }) async {
    final nombre = nombreAdulto.trim();
    await mostrarNotificacionAtencion(
      id: id,
      titulo: 'Adulto sin senal',
      cuerpo:
          '${nombre.isEmpty ? 'El adulto mayor' : nombre} no ha enviado ubicacion reciente.',
    );
  }

  static Future<void> mostrarNotificacionMedicamentoNoConfirmado({
    required int id,
    required String cuerpo,
  }) async {
    await mostrarNotificacionAtencion(
      id: id,
      titulo: 'Medicamento no confirmado',
      cuerpo: cuerpo.trim().isEmpty
          ? 'El adulto no ha confirmado un medicamento reciente.'
          : '$cuerpo. El adulto aun no lo confirma.',
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

  static Future<bool> asegurarPermisoAlarmasExactas() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return true;

    final canSchedule = await androidPlugin.canScheduleExactNotifications();
    if (canSchedule ?? false) {
      return true;
    }

    final requested = await androidPlugin.requestExactAlarmsPermission();
    if (requested ?? false) {
      return true;
    }

    return false;
  }

  static Future<void> abrirAjustesAlarmasExactas() async {
    final intent = AndroidIntent(
      action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
    );
    await intent.launch();
  }

  static Future<void> programarAlarmaLocal(AlarmaLocal alarma) async {
    if (!alarma.activa) return;

    final exactAllowed = await asegurarPermisoAlarmasExactas();
    if (!exactAllowed) {
      throw Exception(
        'EVA necesita permiso de alarmas exactas para guardar la alarma.',
      );
    }

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
          _scheduledTitleForAlarm(alarma),
          _scheduledBodyForAlarm(alarma),
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
      _scheduledTitleForAlarm(alarma),
      _scheduledBodyForAlarm(alarma),
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

  static Future<void> cancelarNotificacionEmergencia(int id) async {
    await _plugin.cancel(id);
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

  static Future<bool> asegurarPermisoNotificaciones() async {
    if (!_initialized) {
      await inicializar();
    }

    final prefs = await SharedPreferences.getInstance();
    final yaSolicitado =
        prefs.getBool('eva_notification_permission_requested') ?? false;

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return true;

    final granted = await androidPlugin.areNotificationsEnabled();
    if (granted ?? false) {
      return true;
    }

    final requested = await androidPlugin.requestNotificationsPermission();
    await prefs.setBool('eva_notification_permission_requested', true);

    if (requested ?? false) {
      return true;
    }

    if (yaSolicitado) {
      await abrirAjustesNotificaciones();
    }

    return false;
  }

  static Future<void> abrirAjustesNotificaciones() async {
    final intent = AndroidIntent(
      action: 'android.settings.APP_NOTIFICATION_SETTINGS',
      arguments: <String, dynamic>{
        'android.provider.extra.APP_PACKAGE': 'com.example.eva_mobile',
      },
    );
    await intent.launch();
  }

  static String _scheduledTitleForAlarm(AlarmaLocal alarma) {
    final mensaje = alarma.mensaje.trim();
    if (mensaje.toLowerCase().startsWith('cita:')) {
      return 'Recordatorio de cita';
    }
    return 'EVA';
  }

  static String _scheduledBodyForAlarm(AlarmaLocal alarma) {
    final mensaje = alarma.mensaje.trim();
    if (mensaje.toLowerCase().startsWith('cita:')) {
      final limpio = mensaje.replaceFirst(
        RegExp(r'^cita:\s*', caseSensitive: false),
        '',
      );
      return limpio.isEmpty ? 'Tienes una cita programada.' : limpio;
    }
    return mensaje;
  }
}
