import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cuidador_agenda_item.dart';

class CuidadorAgendaService {
  static const String baseUrl = 'http://192.168.1.13:8000';

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

  static Future<List<CuidadorAgendaItem>> obtenerAgenda() async {
    final username = await _getUsername();
    final uri = Uri.parse('$baseUrl/api/v1/cuidador/alarmas/?username=$username');

    final response = await http.get(uri);
    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude cargar la agenda del cuidador.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude cargar la agenda del cuidador.');
    }

    final List alarmas = data['alarmas'] ?? [];
    return alarmas
        .map((item) => CuidadorAgendaItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<void> crearItem({
    required String title,
    required String type,
    required String timeText,
    DateTime? date,
    String daysText = '',
    bool active = true,
  }) async {
    final username = await _getUsername();
    final uri = Uri.parse('$baseUrl/api/v1/cuidador/alarmas/crear/');
    final message = type == 'cita' ? 'Cita: ${title.trim()}' : title.trim();

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'mensaje': message,
        'hora': timeText,
        'fecha': date != null ? _formatDate(date) : null,
        'dias': daysText,
        'activa': active,
      }),
    );

    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude crear el elemento.',
    );
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude crear el elemento.');
    }
  }

  static Future<void> editarItem(CuidadorAgendaItem item) async {
    final username = await _getUsername();
    final uri = Uri.parse('$baseUrl/api/v1/cuidador/alarmas/editar/');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'id': item.id,
        'mensaje': item.apiMessage,
        'hora': item.timeText,
        'fecha': item.date != null ? _formatDate(item.date!) : null,
        'dias': item.daysText,
        'activa': item.active,
      }),
    );

    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude editar el elemento.',
    );
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude editar el elemento.');
    }
  }

  static Future<void> eliminarItem(int id) async {
    final username = await _getUsername();
    final uri = Uri.parse('$baseUrl/api/v1/cuidador/alarmas/eliminar/');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'id': id,
      }),
    );

    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude eliminar el elemento.',
    );
    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude eliminar el elemento.');
    }
  }

  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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

