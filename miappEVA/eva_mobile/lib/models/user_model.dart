class UserModel {
  final String username;
  final String nombreCompleto;
  final String tipo;
  final String correo;
  final String? telefono;

  UserModel({
    required this.username,
    required this.nombreCompleto,
    required this.tipo,
    required this.correo,
    this.telefono,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      username: json['username'] ?? '',
      nombreCompleto: json['nombre_completo'] ?? '',
      tipo: json['tipo'] ?? '',
      correo: json['correo'] ?? '',
      telefono: json['telefono'],
    );
  }
}