import 'package:flutter/material.dart';

import '../models/alarma_local.dart';
import '../services/alarmas_local_service.dart';

class HistorialAlarmasPage extends StatefulWidget {
  const HistorialAlarmasPage({super.key});

  @override
  State<HistorialAlarmasPage> createState() => _HistorialAlarmasPageState();
}

class _HistorialAlarmasPageState extends State<HistorialAlarmasPage> {
  List<AlarmaLocal> _alarmas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    await AlarmasLocalService.sincronizarDesdeBackend();
    final data = await AlarmasLocalService.obtenerAlarmas();
    if (!mounted) return;
    setState(() {
      _alarmas = data;
      _loading = false;
    });
  }

  String _textoDias(List<int> dias) {
    if (dias.isEmpty) return 'Una sola vez';

    const mapa = {
      1: 'Lun',
      2: 'Mar',
      3: 'Mié',
      4: 'Jue',
      5: 'Vie',
      6: 'Sáb',
      7: 'Dom',
    };

    return dias.map((e) => mapa[e] ?? e.toString()).join(', ');
  }

  String _fechaTexto(String? fechaIso) {
    if (fechaIso == null || fechaIso.isEmpty) return 'Sin fecha';
    return fechaIso;
  }

  DateTime _proximaEjecucion(AlarmaLocal alarma) {
    final now = DateTime.now();

    if (alarma.diasSemana.isNotEmpty) {
      return _proximaRecurrente(
        diasSemana: alarma.diasSemana,
        hour: alarma.hour,
        minute: alarma.minute,
      );
    }

    if (alarma.fechaIso != null && alarma.fechaIso!.isNotEmpty) {
      final fecha = DateTime.parse(alarma.fechaIso!);
      return DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        alarma.hour,
        alarma.minute,
      );
    }

    DateTime scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      alarma.hour,
      alarma.minute,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  DateTime _proximaRecurrente({
    required List<int> diasSemana,
    required int hour,
    required int minute,
  }) {
    final now = DateTime.now();

    DateTime? mejor;

    for (final dia in diasSemana) {
      DateTime candidato = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      while (candidato.weekday != dia || !candidato.isAfter(now)) {
        candidato = candidato.add(const Duration(days: 1));
      }

      if (mejor == null || candidato.isBefore(mejor)) {
        mejor = candidato;
      }
    }

    return mejor ??
        DateTime(now.year, now.month, now.day, hour, minute)
            .add(const Duration(days: 1));
  }

  String _nombreDiaCompleto(int weekday) {
    const mapa = {
      1: 'Lunes',
      2: 'Martes',
      3: 'Miércoles',
      4: 'Jueves',
      5: 'Viernes',
      6: 'Sábado',
      7: 'Domingo',
    };
    return mapa[weekday] ?? 'Día';
  }

  String _dosDigitos(int n) => n.toString().padLeft(2, '0');

  String _textoProximaAlarma(AlarmaLocal alarma) {
    final proxima = _proximaEjecucion(alarma);
    final now = DateTime.now();

    final hoy = DateTime(now.year, now.month, now.day);
    final fechaProxima = DateTime(proxima.year, proxima.month, proxima.day);
    final diferenciaDias = fechaProxima.difference(hoy).inDays;

    final horaTexto =
        '${_dosDigitos(proxima.hour)}:${_dosDigitos(proxima.minute)}';

    if (diferenciaDias == 0) {
      return 'Hoy $horaTexto';
    }

    if (diferenciaDias == 1) {
      return 'Mañana $horaTexto';
    }

    final nombreDia = _nombreDiaCompleto(proxima.weekday);
    final fechaTexto =
        '${_dosDigitos(proxima.day)}/${_dosDigitos(proxima.month)}';

    return '$nombreDia $fechaTexto $horaTexto';
  }

  Future<void> _toggle(AlarmaLocal alarma, bool value) async {
    await AlarmasLocalService.cambiarActiva(alarma.id, value);
    await _cargar();
  }

  Future<void> _eliminar(AlarmaLocal alarma) async {
    await AlarmasLocalService.eliminarAlarma(alarma.id);
    await _cargar();
  }

  Widget _buildCard(AlarmaLocal alarma) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(Icons.alarm, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarma.horaTexto,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alarma.mensaje,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  if (!alarma.esRecurrente && alarma.fechaIso != null && alarma.fechaIso!.isNotEmpty)
                    Text(
                      'Fecha: ${_fechaTexto(alarma.fechaIso)}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  Text(
                    'Repetir: ${_textoDias(alarma.diasSemana)}',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Próxima alarma: ${_textoProximaAlarma(alarma)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                  Text(
                    'Estado: ${alarma.estado}',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pospuesta: ${alarma.vecesPospuesta} veces',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: alarma.activa,
                  onChanged: (v) => _toggle(alarma, v),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _eliminar(alarma),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de alarmas'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _alarmas.isEmpty
              ? const Center(child: Text('No hay alarmas guardadas'))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    itemCount: _alarmas.length,
                    itemBuilder: (context, index) {
                      final alarma = _alarmas[index];
                      return _buildCard(alarma);
                    },
                  ),
                ),
    );
  }
}
