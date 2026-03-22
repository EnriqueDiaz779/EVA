import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message_model.dart';

class ChatFetchResult {
  final int adultoId;
  final int cuidadorId;
  final int emisorId;
  final String tipoUsuario;
  final int lastId;
  final List<ChatMessageModel> mensajes;

  ChatFetchResult({
    required this.adultoId,
    required this.cuidadorId,
    required this.emisorId,
    required this.tipoUsuario,
    required this.lastId,
    required this.mensajes,
  });
}

class ChatService {
  static const String baseUrl = 'http://192.168.1.13:8000';

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

  static Future<ChatFetchResult> obtenerMensajes({
    int afterId = 0,
    int limit = 50,
  }) async {
    final username = await _getUsername();
    final uri = Uri.parse(
      '$baseUrl/api/v1/chat/mensajes/?username=$username&after_id=$afterId&limit=$limit',
    );

    final response = await http.get(uri);
    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude cargar los mensajes del chat.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude cargar los mensajes del chat.');
    }

    final mensajes = (data['mensajes'] as List<dynamic>? ?? [])
        .map((item) => ChatMessageModel.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    return ChatFetchResult(
      adultoId: (data['adulto_id'] as num?)?.toInt() ?? 0,
      cuidadorId: (data['cuidador_id'] as num?)?.toInt() ?? 0,
      emisorId: (data['emisor_id'] as num?)?.toInt() ?? 0,
      tipoUsuario: data['tipo_usuario']?.toString() ?? '',
      lastId: (data['last_id'] as num?)?.toInt() ?? afterId,
      mensajes: mensajes,
    );
  }

  static Future<void> enviarMensaje({
    required String mensaje,
    String tipo = 'texto',
  }) async {
    final username = await _getUsername();
    final uri = Uri.parse('$baseUrl/api/v1/chat/enviar/');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'mensaje': mensaje.trim(),
        'tipo': tipo,
      }),
    );

    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude enviar el mensaje.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude enviar el mensaje.');
    }
  }

  static Future<void> marcarVistos({int? upToId}) async {
    final username = await _getUsername();
    final uri = Uri.parse('$baseUrl/api/v1/chat/marcar-visto/');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'up_to_id': upToId,
      }),
    );

    final data = _decodeJsonResponse(
      response,
      defaultMessage: 'No pude actualizar el estado del chat.',
    );

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'No pude actualizar el estado del chat.');
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

