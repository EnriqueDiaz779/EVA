import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import 'pago_premium_screen.dart';

class RegistroCuidadorScreen extends StatefulWidget {
  const RegistroCuidadorScreen({super.key});

  @override
  State<RegistroCuidadorScreen> createState() => _RegistroCuidadorScreenState();
}

class _RegistroCuidadorScreenState extends State<RegistroCuidadorScreen> {
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  String? _error;

  bool get _formularioCompleto {
    return _nombreController.text.trim().isNotEmpty &&
        _correoController.text.trim().isNotEmpty &&
        _telefonoController.text.trim().isNotEmpty &&
        _passwordController.text.trim().isNotEmpty;
  }

  bool _correoValido(String correo) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(correo);
  }

  Future<void> _irAPago() async {
    final nombre = _nombreController.text.trim();
    final correo = _correoController.text.trim();
    final telefono = _telefonoController.text.trim();
    final password = _passwordController.text.trim();

    if (!_formularioCompleto) {
      setState(() {
        _error = 'Completa todos los campos.';
      });
      return;
    }

    if (!_correoValido(correo)) {
      setState(() {
        _error = 'Escribe un correo válido.';
      });
      return;
    }

    if (telefono.length < 10) {
      setState(() {
        _error = 'El teléfono debe tener al menos 10 dígitos.';
      });
      return;
    }

    final pagado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const PagoPremiumScreen(),
      ),
    );

    if (pagado != true) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.registerCuidador(
        nombreCompleto: nombre,
        correo: correo,
        telefono: telefono,
        password: password,
        pagoCompletado: true,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro exitoso. Ahora inicia sesión.')),
      );

      Navigator.pop(context);
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

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _telefonoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color(0xFF0B2C6B);
    final verde = const Color(0xFF16A34A);

    return Scaffold(
      backgroundColor: const Color(0xFFE4E4E4),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 40,
              width: double.infinity,
              color: azul,
              alignment: Alignment.center,
              child: const Text(
                'EVA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: 500,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 20,
                          color: Colors.black12,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(60),
                          child: Image.asset(
                            'assets/images/eva.png',
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Registro de cuidador',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '🧑‍⚕️ Regístrate para administrar y ayudar al adulto mayor.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 17, color: Colors.black54),
                        ),
                        const SizedBox(height: 24),

                        if (_error != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],

                        TextField(
                          controller: _nombreController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: 'Nombre completo',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: _correoController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: InputDecoration(
                            hintText: 'Correo',
                            prefixIcon: const Icon(Icons.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),

                        TextField(
                          controller: _telefonoController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            hintText: 'Teléfono',
                            prefixIcon: const Icon(Icons.phone),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_formularioCompleto && !_loading)
                                ? _irAPago
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: verde,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Continuar a pago',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Ya tengo cuenta, volver al login',
                            style: TextStyle(
                              color: azul,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(height: 16, width: double.infinity, color: azul),
          ],
        ),
      ),
    );
  }
}