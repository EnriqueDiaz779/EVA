import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cuidador_inicio_model.dart';

class CuidadorService {
  static const String baseUrl = 'http://192.168.1.3:8000';

  static Future<CuidadorInicioModel> obtenerInicioCuidador({
    required String username,
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/v1/interfaz-cuidador/?username=$username',
    );

    final response = await http.get(url);
    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['ok'] != true) {
      throw Exception(
        data['error'] ?? 'No se pudo cargar la interfaz del cuidador.',
      );
    }

    return CuidadorInicioModel.fromJson(data);
  }

  static Future<Map<String, dynamic>> vincularAdultoPorCodigo({
    required String username,
    required String codigo,
  }) async {
    final url = Uri.parse('$baseUrl/vincular-adulto-por-codigo/');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'username': username,
        'codigo': codigo.trim().toUpperCase(),
      },
    );

    final data = jsonDecode(response.body);

    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'No se pudo vincular el adulto.');
    }

    return data;
  }
}

