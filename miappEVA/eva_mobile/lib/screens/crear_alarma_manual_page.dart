import 'package:flutter/material.dart';
import '../services/alarmas_local_service.dart';
import '../services/notificacion_service.dart';

class CrearAlarmaManualPage extends StatefulWidget {
  const CrearAlarmaManualPage({super.key});

  @override
  State<CrearAlarmaManualPage> createState() => _CrearAlarmaManualPageState();
}

class _CrearAlarmaManualPageState extends State<CrearAlarmaManualPage> {
  int _hour = 8;
  int _minute = 0;

  int _paso = 1;

  final Set<int> _diasSeleccionados = {};
  final TextEditingController _mensajeController =
      TextEditingController(text: 'Es hora de tu alarma');

  bool _guardando = false;

  @override
  void dispose() {
    _mensajeController.dispose();
    super.dispose();
  }

  void _sumarHora() {
    setState(() {
      _hour++;
      if (_hour > 23) _hour = 0;
    });
  }

  void _restarHora() {
    setState(() {
      _hour--;
      if (_hour < 0) _hour = 23;
    });
  }

  void _sumarMinuto() {
    setState(() {
      _minute += 5;
      if (_minute > 55) _minute = 0;
    });
  }

  void _restarMinuto() {
    setState(() {
      _minute -= 5;
      if (_minute < 0) _minute = 55;
    });
  }

  String get _horaTexto {
    final hh = _hour.toString().padLeft(2, '0');
    final mm = _minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _toggleDia(int dia) {
    setState(() {
      if (_diasSeleccionados.contains(dia)) {
        _diasSeleccionados.remove(dia);
      } else {
        _diasSeleccionados.add(dia);
      }
    });
  }

  Future<void> _guardarAlarma() async {
    if (_guardando) return;

    setState(() {
      _guardando = true;
    });

    try {
      final mensaje = _mensajeController.text.trim().isEmpty
          ? 'Es hora de tu alarma'
          : _mensajeController.text.trim();

      final dias = _diasSeleccionados.toList()..sort();

      await AlarmasLocalService.crearAlarma(
        hour: _hour,
        minute: _minute,
        mensaje: mensaje,
        diasSemana: dias,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alarma guardada correctamente'),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      final message = e.toString().replaceFirst('Exception: ', '');
      final exactAlarmIssue =
          message.contains('exact_alarms_not_permitted') ||
          message.contains('alarmas exactas');

      if (exactAlarmIssue) {
        final abrir = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permiso requerido'),
            content: const Text(
              'Tu telefono no permite alarmas exactas. Necesitas habilitar ese permiso para que EVA pueda guardar y sonar a la hora correcta.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Abrir ajustes'),
              ),
            ],
          ),
        );

        if (abrir == true) {
          await NotificacionService.abrirAjustesAlarmasExactas();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  Widget _botonNumero({
    required String texto,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 70,
      height: 70,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFBFDBFE),
          foregroundColor: const Color(0xFF1E3A8A),
          shape: const CircleBorder(),
          elevation: 4,
        ),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _botonGrande({
    required String texto,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _paso1() {
    return Column(
      children: [
        const Text(
          '⏰',
          style: TextStyle(fontSize: 60),
        ),
        const SizedBox(height: 10),
        const Text(
          'Selecciona la hora',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E3A8A),
          ),
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [
                _botonNumero(texto: '+', onTap: _sumarHora),
                const SizedBox(height: 10),
                Text(
                  _hour.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 54,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 10),
                _botonNumero(texto: '−', onTap: _restarHora),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                ':',
                style: TextStyle(
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ),
            Column(
              children: [
                _botonNumero(texto: '+', onTap: _sumarMinuto),
                const SizedBox(height: 10),
                Text(
                  _minute.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 54,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 10),
                _botonNumero(texto: '−', onTap: _restarMinuto),
              ],
            ),
          ],
        ),
        const SizedBox(height: 30),
        _botonGrande(
          texto: 'Continuar',
          color: const Color(0xFF16A34A),
          onTap: () {
            setState(() {
              _paso = 2;
            });
          },
        ),
      ],
    );
  }

  Widget _paso2() {
    final dias = [
      (1, 'Lun'),
      (2, 'Mar'),
      (3, 'Mié'),
      (4, 'Jue'),
      (5, 'Vie'),
      (6, 'Sáb'),
      (7, 'Dom'),
    ];

    return Column(
      children: [
        const Text(
          '📅',
          style: TextStyle(fontSize: 54),
        ),
        const SizedBox(height: 10),
        const Text(
          '¿Qué días quieres repetirla?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E3A8A),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Si no eliges días, será una sola vez.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            color: Color(0xFF4B5563),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: dias.map((item) {
            final dia = item.$1;
            final texto = item.$2;
            final selected = _diasSeleccionados.contains(dia);

            return SizedBox(
              width: 92,
              height: 62,
              child: ElevatedButton(
                onPressed: () => _toggleDia(dia),
                style: ElevatedButton.styleFrom(
                  backgroundColor: selected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFE5E7EB),
                  foregroundColor: selected ? Colors.white : Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  texto,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: _botonGrande(
                texto: 'Atrás',
                color: const Color(0xFF9CA3AF),
                onTap: () {
                  setState(() {
                    _paso = 1;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _botonGrande(
                texto: 'Continuar',
                color: const Color(0xFF16A34A),
                onTap: () {
                  setState(() {
                    _paso = 3;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _paso3() {
    return Column(
      children: [
        const Text(
          '💊',
          style: TextStyle(fontSize: 54),
        ),
        const SizedBox(height: 10),
        const Text(
          'Escribe el nombre o mensaje',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E3A8A),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Hora seleccionada: $_horaTexto',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _mensajeController,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: 'Ej. Tomar medicamento',
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 22,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(
                color: Color(0xFF60A5FA),
                width: 3,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(
                color: Color(0xFF60A5FA),
                width: 3,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(
                color: Color(0xFF2563EB),
                width: 3,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: _botonGrande(
                texto: 'Atrás',
                color: const Color(0xFF9CA3AF),
                onTap: () {
                  setState(() {
                    _paso = 2;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _botonGrande(
                texto: _guardando ? 'Guardando...' : 'Guardar',
                color: const Color(0xFF16A34A),
                onTap: _guardando ? () {} : _guardarAlarma,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF173A8A),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Nueva alarma',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 14,
                    color: Colors.black12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: _paso == 1
                  ? _paso1()
                  : _paso == 2
                      ? _paso2()
                      : _paso3(),
            ),
          ),
        ),
      ),
    );
  }
}
