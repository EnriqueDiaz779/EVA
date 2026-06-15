import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/emergencia_model.dart';

class EmergenciaService {

  static Future<Map<String, dynamic>> crearEmergencia({
    required String username,
    double? lat,
    double? lng,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/emergencia/crear/'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'lat': lat,
        'lng': lng,
      }),
    );

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    }

    throw Exception(
      (data['error'] ?? 'No se pudo crear la emergencia.').toString(),
    );
  }

  static Future<List<EmergenciaModel>> obtenerPendientes({
    required String username,
  }) async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/emergencia/pendientes/?username=$username'),
    );

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode == 200) {
      final lista = (data['emergencias'] as List? ?? []);
      return lista
          .map((e) => EmergenciaModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    throw Exception(
      (data['error'] ?? 'No se pudieron obtener las emergencias.').toString(),
    );
  }

  static Future<Map<String, dynamic>> actualizarEstado({
    required String username,
    required int idEmergencia,
    required String estado,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/emergencia/actualizar/'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'id_emergencia': idEmergencia,
        'estado': estado,
      }),
    );

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    }

    throw Exception(
      (data['error'] ?? 'No se pudo actualizar la emergencia.').toString(),
    );
  }
}
