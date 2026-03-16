import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class MedicamentoService {
  static const String baseUrl = 'http://10.0.2.2:8000';

  static Future<Map<String, dynamic>> analizarMedicamento({
    required File imageFile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString('userData');

    if (rawUser == null) {
      throw Exception('No hay sesión guardada.');
    }

    final user = jsonDecode(rawUser);
    final username = (user['username'] ?? '').toString().trim();

    if (username.isEmpty) {
      throw Exception('No se encontró el username guardado.');
    }

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
      throw Exception('El servidor devolvió HTML en lugar de JSON.');
    }

    final data = jsonDecode(body);

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data['error'] ?? 'Error al analizar medicamento');
    }
  }
}