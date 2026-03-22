import 'package:flutter/material.dart';
import '../models/cuidador_agenda_item.dart';

class CuidadorCitaFormSheet extends StatefulWidget {
  final DateTime initialDate;
  final CuidadorAgendaItem? initialItem;

  const CuidadorCitaFormSheet({
    super.key,
    required this.initialDate,
    this.initialItem,
  });

  @override
  State<CuidadorCitaFormSheet> createState() => _CuidadorCitaFormSheetState();
}

class _CuidadorCitaFormSheetState extends State<CuidadorCitaFormSheet> {
  late final TextEditingController _placeController;
  late final TextEditingController _dateController;
  TimeOfDay? _selectedTime;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _placeController = TextEditingController(text: item?.title ?? '');
    _selectedDate = item?.date ?? widget.initialDate;
    _dateController = TextEditingController(
      text: _formatDisplayDate(_selectedDate!),
    );
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
    _placeController.dispose();
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? widget.initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _dateController.text = _formatDisplayDate(picked);
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

  void _save() {
    final place = _placeController.text.trim();
    if (place.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe el lugar de la cita.')),
      );
      return;
    }
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona fecha y hora.')),
      );
      return;
    }

    final existing = widget.initialItem;
    Navigator.pop(
      context,
      CuidadorAgendaItem(
        id: existing?.id ?? 0,
        title: place,
        timeText: _formatTime(_selectedTime!),
        date: _selectedDate,
        type: 'cita',
        active: existing?.active ?? true,
        daysText: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialItem != null;
    final media = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: media.viewInsets.bottom + media.padding.bottom + 1,
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
                        editing ? 'Editar cita' : 'Genera una alarma para una cita',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Selecciona la fecha de la cita.'),
                const SizedBox(height: 18),
                TextField(
                  controller: _placeController,
                  decoration: const InputDecoration(
                    labelText: 'Lugar',
                    hintText: 'Ej. IMSS / Hospital / Consultorio',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _dateController,
                  readOnly: true,
                  onTap: _pickDate,
                  decoration: const InputDecoration(
                    labelText: 'Fecha',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _pickTime,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        _selectedTime == null
                            ? 'Selecciona hora'
                            : _formatTime(_selectedTime!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF28469A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Crear alarma de cita'),
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
