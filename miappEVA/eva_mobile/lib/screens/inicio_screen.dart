import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:geolocator/geolocator.dart';

import '../models/inicio_model.dart';
import '../services/inicio_service.dart';
import '../services/voz_service.dart';
import 'login_screen.dart';
import '../screens/historial_alarmas_page.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../services/medicamento_service.dart';
import '../services/alarmas_local_service.dart';
import '../services/adulto_location_service.dart';
import '../services/tts_service.dart';
import 'adulto_chat_page.dart';
import 'crear_alarma_manual_page.dart';
import '../services/emergencia_service.dart';
import 'dart:convert';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> with WidgetsBindingObserver {

  InicioModel? _inicio;
  bool _loading = true;
  String? _error;
  bool _mostrarCodigo = false;
  bool _ubicacionActiva = false;
  bool _cargandoUbicacion = false;
  bool _enviandoEmergencia = false;
  StreamSubscription<Position>? _locationSubscription;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechDisponible = false;
  bool _escuchando = false;
  bool _procesandoVoz = false;
  bool _procesandoLector = false;
  String _textoEscuchado = '';
  String _respuestaIA = '';
  bool _bienvenidaHablada = false;
  bool get _mostrarFuncionesCuidador => _inicio?.estaVinculado == true;
  bool get _mostrarAlarmaManual => _inicio?.estaVinculado != true;
  bool _esperandoRegresoDeAjustesUbicacion = false;
  bool _activandoUbicacionAutomaticamente = false;

  bool _modalUbicacionMostrado = false;
  bool _modalUbicacionAbierto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPantalla();
  }

  Future<void> _initPantalla() async {
    await _inicializarVoz();
    await TtsService.inicializar();
    await AlarmasLocalService.sincronizarDesdeBackend();
    await _cargarInicio();

    if (_inicio?.estaVinculado == true) {
      await _cargarEstadoUbicacion();

      if (!_ubicacionActiva) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mostrarModalUbicacionInicial();
        });
      }
    } else {
      _detenerStreamUbicacion();
      if (mounted) {
        setState(() {
          _ubicacionActiva = false;
        });
      }
    }

    _hablarBienvenida();
  }

  void _hablarBienvenida() {
    if (_bienvenidaHablada || !mounted) return;
    if (_inicio == null) return;

    _bienvenidaHablada = true;

    final estaVinculado = _inicio?.estaVinculado == true;

    final mensaje = estaVinculado
        ? 'Bienvenido a EVA. Presiona hablar para decirme lo que necesitas, lector de medicamentos para escanear un medicamento, chat para comunicarte con tu cuidador, botón de emergencia para pedir ayuda, o ubicación compartida para que tu cuidador pueda verla.'
        : 'Bienvenido a EVA. Presiona hablar para decirme lo que necesitas, lector de medicamentos para escanear un medicamento, o alarma para crear una alarma manual.';

    unawaited(TtsService.hablar(mensaje));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _esperandoRegresoDeAjustesUbicacion &&
        !_activandoUbicacionAutomaticamente) {
      unawaited(_continuarActivacionUbicacionAlRegresar());
    }
  }

  Future<void> _continuarActivacionUbicacionAlRegresar() async {
    _activandoUbicacionAutomaticamente = true;

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        _esperandoRegresoDeAjustesUbicacion = false;
        _mostrarMensajeUbicacion('La ubicación sigue apagada.');
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _esperandoRegresoDeAjustesUbicacion = false;
        _mostrarMensajeUbicacion('Debes permitir la ubicación para continuar.');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _esperandoRegresoDeAjustesUbicacion = false;
        await Geolocator.openAppSettings();
        _mostrarMensajeUbicacion(
          'Activa el permiso de ubicación en ajustes de la aplicación.',
        );
        return;
      }

      final position = await _obtenerPosicionActual();
      final estado = await AdultoLocationService.cambiarEstado(true);

      await AdultoLocationService.enviarPing(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
      );

      _esperandoRegresoDeAjustesUbicacion = false;

      if (!mounted) return;

      setState(() {
        _ubicacionActiva = estado.enabled;
      });

      _iniciarStreamUbicacion();
      _cerrarModalUbicacionSiEstaAbierto();

      await TtsService.hablar('Ubicación activada correctamente.');
      _mostrarMensajeUbicacion(
        'Ubicación activada correctamente.',
        color: Colors.green,
      );
    } catch (_) {
      _esperandoRegresoDeAjustesUbicacion = false;
      _mostrarMensajeUbicacion('No pude activar la ubicación.');
    } finally {
      _activandoUbicacionAutomaticamente = false;

      if (mounted) {
        setState(() {
          _cargandoUbicacion = false;
        });
      }
    }
  }

  Future<void> _cargarEstadoUbicacion() async {
    try {
      final estado = await AdultoLocationService.obtenerEstado();
      if (!mounted) return;

      setState(() {
        _ubicacionActiva = estado.enabled;
      });

      if (_ubicacionActiva) {
        _iniciarStreamUbicacion();
      } else {
        _detenerStreamUbicacion();
      }
    } catch (_) {}
  }

  Future<void> _inicializarVoz() async {
    try {
      final disponible = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;

          if (status == 'notListening' || status == 'done') {
            setState(() {
              _escuchando = false;
            });
          }
        },
        onError: (error) {
          if (!mounted) return;

          setState(() {
            _escuchando = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error de voz: ${error.errorMsg}'),
              backgroundColor: Colors.red,
            ),
          );
        },
      );

      if (!mounted) return;

      setState(() {
        _speechDisponible = disponible;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _speechDisponible = false;
      });
    }
  }

  Future<void> _cargarInicio() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await InicioService.obtenerInicio();
      if (!mounted) return;

      setState(() {
        _inicio = data;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _mostrarMensajeUbicacion(String mensaje, {Color? color}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: color,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _accionLectorMedicamentos() async {
    try {
      await TtsService.hablar(
        'Toma una foto de tu medicamento para que pueda ayudarte a identificarlo.',
      );

      final picker = ImagePicker();

      final XFile? foto = await picker.pickImage(
        source: ImageSource.camera, // 🔥 SOLO CÁMARA
        imageQuality: 85,
      );

      if (foto == null) return;

      if (!mounted) return;

      setState(() {
        _procesandoLector = true;
      });

      final resultado = await MedicamentoService.analizarMedicamento(
        imageFile: File(foto.path),
      );

      if (!mounted) return;

      final ok = resultado['ok'] == true;
      final nombre = (resultado['nombre'] ?? '').toString().trim();
      final paraQueSirve = (resultado['para_que_sirve'] ?? '').toString().trim();
      final error = (resultado['error'] ?? '').toString().trim();

      if (ok && nombre.isNotEmpty) {
        _mostrarDialogoRespuesta(
          titulo: 'Medicamento detectado',
          mensaje: 'Nombre: $nombre\n\n¿Para qué sirve?\n$paraQueSirve',
        );
      } else {
        _mostrarDialogoRespuesta(
          titulo: 'Resultado',
          mensaje: error.isNotEmpty
              ? error
              : 'No pude identificar el medicamento en la foto.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      _mostrarDialogoRespuesta(
        titulo: 'Error',
        mensaje: e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          _procesandoLector = false;
        });
      }
    }
  }

  Future<void> _cerrarSesion() async {
    _detenerStreamUbicacion();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userData');

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _toggleUbicacion({bool desdeModal = false}) async {
    if (_cargandoUbicacion) return;

    setState(() {
      _cargandoUbicacion = true;
    });

    try {
      if (_ubicacionActiva) {
        final estado = await AdultoLocationService.cambiarEstado(false);
        _detenerStreamUbicacion();

        if (!mounted) return;

        setState(() {
          _ubicacionActiva = estado.enabled;
        });

        await TtsService.hablar(
          'La ubicación compartida fue desactivada en EVA.',
        );

        _mostrarMensajeUbicacion(
          'Ubicación compartida desactivada.',
          color: Colors.red,
        );

        return;
      }

      await TtsService.hablar(
        'Vamos a activar tu ubicación para compartirla con tu cuidador.',
      );

      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        _esperandoRegresoDeAjustesUbicacion = true;
        await Geolocator.openLocationSettings();
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _mostrarMensajeUbicacion('Debes permitir la ubicación para continuar.');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        _mostrarMensajeUbicacion(
          'Activa el permiso de ubicación en ajustes de la aplicación.',
        );
        return;
      }

      final position = await _obtenerPosicionActual();
      final estado = await AdultoLocationService.cambiarEstado(true);

      await AdultoLocationService.enviarPing(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
      );

      if (!mounted) return;

      setState(() {
        _ubicacionActiva = estado.enabled;
      });

      _iniciarStreamUbicacion();

      if (_ubicacionActiva) {
        _cerrarModalUbicacionSiEstaAbierto();
      }

      await TtsService.hablar('Ubicación activada correctamente.');
      _mostrarMensajeUbicacion(
        'Ubicación activada correctamente.',
        color: Colors.green,
      );
    } catch (_) {
      _mostrarMensajeUbicacion('Ocurrió un problema con la ubicación.');
    } finally {
      if (_esperandoRegresoDeAjustesUbicacion) return;
      if (!mounted) return;

      setState(() {
        _cargandoUbicacion = false;
      });
    }
  }

  Future<Position> _obtenerPosicionActual() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }
      throw Exception(
        'No pude obtener la ubicación del dispositivo.',
      );
    }
  }

  Future<void> _enviarUbicacionDesdePosition(Position position) async {
    await AdultoLocationService.enviarPing(
      lat: position.latitude,
      lng: position.longitude,
      accuracy: position.accuracy,
    );
  }

  void _iniciarStreamUbicacion() {
    _locationSubscription?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
        try {
          if (!_ubicacionActiva) return;
          await _enviarUbicacionDesdePosition(position);
        } catch (_) {}
      },
      onError: (_) {},
    );
  }

  void _detenerStreamUbicacion() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  Future<String> _obtenerUsernameGuardado() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('userData');

    if (userData == null || userData.isEmpty) {
      throw Exception('No se encontró la sesión del usuario.');
    }

    final data = jsonDecode(userData);
    final username = (data['username'] ?? '').toString().trim();

    if (username.isEmpty) {
      throw Exception('No se encontró el username del usuario.');
    }

    return username;
  }

  Future<void> _enviarEmergenciaSOS() async {
    if (_enviandoEmergencia) return;

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Se enviará una alerta SOS a tu cuidador.\n\n¿Deseas continuar?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Enviar SOS',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5E7EB),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmar != true) return;

    setState(() {
      _enviandoEmergencia = true;
    });

    try {
      final username = await _obtenerUsernameGuardado();

      double? lat;
      double? lng;

      try {
        final position = await _obtenerPosicionActual();
        lat = position.latitude;
        lng = position.longitude;

        try {
          await AdultoLocationService.enviarPing(
            lat: lat,
            lng: lng,
            accuracy: position.accuracy,
          );
        } catch (_) {}
      } catch (_) {}

      final resp = await EmergenciaService.crearEmergencia(
        username: username,
        lat: lat,
        lng: lng,
      );

      if (!mounted) return;

      final duplicada = resp['duplicada'] == true;

      _mostrarDialogoRespuesta(
        titulo: 'SOS',
        mensaje: duplicada
            ? 'La alerta ya había sido enviada hace unos segundos.'
            : 'Tu alerta SOS fue enviada correctamente al cuidador.',
      );
    } catch (e) {
      if (!mounted) return;

      _mostrarDialogoRespuesta(
        titulo: 'Error',
        mensaje: e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _enviandoEmergencia = false;
      });
    }
  }

  int? _mapearDiaTextoANumero(String dia) {
    final d = dia.toLowerCase().trim();

    const mapa = {
      'lun': 1,
      'lunes': 1,
      'mar': 2,
      'martes': 2,
      'mie': 3,
      'mié': 3,
      'miercoles': 3,
      'miércoles': 3,
      'jue': 4,
      'jueves': 4,
      'vie': 5,
      'viernes': 5,
      'sab': 6,
      'sáb': 6,
      'sabado': 6,
      'sábado': 6,
      'dom': 7,
      'domingo': 7,
    };

    return mapa[d];
  }

  List<int> _obtenerDiasDesdeMeta(Map meta) {
    final raw = meta['dias_semana'] ?? meta['dias'] ?? meta['dia'];

    if (raw is List) {
      return raw.map((e) {
        if (e is int) return e;
        return _mapearDiaTextoANumero(e.toString());
      }).whereType<int>().toSet().toList()..sort();
    }

    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(RegExp(r'[,;/]'))
          .map((e) => _mapearDiaTextoANumero(e.trim()))
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();
    }

    return <int>[];
  }

  String? _obtenerFechaIsoDesdeMeta(Map meta) {
    String? fechaIso = meta['fecha']?.toString();

    if (fechaIso != null && fechaIso.trim().isNotEmpty && fechaIso != 'null') {
      return fechaIso.trim();
    }

    final fechaRelativa = (meta['fecha_relativa'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    if (fechaRelativa.isEmpty) return null;

    final ahora = DateTime.now();
    DateTime base = ahora;

    if (fechaRelativa == 'mañana' || fechaRelativa == 'manana') {
      base = ahora.add(const Duration(days: 1));
    } else if (fechaRelativa == 'hoy') {
      base = ahora;
    } else {
      return null;
    }

    return '${base.year.toString().padLeft(4, '0')}-'
        '${base.month.toString().padLeft(2, '0')}-'
        '${base.day.toString().padLeft(2, '0')}';
  }

  Future<void> _accionHablar() async {
    if (_procesandoVoz) return;

    if (!_speechDisponible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El reconocimiento de voz no está disponible.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_escuchando) {
      await _speech.stop();

      if (!mounted) return;

      setState(() {
        _escuchando = false;
      });

      if (_textoEscuchado.trim().isNotEmpty) {
        await _enviarTextoAVozService(_textoEscuchado.trim());
      }
      return;
    }

    setState(() {
      _textoEscuchado = '';
      _respuestaIA = '';
      _escuchando = true;
    });

    await TtsService.hablar('Te escucho. Dime que necesitas.');

    await _speech.listen(
      localeId: 'es_MX',
      partialResults: true,
      onResult: (result) async {
        if (!mounted) return;

        setState(() {
          _textoEscuchado = result.recognizedWords;
        });

        if (result.finalResult) {
          await _speech.stop();

          if (!mounted) return;

          setState(() {
            _escuchando = false;
          });

          if (_textoEscuchado.trim().isNotEmpty) {
            await _enviarTextoAVozService(_textoEscuchado.trim());
          }
        }
      },
    );
  }

  Future<void> _enviarTextoAVozService(String texto) async {
    setState(() {
      _procesandoVoz = true;
    });

    try {
      final data = await VozService.registrarOrden(texto: texto);

      final respuesta = (data['respuesta'] ?? '').toString().trim();
      final alarmCreated = data['alarm_created'] == true;
      final meta = data['meta'];

      if (!mounted) return;

      setState(() {
        _respuestaIA = respuesta.isEmpty
            ? 'No hubo respuesta del asistente.'
            : respuesta;
      });

      if (alarmCreated) {
        String hora = '';
        String mensajeAlarma = 'Es hora de tu alarma';

        if (meta is Map) {
          final mensaje = (meta['mensaje'] ?? '').toString().trim();
          hora = (meta['hora'] ?? '').toString().trim();

          if (mensaje.isNotEmpty) {
            mensajeAlarma = mensaje;
          }

          if (hora.isNotEmpty) {
            final partes = hora.split(':');

            if (partes.length >= 2) {
              final h = int.tryParse(partes[0]) ?? 0;
              final m = int.tryParse(partes[1]) ?? 0;

              final fechaIso = _obtenerFechaIsoDesdeMeta(meta);
              final diasSemana = _obtenerDiasDesdeMeta(meta);

              await AlarmasLocalService.crearAlarma(
                hour: h,
                minute: m,
                mensaje: mensajeAlarma,
                fechaIso: fechaIso,
                diasSemana: diasSemana,
              );
            }
          }
        }
      }

      _mostrarDialogoRespuesta(
        titulo: 'EVA',
        mensaje: _respuestaIA,
      );
    } catch (e) {
      if (!mounted) return;

      _mostrarDialogoRespuesta(
        titulo: 'Error',
        mensaje: e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          _procesandoVoz = false;
        });
      }
    }
  }

  void _mostrarDialogoRespuesta({
    required String titulo,
    required String mensaje,
  }) {
    TtsService.hablar(mensaje);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    TtsService.detener();
                    Navigator.pop(context);

                    setState(() {
                      _textoEscuchado = '';
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF173A8A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Cerrar',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarModalUbicacionInicial() async {
    if (!mounted) return;
    if (_modalUbicacionMostrado || _modalUbicacionAbierto) return;
    if (!_mostrarFuncionesCuidador) return;
    if (_ubicacionActiva) return;

    _modalUbicacionMostrado = true;
    _modalUbicacionAbierto = true;

    await TtsService.hablar(
      'Activa tu ubicación para que tu cuidador pueda verte en todo momento.',
    );

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Activa tu ubicación para que tu cuidador pueda verte en todo momento',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _cargandoUbicacion
                      ? null
                      : () async {
                          await _toggleUbicacion(desdeModal: true);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2DBA34),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    _cargandoUbicacion ? 'Procesando...' : 'Activar',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    TtsService.detener();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    _modalUbicacionAbierto = false;
  }

  void _cerrarModalUbicacionSiEstaAbierto() {
    if (!mounted) return;
    if (_modalUbicacionAbierto &&
        Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
      _modalUbicacionAbierto = false;
    }
  }

  Widget _buildBotonSuperior({
    required String texto,
    required Color color,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: 4),
            ],
            if (texto.isNotEmpty)
              Text(
                texto,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonEstadoUbicacion() {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: _cargandoUbicacion ? null : () => _toggleUbicacion(),
        style: ElevatedButton.styleFrom(
          backgroundColor: _ubicacionActiva
            ? const Color(0xFF93C5FD) 
            : const Color(0xFFD1D5DB), 
          foregroundColor: Colors.black,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _ubicacionActiva ? Icons.location_on : Icons.location_off,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              _cargandoUbicacion
                  ? '...'
                  : _ubicacionActiva
                      ? 'Activa'
                      : 'Inactiva',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonPrincipal({
    required String imagen,
    required String texto,
    required VoidCallback onTap,
    double size = 118,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  blurRadius: 14,
                  color: Colors.black26,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                imagen,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4B5563),
          ),
        ),
      ],
    );
  }

  String _codigoOculto(String codigo) {
    if (codigo.isEmpty) return '';
    return '*' * codigo.length;
  }

  Widget _buildCodigoUnico() {
    final codigo = _inicio?.codigoUnico ?? '';
    if (codigo.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            blurRadius: 6,
            color: Colors.black12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Flexible(
            flex: 4,
            child: Text(
              'Código único',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Text(
              _mostrarCodigo ? codigo : _codigoOculto(codigo),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Color(0xFF374151),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                _mostrarCodigo = !_mostrarCodigo;
              });
            },
            child: Icon(
              _mostrarCodigo ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContenido() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 10,
                    color: Colors.black12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  _buildBotonPrincipal(
                    imagen: 'assets/images/microfono11.png',
                    texto: _escuchando
                        ? 'Escuchando...'
                        : _procesandoVoz
                            ? 'Procesando...'
                            : 'Hablar',
                    onTap: _accionHablar,
                    size: 190,
                  ),
                  if (_textoEscuchado.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _textoEscuchado,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _buildBotonPrincipal(
                    imagen: 'assets/images/medicamento.png',
                    texto: _procesandoLector ? 'Procesando...' : 'Lector Medicamentos',
                    onTap: _procesandoLector ? () {} : _accionLectorMedicamentos,
                    size: 190,
                  ),
                  if (_mostrarAlarmaManual) ...[
                    const SizedBox(height: 28),
                    _buildBotonPrincipal(
                      imagen: 'assets/images/alarmaBoton.png',
                      texto: 'Alarma',
                      onTap: () async {
                        await TtsService.hablar(
                          'Aqui puedes crear una alarma manual. Primero selecciona la hora, luego los dias si quieres repetirla, y por ultimo escribe el mensaje.',
                        );
                        final creada = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CrearAlarmaManualPage(),
                          ),
                        );

                        if (creada == true && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Alarma creada correctamente'),
                            ),
                          );
                        }
                      },
                      size: 190,
                    ),
                  ],
                  if (_mostrarFuncionesCuidador) ...[
                    const SizedBox(height: 28),
                    _buildBotonPrincipal(
                      imagen: 'assets/images/chat_boton.png',
                      texto: 'Chat con cuidador',
                      onTap: () async {
                        await TtsService.hablar(
                          'Aqui puedes comunicarte con tu cuidador usando tu voz.',
                        );
                        if (!mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdultoChatPage(),
                          ),
                        );
                      },
                      size: 190,
                    ),
                    const SizedBox(height: 28),
                    _buildBotonPrincipal(
                      imagen: 'assets/images/sos_boton.png',
                      texto: _enviandoEmergencia ? 'Enviando SOS...' : 'Emergencia SOS',
                      onTap: _enviandoEmergencia ? () {} : _enviarEmergenciaSOS,
                      size: 190,
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildCodigoUnico(),
          ],
        ),
      ),
    );
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
              ClipOval(
                child: Image.asset(
                  'assets/images/eva.jpg',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'EVA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (_mostrarAlarmaManual) ...[
                _buildBotonSuperior(
                  texto: '',
                  color: const Color(0xFF22C55E),
                  icon: Icons.access_time_filled,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HistorialAlarmasPage(),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
              if (_mostrarFuncionesCuidador) ...[
                _buildBotonEstadoUbicacion(),
                const SizedBox(width: 8),
              ],
              _buildBotonSuperior(
                texto: 'Salir',
                color: const Color(0xFFEF4444),
                onPressed: _cerrarSesion,
              ),
            ],
          ),
        ),
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
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarInicio,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                    children: [
                      _buildContenido(),
                    ],
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detenerStreamUbicacion();
    unawaited(TtsService.detener());
    super.dispose();
  }
}