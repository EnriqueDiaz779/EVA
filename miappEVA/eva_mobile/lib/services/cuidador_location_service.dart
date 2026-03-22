import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cuidador_location_model.dart';

class CuidadorLocationService {
  static const String baseUrl = 'http://192.168.1.3:8000';

  static Future<String> _getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('userData');
    if (rawUser == null || rawUser.isEmpty) {
      throw Exception('No encontre el usuario logueado.');
    }

    final data = jsonDecode(rawUser);
    final username = (data['username'] ?? '').toString().trim();
    if (username.isEmpty) {
      throw Exception('No encontre el usuario logueado.');
    }
    return username;
  }

  static Future<CuidadorLocationState> obtenerUltimaUbicacion() async {
    final username = await _getUsername();
    final uri = Uri.parse('$baseUrl/api/v1/cuidador/ubicacion/ultima/?username=$username');
    final response = await http.get(uri);
    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude cargar la ubicacion.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude cargar la ubicacion.');
    }

    return CuidadorLocationState.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<List<CuidadorLocationPoint>> obtenerHistorial({
    int hours = 24,
    int limit = 1200,
  }) async {
    final username = await _getUsername();
    final uri = Uri.parse(
      '$baseUrl/api/v1/cuidador/ubicacion/historial/?username=$username&horas=$hours&limite=$limit',
    );
    final response = await http.get(uri);
    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude cargar el historial de ubicacion.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude cargar el historial de ubicacion.');
    }

    final List points = data['puntos'] ?? [];
    return points
        .map((item) => CuidadorLocationPoint.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Map<String, dynamic> _decodeJsonResponse(
    http.Response response, {
    required String defaultMessage,
  }) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{
        'ok': false,
        'error': defaultMessage,
      };
    } catch (_) {
      final body = response.body.trim();
      final preview = body.length > 140 ? '${body.substring(0, 140)}...' : body;
      return <String, dynamic>{
        'ok': false,
        'error': 'El servidor no devolvio JSON. Codigo ${response.statusCode}. $preview',
      };
    }
  }
}

