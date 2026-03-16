class CuidadorInicioModel {
  final bool ok;
  final CuidadorData cuidador;
  final AdultoVinculado? adultoVinculado;
  final bool bloqueadoPorVinculo;

  CuidadorInicioModel({
    required this.ok,
    required this.cuidador,
    required this.adultoVinculado,
    required this.bloqueadoPorVinculo,
  });

  factory CuidadorInicioModel.fromJson(Map<String, dynamic> json) {
    return CuidadorInicioModel(
      ok: json['ok'] == true,
      cuidador: CuidadorData.fromJson(json['cuidador'] ?? {}),
      adultoVinculado: json['adulto_vinculado'] != null
          ? AdultoVinculado.fromJson(json['adulto_vinculado'])
          : null,
      bloqueadoPorVinculo: json['bloqueado_por_vinculo'] == true,
    );
  }
}

class CuidadorData {
  final int? id;
  final String nombre;
  final String correo;
  final String telefono;

  CuidadorData({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.telefono,
  });

  factory CuidadorData.fromJson(Map<String, dynamic> json) {
    return CuidadorData(
      id: json['id'],
      nombre: json['nombre']?.toString() ?? '',
      correo: json['correo']?.toString() ?? '',
      telefono: json['telefono']?.toString() ?? '',
    );
  }
}

class AdultoVinculado {
  final int? id;
  final String nombre;

  AdultoVinculado({
    required this.id,
    required this.nombre,
  });

  factory AdultoVinculado.fromJson(Map<String, dynamic> json) {
    return AdultoVinculado(
      id: json['id'],
      nombre: json['nombre']?.toString() ?? '',
    );
  }
}