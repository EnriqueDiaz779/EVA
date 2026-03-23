import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class VozService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  static Future<Map<String, dynamic>> registrarOrden({
    required String texto,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('userData');

    String username = '';
    if (rawUser != null) {
      final user = jsonDecode(rawUser);
      username = (user['username'] ?? '').toString();
    }

    final url = Uri.parse('$baseUrl/api/v1/voz/registrar-orden/');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'texto': texto,
        'username': username,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['ok'] == true) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data['error'] ?? 'Error al procesar la orden de voz');
    }
  }
}

