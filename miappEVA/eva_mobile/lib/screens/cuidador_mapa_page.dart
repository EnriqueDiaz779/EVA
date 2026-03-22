import 'package:flutter/material.dart';

import '../models/cuidador_location_model.dart';
import '../services/cuidador_location_service.dart';
import '../widgets/cuidador_map_card.dart';

class CuidadorMapaPage extends StatefulWidget {
  final CuidadorLocationState? initialLocationState;
  final List<CuidadorLocationPoint> initialRoutePoints;
  final bool initialRouteEnabled;

  const CuidadorMapaPage({
    super.key,
    required this.initialLocationState,
    required this.initialRoutePoints,
    required this.initialRouteEnabled,
  });

  @override
  State<CuidadorMapaPage> createState() => _CuidadorMapaPageState();
}

class _CuidadorMapaPageState extends State<CuidadorMapaPage> {
  CuidadorLocationState? _locationState;
  List<CuidadorLocationPoint> _routePoints = const [];
  late bool _routeEnabled;
  bool _loadingRoute = false;

  @override
  void initState() {
    super.initState();
    _locationState = widget.initialLocationState;
    _routePoints = List<CuidadorLocationPoint>.from(widget.initialRoutePoints);
    _routeEnabled = widget.initialRouteEnabled;
  }

  String _statusText() {
    if (_locationState == null) return 'Cargando ubicacion';
    if (_locationState!.adult == null) return 'Sin adulto vinculado';
    if (!_locationState!.compartirUbicacion) return 'Ubicacion desactivada';
    if (_locationState!.sinSenal || _locationState!.latest == null) return 'Sin señal';
    return 'Ubicacion activa';
  }

  Color _statusColor() {
    if (_locationState == null) return const Color(0xFF64748B);
    if (_locationState!.adult == null) return const Color(0xFF64748B);
    if (!_locationState!.compartirUbicacion) return const Color(0xFFB42318);
    if (_locationState!.sinSenal || _locationState!.latest == null) {
      return const Color(0xFFE67E22);
    }
    return const Color(0xFF1F9D55);
  }

  String _lastUpdatedText() {
    final timestamp = _locationState?.latest?.timestamp;
    if (timestamp == null) return 'Sin actualizacion reciente';
    final local = timestamp.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return 'Ultima actualizacion a las $hh:$mm';
  }

  String _statusDescription() {
    if (_locationState == null) {
      return 'Estamos consultando la ubicacion del adulto en este momento.';
    }
    if (_locationState!.adult == null) {
      return 'Aun no hay un adulto vinculado para mostrar en el mapa.';
    }
    if (!_locationState!.compartirUbicacion) {
      return 'El adulto desactivo la opcion de compartir ubicacion.';
    }
    if (_locationState!.sinSenal || _locationState!.latest == null) {
      return 'La app no recibe una posicion valida porque el dispositivo esta sin señal.';
    }
    return 'La ubicacion del adulto se esta recibiendo correctamente.';
  }

  String _adultName() {
    final name = _locationState?.adult?.nombre.trim() ?? '';
    if (name.isEmpty) return 'Adulto no vinculado';
    return name;
  }

  Future<void> _refreshLocation() async {
    try {
      final location = await CuidadorLocationService.obtenerUltimaUbicacion();
      final history = _routeEnabled
          ? await CuidadorLocationService.obtenerHistorial()
          : const <CuidadorLocationPoint>[];
      if (!mounted) return;
      setState(() {
        _locationState = location;
        _routePoints = history;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _toggleRoute() async {
    setState(() {
      _routeEnabled = !_routeEnabled;
      _loadingRoute = true;
    });

    try {
      final history = _routeEnabled
          ? await CuidadorLocationService.obtenerHistorial()
          : const <CuidadorLocationPoint>[];
      if (!mounted) return;
      setState(() {
        _routePoints = history;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routeEnabled = !_routeEnabled;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingRoute = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();

    return Scaffold(
      backgroundColor: const Color(0xFFDBDBDB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF123C92),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Mapa del cuidador',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshLocation,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _adultName(),
                    style: const TextStyle(
                      color: Color(0xFF20304D),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _lastUpdatedText(),
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusText(),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusDescription(),
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Stack(
              children: [
                CuidadorMapCard(
                  locationState: _locationState,
                  routePoints: _routePoints,
                  routeEnabled: _routeEnabled,
                  onToggleRoute: _toggleRoute,
                  onRefresh: _refreshLocation,
                ),
                if (_loadingRoute)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
