import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/inicio_screen.dart';
import 'services/notificacion_service.dart';
import 'services/alarmas_local_service.dart';
import 'screens/cuidador_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificacionService.inicializar();
  runApp(const EvaApp());
}

class EvaApp extends StatefulWidget {
  const EvaApp({super.key});

  @override
  State<EvaApp> createState() => _EvaAppState();
}

class _EvaAppState extends State<EvaApp> {
  bool? isLoggedIn;
  String? tipoUsuario;
  String? usernameGuardado;

  @override
  void initState() {
    super.initState();
    verificarSesion();
    _reprogramarAlarmas();
  }

  Future<void> _reprogramarAlarmas() async {
    try {
      await AlarmasLocalService.reprogramarTodasLasActivas();
    } catch (e) {
      debugPrint('Error reprogramando alarmas: $e');
    }
  }

  Future<void> verificarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final logged = prefs.getBool('isLoggedIn') ?? false;
    final rawUser = prefs.getString('userData');

    String? tipo;
    String? username;

    if (rawUser != null) {
      try {
        final user = jsonDecode(rawUser);
        tipo = user['tipo'];
        username = user['username'];
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      isLoggedIn = logged;
      tipoUsuario = tipo;
      usernameGuardado = username;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget home;

    if (isLoggedIn == null) {
      home = const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    } else if (isLoggedIn == false) {
      home = const LoginScreen();
    } else {
      if (tipoUsuario == 'admin') {
        home = const PantallaAdmin();
      } else if (tipoUsuario == 'cuidador') {
        if (usernameGuardado != null && usernameGuardado!.isNotEmpty) {
          home = CuidadorScreen(username: usernameGuardado!);
        } else {
          home = const LoginScreen();
        }
      } else {
        home = const InicioScreen();
      }
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EVA',
      home: home,
      routes: {
        '/inicio': (context) => const InicioScreen(),
        '/admin': (context) => const PantallaAdmin(),
      },
    );
  }
}

class PantallaAdmin extends StatelessWidget {
  const PantallaAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Interfaz admin')),
    );
  }
}