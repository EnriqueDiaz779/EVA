import 'package:flutter/material.dart';
import '../models/cuidador_inicio_model.dart';
import '../services/cuidador_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

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
  CuidadorInicioModel? _data;
  bool _loading = true;
  bool _vinculando = false;
  String? _error;
  String? _errorCodigo;

  bool _mostrarPanelPerfil = false;

  final TextEditingController _codigoController = TextEditingController();
  bool _ocultarCodigo = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
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

      if (!mounted) return;

      setState(() {
        _data = result;
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adulto vinculado correctamente.'),
          ),
        );
      }
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

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
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
    final bloqueado = _data!.bloqueadoPorVinculo;

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
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 36),
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
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

                const Expanded(
                  child: SizedBox(),
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
                            cuidador.correo.isEmpty ? 'Sin correo' : cuidador.correo,
                          ),
                          const SizedBox(height: 10),
                          _datoPerfil(
                            'Teléfono:',
                            cuidador.telefono.isEmpty ? 'Sin teléfono' : cuidador.telefono,
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
                              border: Border.all(color: Colors.grey.shade300),
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
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(
            text: valor,
            style: const TextStyle(fontWeight: FontWeight.w500),
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
}