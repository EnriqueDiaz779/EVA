class ChatMessageModel {
  final int id;
  final String mensaje;
  final DateTime? creadoEn;
  final int emisorId;
  final bool escuchado;
  final String tipo;

  ChatMessageModel({
    required this.id,
    required this.mensaje,
    required this.creadoEn,
    required this.emisorId,
    required this.escuchado,
    required this.tipo,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['creado_en']?.toString();
    return ChatMessageModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      mensaje: json['mensaje']?.toString() ?? '',
      creadoEn: createdRaw == null || createdRaw.isEmpty
          ? null
          : DateTime.tryParse(createdRaw),
      emisorId: (json['emisor_id'] as num?)?.toInt() ?? 0,
      escuchado: json['escuchado'] == true,
      tipo: json['tipo']?.toString() ?? 'texto',
    );
  }
}
