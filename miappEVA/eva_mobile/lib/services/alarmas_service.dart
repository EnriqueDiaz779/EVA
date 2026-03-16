import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AlarmasService {
  static const String baseUrl = 'http://10.0.2.2:8000';

  static Future<String?> _getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('userData');
    if (rawUser == null) return null;

    try {
      final data = jsonDecode(rawUser);
      return data['username']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> obtenerPendientes() async {
    final username = await _getUsername();
    if (username == null || username.isEmpty) {
      throw Exception('No encontré el usuario logueado.');
    }

    final uri = Uri.parse(
      '$baseUrl/api/v1/alarmas/pendientes/?username=$username',
    );

    final response = await http.get(uri);
    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude obtener alarmas pendientes.');
    }

    final List alarmas = data['alarmas'] ?? [];
    return alarmas.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> marcarEntregada(int id) async {
    final username = await _getUsername();
    if (username == null || username.isEmpty) {
      throw Exception('No encontré el usuario logueado.');
    }

    final uri = Uri.parse('$baseUrl/api/v1/alarmas/marcar-entregada/');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'id': id,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['error'] ?? 'No pude marcar la alarma como entregada.',
      );
    }
  }
}