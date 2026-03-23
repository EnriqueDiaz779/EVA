import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/cuidador_medicamento_alerta.dart';

class CuidadorAlertasService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  static Future<String> _getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('userData');
    if (rawUser == null || rawUser.isEmpty) {
      throw Exception('No encontre el usuario logueado.');
    }

    final data = jsonDecode(rawUser) as Map<String, dynamic>;
    final username = (data['username'] ?? '').toString().trim();
    if (username.isEmpty) {
      throw Exception('No encontre el usuario logueado.');
    }
    return username;
  }

  static Future<List<CuidadorMedicamentoAlerta>>
      obtenerMedicamentosNoConfirmados() async {
    final username = await _getUsername();
    final uri = Uri.parse(
      '$baseUrl/api/v1/cuidador/alertas/medicamentos/?username=$username',
    );

    final response = await http.get(uri);
    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude cargar las alertas del cuidador.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude cargar las alertas del cuidador.');
    }

    final items = (data['alertas'] as List<dynamic>? ?? const []);
    return items
        .map(
          (item) => CuidadorMedicamentoAlerta.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
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
