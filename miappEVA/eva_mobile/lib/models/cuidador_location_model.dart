class CuidadorLocationPoint {
  final double lat;
  final double lng;
  final double? accuracy;
  final DateTime? timestamp;

  const CuidadorLocationPoint({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.timestamp,
  });

  factory CuidadorLocationPoint.fromJson(Map<String, dynamic> json) {
    return CuidadorLocationPoint(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      accuracy: json['accuracy'] is num ? (json['accuracy'] as num).toDouble() : null,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString())
          : null,
    );
  }
}

class CuidadorLocationAdult {
  final int? id;
  final String nombre;

  const CuidadorLocationAdult({
    required this.id,
    required this.nombre,
  });

  factory CuidadorLocationAdult.fromJson(Map<String, dynamic> json) {
    return CuidadorLocationAdult(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}'),
      nombre: (json['nombre'] ?? '').toString(),
    );
  }
}

class CuidadorLocationState {
  final bool ok;
  final CuidadorLocationAdult? adult;
  final bool compartirUbicacion;
  final bool sinSenal;
  final CuidadorLocationPoint? latest;

  const CuidadorLocationState({
    required this.ok,
    required this.adult,
    required this.compartirUbicacion,
    required this.sinSenal,
    required this.latest,
  });

  factory CuidadorLocationState.fromJson(Map<String, dynamic> json) {
    return CuidadorLocationState(
      ok: json['ok'] == true,
      adult: json['adulto'] is Map<String, dynamic>
          ? CuidadorLocationAdult.fromJson(json['adulto'] as Map<String, dynamic>)
          : null,
      compartirUbicacion: json['compartir_ubicacion'] == true,
      sinSenal: json['sin_senal'] == true,
      latest: json['ultima'] is Map<String, dynamic>
          ? CuidadorLocationPoint.fromJson(json['ultima'] as Map<String, dynamic>)
          : null,
    );
  }
}
