class CuidadorMedicamentoAlerta {
  final int id;
  final String mensaje;
  final String hora;
  final String? fecha;
  final DateTime? disparadaAt;

  const CuidadorMedicamentoAlerta({
    required this.id,
    required this.mensaje,
    required this.hora,
    required this.fecha,
    required this.disparadaAt,
  });

  String get notificationKey {
    final stamp = disparadaAt?.toIso8601String() ?? 'sin-fecha';
    return '$id|$stamp';
  }

  factory CuidadorMedicamentoAlerta.fromJson(Map<String, dynamic> json) {
    final rawDisparada = json['disparada_at']?.toString();
    return CuidadorMedicamentoAlerta(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mensaje: json['mensaje']?.toString() ?? '',
      hora: json['hora']?.toString() ?? '',
      fecha: json['fecha']?.toString(),
      disparadaAt: rawDisparada == null || rawDisparada.isEmpty
          ? null
          : DateTime.tryParse(rawDisparada),
    );
  }
}
