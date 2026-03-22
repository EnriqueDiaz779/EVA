import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = 'http://192.168.1.13:8000';

  static Future<Map<String, dynamic>> loginConNombre({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/login-nombre/');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['ok'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userData', jsonEncode(data['user']));
      return data;
    } else {
      throw Exception(data['error'] ?? 'Error al iniciar sesión');
    }
  }

  static Future<Map<String, dynamic>> registerCuidador({
    required String nombreCompleto,
    required String correo,
    required String telefono,
    required String password,
    required bool pagoCompletado,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/register/cuidador/');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'nombre_completo': nombreCompleto,
        'correo': correo,
        'telefono': telefono,
        'password': password,
        'pago_completado': pagoCompletado,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['ok'] == true) {
      return data;
    } else {
      throw Exception(data['error'] ?? 'Error al registrar cuidador');
    }
  }

  static Future<Map<String, dynamic>> registerAdulto({
    required String nombreCompleto,
    required String correo,
    required String telefono,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/register/adulto/');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'nombre_completo': nombreCompleto,
        'correo': correo,
        'telefono': telefono,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['ok'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userData', jsonEncode(data['user']));
      return data;
    } else {
      throw Exception(data['error'] ?? 'Error al registrar adulto mayor');
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userData');
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }
}

