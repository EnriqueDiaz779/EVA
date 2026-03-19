class CuidadorAgendaItem {
  final int id;
  final String title;
  final String timeText;
  final DateTime? date;
  final String type;
  final bool active;
  final String daysText;

  const CuidadorAgendaItem({
    required this.id,
    required this.title,
    required this.timeText,
    required this.date,
    required this.type,
    required this.active,
    required this.daysText,
  });

  bool get isAppointment => type == 'cita';

  factory CuidadorAgendaItem.fromJson(Map<String, dynamic> json) {
    final rawMessage = (json['mensaje'] ?? '').toString().trim();
    final normalized = rawMessage.toLowerCase();
    final type = normalized.startsWith('cita:') ? 'cita' : 'alarma';
    final visibleTitle = type == 'cita'
        ? rawMessage.replaceFirst(RegExp(r'^cita:\s*', caseSensitive: false), '')
        : rawMessage;

    final fechaRaw = json['fecha']?.toString();
    return CuidadorAgendaItem(
      id: int.tryParse('${json['id']}') ?? 0,
      title: visibleTitle.isEmpty ? 'Sin nombre' : visibleTitle,
      timeText: (json['hora'] ?? '').toString(),
      date: fechaRaw != null && fechaRaw.isNotEmpty
          ? DateTime.tryParse(fechaRaw)
          : null,
      type: type,
      active: json['activa'] != false,
      daysText: (json['dias'] ?? '').toString(),
    );
  }

  String get apiMessage {
    final base = title.trim();
    if (isAppointment) {
      return 'Cita: $base';
    }
    return base;
  }
}
