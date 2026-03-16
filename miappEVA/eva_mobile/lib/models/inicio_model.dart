class OrdenInicio {
  final int id;
  final String texto;
  final String respuesta;
  final String intent;
  final String fecha;

  OrdenInicio({
    required this.id,
    required this.texto,
    required this.respuesta,
    required this.intent,
    required this.fecha,
  });

  factory OrdenInicio.fromJson(Map<String, dynamic> json) {
    return OrdenInicio(
      id: json['id'] ?? 0,
      texto: json['texto'] ?? '',
      respuesta: json['respuesta'] ?? '',
      intent: json['intent'] ?? '',
      fecha: json['fecha'] ?? '',
    );
  }
}

class InicioModel {
  final String nombre;
  final String? codigoUnico;
  final bool esPremium;
  final bool estaVinculado;
  final List<OrdenInicio> ultimas;

  InicioModel({
    required this.nombre,
    required this.codigoUnico,
    required this.esPremium,
    required this.estaVinculado,
    required this.ultimas,
  });

  factory InicioModel.fromJson(Map<String, dynamic> json) {
    final ultimasJson = json['ultimas'] as List<dynamic>? ?? [];

    return InicioModel(
      nombre: json['nombre'] ?? '',
      codigoUnico: json['codigo_unico'],
      esPremium: json['es_premium'] ?? false,
      estaVinculado: json['esta_vinculado'] ?? false,
      ultimas: ultimasJson
          .map((e) => OrdenInicio.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}