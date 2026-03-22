import 'package:flutter/material.dart';
import '../models/cuidador_agenda_item.dart';
import 'cuidador_agenda_item.dart';

class CuidadorAgendaCard extends StatefulWidget {
  final List<CuidadorAgendaItem> items;
  final DateTime selectedDate;
  final ValueChanged<DateTime>? onSelectedDateChanged;
  final ValueChanged<DateTime>? onCreateAlarm;
  final ValueChanged<DateTime>? onCreateAppointment;
  final ValueChanged<CuidadorAgendaItem>? onEditItem;
  final ValueChanged<CuidadorAgendaItem>? onDeleteItem;

  const CuidadorAgendaCard({
    super.key,
    required this.items,
    required this.selectedDate,
    this.onSelectedDateChanged,
    this.onCreateAlarm,
    this.onCreateAppointment,
    this.onEditItem,
    this.onDeleteItem,
  });

  @override
  State<CuidadorAgendaCard> createState() => _CuidadorAgendaCardState();
}

class _CuidadorAgendaCardState extends State<CuidadorAgendaCard> {
  static const List<String> _weekdays = <String>[
    'LUNES',
    'MARTES',
    'MIERCOLES',
    'JUEVES',
    'VIERNES',
    'SABADO',
    'DOMINGO',
  ];

  static const List<String> _months = <String>[
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  String _formatLongDate(DateTime date) {
    final month = _months[date.month - 1];
    return '${date.day} de $month de ${date.year}';
  }

  String _weekdayLabel(DateTime date) {
    return _weekdays[date.weekday - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _matchesWeekday(CuidadorAgendaItem item) {
    final raw = item.daysText.trim().toLowerCase();
    if (raw.isEmpty) {
      return true;
    }

    const map = <int, List<String>>{
      1: ['lun', 'lunes'],
      2: ['mar', 'martes'],
      3: ['mie', 'miercoles', 'miércoles', 'mié'],
      4: ['jue', 'jueves'],
      5: ['vie', 'viernes'],
      6: ['sab', 'sábado', 'sabado', 'sáb'],
      7: ['dom', 'domingo'],
    };

    final tokens = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    final valid = map[widget.selectedDate.weekday] ?? const <String>[];
    for (final token in tokens) {
      if (valid.any((v) => token.startsWith(v))) {
        return true;
      }
    }
    return false;
  }

  List<CuidadorAgendaItem> _itemsForSelectedDay() {
    return widget.items
        .where((item) {
          if (item.date != null) {
            return _isSameDay(item.date!, widget.selectedDate);
          }
          return _matchesWeekday(item);
        })
        .toList()
      ..sort((a, b) => a.timeText.compareTo(b.timeText));
  }

  void _showCreateMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      builder: (context) {
        final media = MediaQuery.of(context);

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              media.padding.bottom + 42,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x25000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionTile(
                      label: 'Crear alarma',
                      onTap: () {
                        Navigator.pop(context);
                        widget.onCreateAlarm?.call(widget.selectedDate);
                      },
                    ),
                    Divider(
                      height: 1,
                      color: Colors.grey.shade200,
                    ),
                    _ActionTile(
                      label: 'Crear cita',
                      onTap: () {
                        Navigator.pop(context);
                        widget.onCreateAppointment?.call(widget.selectedDate);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _itemsForSelectedDay();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ArrowButton(
                icon: Icons.arrow_back,
                onTap: () {
                  widget.onSelectedDateChanged?.call(
                    widget.selectedDate.subtract(const Duration(days: 1)),
                  );
                },
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _formatLongDate(widget.selectedDate),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF32405D),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _weekdayLabel(widget.selectedDate),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF0E2D6D),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              _ArrowButton(
                icon: Icons.arrow_forward,
                onTap: () {
                  widget.onSelectedDateChanged?.call(
                    widget.selectedDate.add(const Duration(days: 1)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF28469A),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'NOMBRE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  'HORA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty) ...[
            const Text(
              'No hay alarmas ni citas para este dia.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF5E6A86),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tip: usa el boton + para agregar una cita y generar su alarma.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF98A2B7),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            ...items.map(
              (item) => CuidadorAgendaListItem(
                item: item,
                onEdit: () => widget.onEditItem?.call(item),
                onDelete: () => widget.onDeleteItem?.call(item),
              ),
            ),
          ],
          Center(
            child: GestureDetector(
              onTap: _showCreateMenu,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F3F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFD2D9E6),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add,
                  color: Color(0xFF2A426E),
                  size: 30,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD7DFEC),
          ),
        ),
        child: Icon(
          icon,
          color: const Color(0xFF20304D),
          size: 22,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF20304D),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
