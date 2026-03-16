import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarma_local.dart';
import 'notificacion_service.dart';

class AlarmasLocalService {
  static const String _keyAlarmas = 'eva_alarmas_locales';

  static Future<List<AlarmaLocal>> obtenerAlarmas() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyAlarmas);

    if (raw == null || raw.isEmpty) return [];

    final List decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => AlarmaLocal.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) {
        final af = _fechaProgramadaDesdeAlarma(a);
        final bf = _fechaProgramadaDesdeAlarma(b);
        return af.compareTo(bf);
      });
  }

  static Future<void> _guardarLista(List<AlarmaLocal> alarmas) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(alarmas.map((e) => e.toJson()).toList());
    await prefs.setString(_keyAlarmas, raw);
  }

  static Future<AlarmaLocal> crearAlarma({
    required int hour,
    required int minute,
    required String mensaje,
    String? fechaIso,
    List<int> diasSemana = const [],
  }) async {
    final alarmas = await obtenerAlarmas();

    final ahora = DateTime.now();

    String? fechaFinalIso = fechaIso;

    // Si NO trae fecha y tampoco es recurrente, decidimos si va hoy o mañana
    if ((fechaFinalIso == null || fechaFinalIso.isEmpty) && diasSemana.isEmpty) {
      DateTime fechaObjetivo = DateTime(
        ahora.year,
        ahora.month,
        ahora.day,
        hour,
        minute,
      );

      if (!fechaObjetivo.isAfter(ahora)) {
        fechaObjetivo = fechaObjetivo.add(const Duration(days: 1));
      }

      fechaFinalIso =
          '${fechaObjetivo.year.toString().padLeft(4, '0')}-'
          '${fechaObjetivo.month.toString().padLeft(2, '0')}-'
          '${fechaObjetivo.day.toString().padLeft(2, '0')}';
    }

    final nueva = AlarmaLocal(
      id: DateTime.now().millisecondsSinceEpoch.remainder(10000000),
      mensaje: mensaje.trim().isEmpty ? 'Es hora de tu alarma' : mensaje.trim(),
      hour: hour,
      minute: minute,
      fechaIso: fechaFinalIso,
      diasSemana: diasSemana,
      activa: true,
      creadaEnIso: DateTime.now().toIso8601String(),
      estado: 'pendiente',
      vecesPospuesta: 0,
      ultimaAccionIso: null,
    );

    alarmas.add(nueva);
    await _guardarLista(alarmas);
    await NotificacionService.programarAlarmaLocal(nueva);

    return nueva;
  }

  static Future<void> eliminarAlarma(int id) async {
    final alarmas = await obtenerAlarmas();
    final filtradas = alarmas.where((e) => e.id == id).toList();
    final alarma = filtradas.isNotEmpty ? filtradas.first : null;
    if (alarma == null) return;

    await NotificacionService.cancelarAlarmaLocal(alarma);

    final nuevas = alarmas.where((e) => e.id != id).toList();
    await _guardarLista(nuevas);
  }

  static Future<void> cambiarActiva(int id, bool activa) async {
    final alarmas = await obtenerAlarmas();
    final index = alarmas.indexWhere((e) => e.id == id);
    if (index == -1) return;

    final alarmaActual = alarmas[index];
    await NotificacionService.cancelarAlarmaLocal(alarmaActual);

    final nueva = alarmaActual.copyWith(activa: activa);
    alarmas[index] = nueva;
    await _guardarLista(alarmas);

    if (activa) {
      await NotificacionService.programarAlarmaLocal(nueva);
    }
  }

  static Future<void> reprogramarTodasLasActivas() async {
    final alarmas = await obtenerAlarmas();
    for (final alarma in alarmas) {
      if (alarma.activa) {
        await NotificacionService.programarAlarmaLocal(alarma);
      }
    }
  }

  static DateTime _fechaProgramadaDesdeAlarma(AlarmaLocal alarma) {
    if (alarma.fechaIso != null && alarma.fechaIso!.isNotEmpty) {
      final f = DateTime.parse(alarma.fechaIso!);
      return DateTime(f.year, f.month, f.day, alarma.hour, alarma.minute);
    }

    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, alarma.hour, alarma.minute);
  }

  static Future<void> marcarComoTomada(int id) async {
    final alarmas = await obtenerAlarmas();
    final index = alarmas.indexWhere((e) => e.id == id);
    if (index == -1) return;

    final actual = alarmas[index];

    await NotificacionService.cancelarAlarmaLocal(actual);

    alarmas[index] = actual.copyWith(
      activa: false,
      estado: 'tomada',
      ultimaAccionIso: DateTime.now().toIso8601String(),
    );

    await _guardarLista(alarmas);
  }

  static Future<void> posponer5Min(int id) async {
  final alarmas = await obtenerAlarmas();
  final index = alarmas.indexWhere((e) => e.id == id);
  if (index == -1) return;

  final actual = alarmas[index];

  await NotificacionService.cancelarAlarmaLocal(actual);

  final fechaBase = _fechaProgramadaDesdeAlarma(actual);
    final nuevaFecha = fechaBase.add(const Duration(minutes: 5));

    final nuevaFechaIso =
        '${nuevaFecha.year.toString().padLeft(4, '0')}-'
        '${nuevaFecha.month.toString().padLeft(2, '0')}-'
        '${nuevaFecha.day.toString().padLeft(2, '0')}';

    final actualizada = actual.copyWith(
      hour: nuevaFecha.hour,
      minute: nuevaFecha.minute,
      fechaIso: nuevaFechaIso,
      estado: 'pospuesta',
      vecesPospuesta: actual.vecesPospuesta + 1,
      ultimaAccionIso: DateTime.now().toIso8601String(),
      activa: true,
    );

    alarmas[index] = actualizada;
    await _guardarLista(alarmas);
    await NotificacionService.programarAlarmaLocal(actualizada);
  }
}