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

  String _textoFrecuenciaSimple(AlarmaLocal alarma) {
    if (alarma.diasSemana.isEmpty) return 'Una sola vez';

    if (alarma.diasSemana.length == 7) return 'Todos los días';

    if (alarma.diasSemana.length == 5 &&
        alarma.diasSemana.contains(1) &&
        alarma.diasSemana.contains(2) &&
        alarma.diasSemana.contains(3) &&
        alarma.diasSemana.contains(4) &&
        alarma.diasSemana.contains(5)) {
      return 'Lunes a viernes';
    }

    return _textoDias(alarma.diasSemana);
  }

  String _tituloSimple(AlarmaLocal alarma) {
    final texto = alarma.mensaje.trim();
    if (texto.isEmpty) return 'Alarma';
    return texto;
  }

  String _hora12(AlarmaLocal alarma) {
    int hour = alarma.hour;
    final minute = alarma.minute.toString().padLeft(2, '0');

    hour = hour % 12;
    if (hour == 0) hour = 12;

    return '$hour:$minute';
  }

  Future<void> _toggle(AlarmaLocal alarma, bool value) async {
    await AlarmasLocalService.cambiarActiva(alarma.id, value);
    await _cargar();
  }

  Future<void> _eliminar(AlarmaLocal alarma) async {
    await AlarmasLocalService.eliminarAlarma(alarma.id);
    await _cargar();
  }

  PreferredSizeWidget _buildTopBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(58),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 58,
          color: const Color(0xFF173A8A),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Historial de alarmas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(AlarmaLocal alarma) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _textoFrecuenciaSimple(alarma),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tituloSimple(alarma),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.scale(
                scale: 1.15,
                child: Switch(
                  value: alarma.activa,
                  onChanged: (v) => _toggle(alarma, v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _hora12(alarma),
                style: const TextStyle(
                  fontSize: 56,
                  height: 1,
                  fontWeight: FontWeight.w300,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  alarma.hour < 12 ? 'a.m.' : 'p.m.',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 30,
                color: Color(0xFF6B7280),
              ),
              onPressed: () => _eliminar(alarma),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE4E4E4),
      appBar: _buildTopBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _alarmas.isEmpty
              ? const Center(
                  child: Text(
                    'No hay alarmas guardadas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                    itemCount: _alarmas.length,
                    itemBuilder: (context, index) {
                      final alarma = _alarmas[index];
                      return _buildCard(alarma);
                    },
                  ),
                ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 30,
          color: const Color(0xFF173A8A),
        ),
      ),
    );
  }
}