import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class AdultoLocationState {
  final bool enabled;
  final String? updatedAt;

  const AdultoLocationState({
    required this.enabled,
    required this.updatedAt,
  });

  factory AdultoLocationState.fromJson(Map<String, dynamic> json) {
    return AdultoLocationState(
      enabled: json['compartir_ubicacion'] == true,
      updatedAt: json['ubicacion_actualizada_en']?.toString(),
    );
  }
}

class AdultoLocationService {

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

  static Future<AdultoLocationState> obtenerEstado() async {
    final username = await _getUsername();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/ubicacion/estado/?username=$username');
    final response = await http.get(uri);
    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude cargar el estado de ubicacion.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude cargar el estado de ubicacion.');
    }

    return AdultoLocationState.fromJson(data);
  }

  static Future<AdultoLocationState> cambiarEstado(bool activar) async {
    final username = await _getUsername();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/ubicacion/toggle/');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'activar': activar,
      }),
    );
    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude actualizar la ubicacion.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude actualizar la ubicacion.');
    }

    return AdultoLocationState.fromJson(data);
  }

  static Future<void> enviarPing({
    required double lat,
    required double lng,
    double? accuracy,
  }) async {
    final username = await _getUsername();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/ubicacion/ping/');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
      }),
    );
    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude enviar la ubicacion actual.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude enviar la ubicacion actual.');
    }
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

