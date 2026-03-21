import 'package:flutter/material.dart';
import 'dart:async';
import '../models/cuidador_agenda_item.dart';
import '../models/cuidador_inicio_model.dart';
import '../models/cuidador_location_model.dart';
import '../models/emergencia_model.dart';
import '../services/cuidador_service.dart';
import '../services/cuidador_agenda_service.dart';
import '../services/cuidador_location_service.dart';
import '../services/alarmas_local_service.dart';
import '../services/auth_service.dart';
import '../services/emergencia_service.dart';
import '../services/notificacion_service.dart';
import 'cuidador_agenda_page.dart';
import 'cuidador_chat_page.dart';
import 'cuidador_mapa_page.dart';
import 'cuidador_receta_page.dart';
import 'login_screen.dart';
import '../widgets/cuidador_alarm_form_sheet.dart';
import '../widgets/cuidador_cita_form_sheet.dart';
import '../widgets/cuidador_quick_actions_card.dart';
import '../widgets/cuidador_summary_card.dart';

class CuidadorScreen extends StatefulWidget {
  final String username;

  const CuidadorScreen({
    super.key,
    required this.username,
  });

  @override
  State<CuidadorScreen> createState() => _CuidadorScreenState();
}

class _CuidadorScreenState extends State<CuidadorScreen> {
  static const Duration _locationRefreshInterval = Duration(seconds: 10);
  static const Duration _emergencyRefreshInterval = Duration(seconds: 5);

  CuidadorInicioModel? _data;
  List<CuidadorAgendaItem> _agendaItems = const [];
  CuidadorLocationState? _locationState;
  List<CuidadorLocationPoint> _routePoints = const [];
  List<EmergenciaModel> _emergenciasPendientes = const [];

  bool _routeEnabled = false;
  DateTime _selectedAgendaDate = DateTime.now();
  bool _loading = true;
  bool _vinculando = false;
  bool _actualizandoEmergencia = false;
  int? _ultimoIdEmergenciaNotificado;

  String? _error;
  String? _errorCodigo;

  Timer? _locationTimer;
  Timer? _emergencyTimer;

  bool _mostrarPanelPerfil = false;
  final TextEditingController _codigoController = TextEditingController();
  bool _ocultarCodigo = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();

    _locationTimer = Timer.periodic(_locationRefreshInterval, (_) {
      _refreshLocationOnly();
    });

    _emergencyTimer = Timer.periodic(_emergencyRefreshInterval, (_) {
      _refreshEmergenciasOnly();
    });
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _emergencyTimer?.cancel();
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await CuidadorService.obtenerInicioCuidador(
        username: widget.username,
      );

      final tieneAdultoVinculado = result.adultoVinculado != null;

      final agenda = tieneAdultoVinculado
          ? await CuidadorAgendaService.obtenerAgenda()
          : const <CuidadorAgendaItem>[];

      final location = tieneAdultoVinculado
          ? await CuidadorLocationService.obtenerUltimaUbicacion()
          : null;

      final history = tieneAdultoVinculado && _routeEnabled
          ? await CuidadorLocationService.obtenerHistorial()
          : const <CuidadorLocationPoint>[];

      final emergencias = tieneAdultoVinculado
          ? await EmergenciaService.obtenerPendientes(
              username: widget.username,
            )
          : const <EmergenciaModel>[];

      if (!mounted) return;

      await _notificarEmergenciaNueva(emergencias);

      setState(() {
        _data = result;
        _agendaItems = agenda;
        _locationState = location;
        _routePoints = history;
        _emergenciasPendientes = emergencias;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _notificarEmergenciaNueva(
    List<EmergenciaModel> emergencias,
  ) async {
    if (emergencias.isEmpty) return;

    final actual = emergencias.first;
    final actualId = actual.idEmergencia;

    if (_ultimoIdEmergenciaNotificado == actualId) return;

    _ultimoIdEmergenciaNotificado = actualId;

    final nombreAdulto = (actual.adultoNombre ?? 'El adulto mayor').trim();

    await NotificacionService.mostrarNotificacionEmergencia(
      id: actualId,
      titulo: 'Emergencia SOS',
      cuerpo: '$nombreAdulto necesita ayuda urgente.',
    );
  }

  Future<void> _refreshLocationOnly() async {
    if (!mounted) return;

    if (_data?.adultoVinculado == null) {
      setState(() {
        _locationState = null;
        _routePoints = const [];
      });
      return;
    }

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
    } catch (_) {}
  }

  Future<void> _refreshEmergenciasOnly() async {
    if (!mounted) return;

    if (_data?.adultoVinculado == null) {
      setState(() {
        _emergenciasPendientes = const [];
        _ultimoIdEmergenciaNotificado = null;
      });
      return;
    }

    try {
      final emergencias = await EmergenciaService.obtenerPendientes(
        username: widget.username,
      );

      if (!mounted) return;

      await _notificarEmergenciaNueva(emergencias);

      setState(() {
        _emergenciasPendientes = emergencias;
      });
    } catch (_) {}
  }

  Future<void> _cambiarEstadoEmergencia(
    int idEmergencia,
    String estado,
  ) async {
    if (_actualizandoEmergencia) return;

    setState(() {
      _actualizandoEmergencia = true;
    });

    try {
      await EmergenciaService.actualizarEstado(
        username: widget.username,
        idEmergencia: idEmergencia,
        estado: estado,
      );

      if (estado == 'atendida' || estado == 'cerrada') {
        await NotificacionService.cancelarNotificacionEmergencia(idEmergencia);
      }

      await _refreshEmergenciasOnly();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Emergencia marcada como $estado.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _actualizandoEmergencia = false;
      });
    }
  }

  Future<void> _vincularAdulto() async {
    final codigo = _codigoController.text.trim();

    if (codigo.isEmpty) {
      setState(() {
        _errorCodigo = 'Ingresa el código único.';
      });
      return;
    }

    setState(() {
      _vinculando = true;
      _errorCodigo = null;
    });

    try {
      await CuidadorService.vincularAdultoPorCodigo(
        username: widget.username,
        codigo: codigo,
      );

      _codigoController.clear();
      await _cargarDatos();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adulto vinculado correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorCodigo = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _vinculando = false;
      });
    }
  }

  Future<void> _cerrarSesion() async {
    try {
      await AuthService.logout();
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  Future<void> _openAgendaPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CuidadorAgendaPage(
          initialItems: _agendaItems,
          initialSelectedDate: _selectedAgendaDate,
          onCreateAlarm: _crearAlarma,
          onCreateAppointment: _crearCita,
          onEditItem: _editarItem,
          onDeleteItem: _eliminarItem,
        ),
      ),
    );

    if (!mounted) return;
    await _cargarDatos();
  }

  Future<void> _openMapaPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CuidadorMapaPage(
          initialLocationState: _locationState,
          initialRoutePoints: _routePoints,
          initialRouteEnabled: _routeEnabled,
        ),
      ),
    );

    if (!mounted) return;
    await _refreshLocationOnly();
  }

  Future<void> _openRecetaPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CuidadorRecetaPage(),
      ),
    );

    if (!mounted) return;
    await _cargarDatos();
  }

  Future<void> _openChatPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CuidadorChatPage(),
      ),
    );
  }

  Future<void> _toggleRoute() async {
    setState(() {
      _routeEnabled = !_routeEnabled;
    });

    await _refreshLocationOnly();
  }

  Future<void> _crearAlarma(DateTime date) async {
    try {
      final result = await showModalBottomSheet<CuidadorAgendaItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CuidadorAlarmFormSheet(initialDate: date),
      );

      if (result == null) return;

      await CuidadorAgendaService.crearItem(
        title: result.title,
        type: result.type,
        timeText: result.timeText,
        date: result.date,
        daysText: result.daysText,
        active: result.active,
      );

      setState(() {
        _selectedAgendaDate = result.date ?? _selectedAgendaDate;
      });

      await _cargarDatos();
      await AlarmasLocalService.sincronizarDesdeBackend();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alarma creada correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _crearCita(DateTime date) async {
    try {
      final result = await showModalBottomSheet<CuidadorAgendaItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CuidadorCitaFormSheet(initialDate: date),
      );

      if (result == null) return;

      await CuidadorAgendaService.crearItem(
        title: result.title,
        type: result.type,
        timeText: result.timeText,
        date: result.date,
        active: result.active,
      );

      setState(() {
        _selectedAgendaDate = result.date ?? _selectedAgendaDate;
      });

      await _cargarDatos();
      await AlarmasLocalService.sincronizarDesdeBackend();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cita creada correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _editarItem(CuidadorAgendaItem item) async {
    try {
      final result = await showModalBottomSheet<CuidadorAgendaItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => item.isAppointment
            ? CuidadorCitaFormSheet(
                initialDate: item.date ?? DateTime.now(),
                initialItem: item,
              )
            : CuidadorAlarmFormSheet(
                initialDate: item.date ?? DateTime.now(),
                initialItem: item,
              ),
      );

      if (result == null) return;

      setState(() {
        _selectedAgendaDate = result.date ?? _selectedAgendaDate;
      });

      await CuidadorAgendaService.editarItem(result);
      await _cargarDatos();
      await AlarmasLocalService.sincronizarDesdeBackend();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elemento actualizado correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _eliminarItem(CuidadorAgendaItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar elemento'),
        content: Text('Se eliminará "${item.title}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await CuidadorAgendaService.eliminarItem(item.id);
      await _cargarDatos();
      await AlarmasLocalService.sincronizarDesdeBackend();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elemento eliminado correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Widget _buildEmergenciaCard() {
    if (_emergenciasPendientes.isEmpty) {
      return const SizedBox.shrink();
    }

    final emergencia = _emergenciasPendientes.first;
    final nombreAdulto = (emergencia.adultoNombre ?? 'El adulto mayor').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD32F2F),
          width: 1.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Emergencia SOS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFFB71C1C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$nombreAdulto necesita ayuda urgente.',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _actualizandoEmergencia
                      ? null
                      : () => _cambiarEstadoEmergencia(
                            emergencia.idEmergencia,
                            'atendida',
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Atendida'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _actualizandoEmergencia
                      ? null
                      : () => _cambiarEstadoEmergencia(
                            emergencia.idEmergencia,
                            'cerrada',
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B7280),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datoPerfil(String titulo, String valor) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 16,
          color: Colors.black87,
        ),
        children: [
          TextSpan(
            text: '$titulo ',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(
            text: valor,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayVinculacion() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 28,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'BIENVENIDO A EVA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ingresa el código único del adulto mayor que deseas cuidar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codigoController,
                    obscureText: _ocultarCodigo,
                    maxLength: 20,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '************',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _ocultarCodigo = !_ocultarCodigo;
                          });
                        },
                        icon: Icon(
                          _ocultarCodigo
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  if (_errorCodigo != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorCodigo!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _vinculando ? null : _vincularAdulto,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF123C92),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _vinculando ? 'Validando...' : 'Confirmar',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Se encuentra en la esquina inferior izquierda de la pantalla del adulto mayor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFDBDBDB),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFDBDBDB),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      );
    }

    if (_data == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFDBDBDB),
        body: Center(
          child: Text('No se pudo cargar la información del cuidador.'),
        ),
      );
    }

    final cuidador = _data!.cuidador;
    final adulto = _data!.adultoVinculado;
    final bloqueado = _data!.bloqueadoPorVinculo || adulto == null;

    return Scaffold(
      backgroundColor: const Color(0xFFDBDBDB),
      bottomNavigationBar: Container(
        height: 14,
        color: const Color(0xFF123C92),
      ),
      body: GestureDetector(
        onTap: () {
          if (_mostrarPanelPerfil) {
            setState(() {
              _mostrarPanelPerfil = false;
            });
          }
        },
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  height: 95,
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 36,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF123C92),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Image.asset(
                              'assets/images/eva.png',
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'EVA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _cerrarSesion,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE53935),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.logout,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Salir',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _mostrarPanelPerfil = !_mostrarPanelPerfil;
                              });
                            },
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.person,
                                color: Color(0xFF123C92),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _cargarDatos,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                      children: [
                        _buildEmergenciaCard(),
                        if (_emergenciasPendientes.isNotEmpty)
                          const SizedBox(height: 18),
                        CuidadorSummaryCard(
                          caregiverName: cuidador.nombre,
                          linkedAdultName: adulto?.nombre,
                          hasLinkedAdult: adulto != null,
                          currentDate: DateTime.now(),
                        ),
                        const SizedBox(height: 18),
                        CuidadorQuickActionsCard(
                          onAgendaTap: _openAgendaPage,
                          onMapTap: _openMapaPage,
                          onChatTap: _openChatPage,
                          onRecipeTap: _openRecetaPage,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_mostrarPanelPerfil)
              Positioned(
                top: 92,
                right: 0,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 310,
                    margin: const EdgeInsets.only(right: 0),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(28),
                        bottomLeft: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 12,
                          offset: Offset(-2, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Perfil del cuidador',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _datoPerfil('Nombre:', cuidador.nombre),
                          const SizedBox(height: 10),
                          _datoPerfil(
                            'Correo:',
                            cuidador.correo.isEmpty
                                ? 'Sin correo'
                                : cuidador.correo,
                          ),
                          const SizedBox(height: 10),
                          _datoPerfil(
                            'Teléfono:',
                            cuidador.telefono.isEmpty
                                ? 'Sin teléfono'
                                : cuidador.telefono,
                          ),
                          const SizedBox(height: 22),
                          Divider(color: Colors.grey.shade300),
                          const SizedBox(height: 18),
                          const Center(
                            child: Text(
                              'Perfil del adulto',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7F7),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.white,
                                  child: Icon(
                                    Icons.person,
                                    color: Color(0xFF123C92),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    adulto != null
                                        ? adulto.nombre
                                        : 'Aún no has vinculado a ningún adulto.',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: adulto != null
                                          ? Colors.black87
                                          : Colors.grey[700],
                                      fontWeight: adulto != null
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (bloqueado) _buildOverlayVinculacion(),
          ],
        ),
      ),
    );
  }
}