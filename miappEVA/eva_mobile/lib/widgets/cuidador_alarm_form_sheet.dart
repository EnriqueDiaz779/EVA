import 'package:flutter/material.dart';
import '../models/cuidador_agenda_item.dart';

class CuidadorAlarmFormSheet extends StatefulWidget {
  final DateTime initialDate;
  final CuidadorAgendaItem? initialItem;

  const CuidadorAlarmFormSheet({
    super.key,
    required this.initialDate,
    this.initialItem,
  });

  @override
  State<CuidadorAlarmFormSheet> createState() => _CuidadorAlarmFormSheetState();
}

class _CuidadorAlarmFormSheetState extends State<CuidadorAlarmFormSheet> {
  late final TextEditingController _messageController;
  late final TextEditingController _dateController;
  TimeOfDay? _selectedTime;
  DateTime? _selectedDate;
  bool _active = true;
  final Set<int> _selectedWeekdays = <int>{};

  static const List<({int value, String label})> _weekdayOptions = [
    (value: 1, label: 'L'),
    (value: 2, label: 'M'),
    (value: 3, label: 'M'),
    (value: 4, label: 'J'),
    (value: 5, label: 'V'),
    (value: 6, label: 'S'),
    (value: 7, label: 'D'),
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _messageController = TextEditingController(text: item?.title ?? '');
    _selectedDate = item?.date;
    _dateController = TextEditingController(
      text: item?.date != null ? _formatDisplayDate(item!.date!) : '',
    );
    _active = item?.active ?? true;
    _selectedWeekdays.addAll(_parseDaysText(item?.daysText ?? ''));
    if (item != null && item.timeText.contains(':')) {
      final parts = item.timeText.split(':');
      _selectedTime = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 8,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  String _formatDisplayDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  List<int> _parseDaysText(String raw) {
    if (raw.trim().isEmpty) return const [];

    const map = <String, int>{
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

    final out = <int>{};
    for (final token in raw.split(RegExp(r'[,;/]'))) {
      final day = map[token.trim().toLowerCase()];
      if (day != null) out.add(day);
    }
    return out.toList()..sort();
  }

  String _daysTextValue() {
    const labels = <int, String>{
      1: 'Lun',
      2: 'Mar',
      3: 'Mie',
      4: 'Jue',
      5: 'Vie',
      6: 'Sab',
      7: 'Dom',
    };

    final ordered = _selectedWeekdays.toList()..sort();
    return ordered.map((day) => labels[day]!).join(', ');
  }

  void _toggleWeekday(int value) {
    setState(() {
      if (_selectedWeekdays.contains(value)) {
        _selectedWeekdays.remove(value);
      } else {
        _selectedWeekdays.add(value);
      }
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedTime = picked;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? widget.initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _dateController.text = _formatDisplayDate(picked);
    });
  }

  void _save() {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe el nombre o mensaje.')),
      );
      return;
    }
    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una hora.')),
      );
      return;
    }

    final existing = widget.initialItem;
    Navigator.pop(
      context,
      CuidadorAgendaItem(
        id: existing?.id ?? 0,
        title: message,
        timeText: _formatTime(_selectedTime!),
        date: _selectedDate,
        type: 'alarma',
        active: _active,
        daysText: _daysTextValue(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialItem != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      editing ? 'Editar alarma' : 'Nueva alarma',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Se creara para el adulto vinculado.'),
              const SizedBox(height: 18),
              TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: 'Mensaje / Nombre',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(_selectedTime == null ? 'Selecciona hora' : _formatTime(_selectedTime!)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _dateController,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: const InputDecoration(
                        labelText: 'Fecha',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Dias (opcional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF344054),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _weekdayOptions.map((day) {
                  final selected = _selectedWeekdays.contains(day.value);
                  return GestureDetector(
                    onTap: () => _toggleWeekday(day.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF28469A)
                            : const Color(0xFFF4F6FB),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF28469A)
                              : const Color(0xFFD0D5DD),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          day.label,
                          style: TextStyle(
                            color: selected ? Colors.white : const Color(0xFF344054),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              if (_selectedWeekdays.isEmpty)
                const Text(
                  'Si no eliges dias, la alarma sera de una sola vez.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                )
              else
                Text(
                  'Repetir: ${_daysTextValue()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: _active,
                contentPadding: EdgeInsets.zero,
                onChanged: (value) {
                  setState(() {
                    _active = value ?? true;
                  });
                },
                title: const Text('Activa'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF28469A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
