class EmergenciaModel {
  final int idEmergencia;
  final double? lat;
  final double? lng;
  final String estado;
  final String? creadoEn;
  final String? atendidoEn;
  final String? adultoNombre;

  EmergenciaModel({
    required this.idEmergencia,
    required this.estado,
    this.lat,
    this.lng,
    this.creadoEn,
    this.atendidoEn,
    this.adultoNombre,
  });

  factory EmergenciaModel.fromJson(Map<String, dynamic> json) {
    final adulto = json['adulto'];

    return EmergenciaModel(
      idEmergencia: int.tryParse(json['id_emergencia'].toString()) ?? 0,
      lat: json['lat'] != null ? double.tryParse(json['lat'].toString()) : null,
      lng: json['lng'] != null ? double.tryParse(json['lng'].toString()) : null,
      estado: (json['estado'] ?? '').toString(),
      creadoEn: json['creado_en']?.toString(),
      atendidoEn: json['atendido_en']?.toString(),
      adultoNombre: adulto is Map ? adulto['nombre']?.toString() : null,
    );
  }
}