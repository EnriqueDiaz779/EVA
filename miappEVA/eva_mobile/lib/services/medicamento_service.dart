import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class MedicamentoService {
  static const String baseUrl = AppConfig.apiBaseUrl;

  static Future<String> _getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('userData');

    if (rawUser == null) {
      throw Exception('No hay sesion guardada.');
    }

    final user = jsonDecode(rawUser);
    final username = (user['username'] ?? '').toString().trim();

    if (username.isEmpty) {
      throw Exception('No se encontro el username guardado.');
    }

    return username;
  }

  static Future<Map<String, dynamic>> analizarMedicamento({
    required File imageFile,
  }) async {
    final username = await _getUsername();

    final uri = Uri.parse('$baseUrl/api/v1/medicamentos/analizar/');
    final request = http.MultipartRequest('POST', uri);

    request.fields['username'] = username;
    request.files.add(
      await http.MultipartFile.fromPath('foto', imageFile.path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final body = response.body;

    if (body.trim().startsWith('<!DOCTYPE html>')) {
      throw Exception('El servidor devolvio HTML en lugar de JSON.');
    }

    final data = jsonDecode(body);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data['error'] ?? 'Error al analizar medicamento');
    }
  }

  static Future<Map<String, dynamic>> crearAlarmasDesdeRecetaCuidador({
    required File imageFile,
  }) async {
    final username = await _getUsername();

    final uri = Uri.parse('$baseUrl/api/v1/cuidador/receta/crear-alarmas/');
    final request = http.MultipartRequest('POST', uri);

    request.fields['username'] = username;
    request.files.add(
      await http.MultipartFile.fromPath('foto', imageFile.path),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final body = response.body;

    if (body.trim().startsWith('<!DOCTYPE html>')) {
      throw Exception('El servidor devolvio HTML en lugar de JSON.');
    }

    final data = jsonDecode(body);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data['error'] ?? 'Error al procesar la receta.');
    }
  }
}

