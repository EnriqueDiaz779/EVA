class AlarmaLocal {
  final int id;
  final String mensaje;
  final int hour;
  final int minute;
  final String? fechaIso;
  final List<int> diasSemana;
  final bool activa;
  final String creadaEnIso;

  final String estado;
  final int vecesPospuesta;
  final String? ultimaAccionIso;

  const AlarmaLocal({
    required this.id,
    required this.mensaje,
    required this.hour,
    required this.minute,
    required this.fechaIso,
    required this.diasSemana,
    required this.activa,
    required this.creadaEnIso,
    required this.estado,
    required this.vecesPospuesta,
    required this.ultimaAccionIso,
  });

  bool get esRecurrente => diasSemana.isNotEmpty;

  String get horaTexto {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mensaje': mensaje,
      'hour': hour,
      'minute': minute,
      'fechaIso': fechaIso,
      'diasSemana': diasSemana,
      'activa': activa,
      'creadaEnIso': creadaEnIso,
      'estado': estado,
      'vecesPospuesta': vecesPospuesta,
      'ultimaAccionIso': ultimaAccionIso,
    };
  }

  factory AlarmaLocal.fromJson(Map<String, dynamic> json) {
    return AlarmaLocal(
      id: json['id'] as int,
      mensaje: (json['mensaje'] ?? '') as String,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      fechaIso: json['fechaIso'] as String?,
      diasSemana: (json['diasSemana'] as List? ?? [])
          .map((e) => e as int)
          .toList(),
      activa: json['activa'] as bool? ?? true,
      creadaEnIso: (json['creadaEnIso'] ?? DateTime.now().toIso8601String()) as String,
      estado: (json['estado'] ?? 'pendiente') as String,
      vecesPospuesta: json['vecesPospuesta'] as int? ?? 0,
      ultimaAccionIso: json['ultimaAccionIso'] as String?,
    );
  }

  AlarmaLocal copyWith({
    int? id,
    String? mensaje,
    int? hour,
    int? minute,
    String? fechaIso,
    List<int>? diasSemana,
    bool? activa,
    String? creadaEnIso,
    String? estado,
    int? vecesPospuesta,
    String? ultimaAccionIso,
  }) {
    return AlarmaLocal(
      id: id ?? this.id,
      mensaje: mensaje ?? this.mensaje,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      fechaIso: fechaIso ?? this.fechaIso,
      diasSemana: diasSemana ?? this.diasSemana,
      activa: activa ?? this.activa,
      creadaEnIso: creadaEnIso ?? this.creadaEnIso,
      estado: estado ?? this.estado,
      vecesPospuesta: vecesPospuesta ?? this.vecesPospuesta,
      ultimaAccionIso: ultimaAccionIso ?? this.ultimaAccionIso,
    );
  }
}