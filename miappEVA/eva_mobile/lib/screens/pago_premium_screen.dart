import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PagoPremiumScreen extends StatefulWidget {
  const PagoPremiumScreen({super.key});

  @override
  State<PagoPremiumScreen> createState() => _PagoPremiumScreenState();
}

class _PagoPremiumScreenState extends State<PagoPremiumScreen> {
  final _cardNumberController = TextEditingController();
  final _cardNameController = TextEditingController();
  final _expController = TextEditingController();
  final _cvvController = TextEditingController();

  bool _processing = false;
  String? _error;

  String get _numeroTarjetaLimpio {
    return _cardNumberController.text.replaceAll(' ', '');
  }

  bool get _pagoCompleto {
    return _numeroTarjetaLimpio.length == 16 &&
        _cardNameController.text.trim().isNotEmpty &&
        RegExp(r'^\d{2}/\d{2}$').hasMatch(_expController.text.trim()) &&
        (_cvvController.text.trim().length == 3 ||
            _cvvController.text.trim().length == 4);
  }

  bool _validarFecha(String fecha) {
    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(fecha)) {
      return false;
    }

    final partes = fecha.split('/');
    final mes = int.tryParse(partes[0]) ?? 0;
    final anio = int.tryParse(partes[1]) ?? 0;

    if (mes < 1 || mes > 12) {
      return false;
    }

    final ahora = DateTime.now();
    final anioActual = ahora.year % 100;
    final mesActual = ahora.month;

    if (anio < anioActual) return false;
    if (anio == anioActual && mes < mesActual) return false;

    return true;
  }

  Future<void> _pagar() async {
    final tarjeta = _numeroTarjetaLimpio;
    final nombre = _cardNameController.text.trim();
    final fecha = _expController.text.trim();
    final cvv = _cvvController.text.trim();

    if (tarjeta.length != 16) {
      setState(() {
        _error = 'La tarjeta debe tener 16 dígitos.';
      });
      return;
    }

    if (nombre.isEmpty) {
      setState(() {
        _error = 'Escribe el nombre del titular.';
      });
      return;
    }

    if (!_validarFecha(fecha)) {
      setState(() {
        _error = 'La fecha debe ser válida y con formato MM/YY.';
      });
      return;
    }

    if (cvv.length < 3 || cvv.length > 4) {
      setState(() {
        _error = 'El CVV debe tener 3 o 4 dígitos.';
      });
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardNameController.dispose();
    _expController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color(0xFF0B2C6B);

    return Scaffold(
      backgroundColor: const Color(0xFFE4E4E4),
      appBar: AppBar(
        backgroundColor: azul,
        foregroundColor: Colors.white,
        title: const Text('Suscripción anual'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
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
                Image.asset(
                  'assets/images/eva.png',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Monto de pago',
                  style: TextStyle(fontSize: 18, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                const Text(
                  '\$100',
                  style: TextStyle(fontSize: 42, fontWeight: FontWeight.w800),
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
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _cardNumberController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(16),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Número de tarjeta',
                    prefixIcon: const Icon(Icons.credit_card),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _cardNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Nombre completo',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _expController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          hintText: 'MM/YY',
                          prefixIcon: const Icon(Icons.date_range),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onChanged: (value) {
                          final digits = value.replaceAll('/', '');

                          if (digits.length >= 3) {
                            final formatted =
                                '${digits.substring(0, 2)}/${digits.substring(2)}';

                            _expController.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                offset: formatted.length,
                              ),
                            );
                          } else {
                            _expController.value = TextEditingValue(
                              text: digits,
                              selection: TextSelection.collapsed(
                                offset: digits.length,
                              ),
                            );
                          }

                          setState(() {
                            _error = null;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _cvvController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          hintText: 'CVV',
                          prefixIcon: const Icon(Icons.lock),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onChanged: (_) {
                          setState(() {
                            _error = null;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_pagoCompleto && !_processing) ? _pagar : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: azul,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _processing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Pagar',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}