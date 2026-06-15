import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/inicio_model.dart';

class InicioService {

  static Future<InicioModel> obtenerInicio() async {
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

    final url = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/inicio/?username=$username');

    final response = await http.get(url, headers: {
      'Content-Type': 'application/json',
    });

    final body = response.body;

    if (body.trim().startsWith('<!DOCTYPE html>')) {
      throw Exception('El servidor devolvió HTML en lugar de JSON. Revisa la vista api_v1_inicio.');
    }

    final data = jsonDecode(body);

    if (response.statusCode == 200 && data['ok'] == true) {
      return InicioModel.fromJson(data);
    } else {
      throw Exception(data['error'] ?? 'Error al cargar inicio');
    }
  }
}

