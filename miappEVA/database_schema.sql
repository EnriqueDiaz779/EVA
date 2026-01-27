CREATE DATABASE IF NOT EXISTS eva_db
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'eva_user'@'localhost' IDENTIFIED BY 'TuPasswordSegura123!';
GRANT ALL PRIVILEGES ON eva_db.* TO 'eva_user'@'localhost';
FLUSH PRIVILEGES;

USE eva_db;

CREATE TABLE Usuarios (
  Id_Usuario INT AUTO_INCREMENT PRIMARY KEY,
  Nombre_Completo VARCHAR(128) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  Tipo ENUM('adulto','cuidador','admin') NOT NULL,
  correo VARCHAR(255) NULL UNIQUE,
  Telefono VARCHAR(20) NULL,
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  activo BOOL DEFAULT TRUE
);

CREATE TABLE adulto_cuidador (
  Id_AdultoCuidador INT AUTO_INCREMENT PRIMARY KEY,
  Codigo_unico VARCHAR(20) UNIQUE,
  Activo BOOL DEFAULT TRUE,
  fecha_asignacion DATETIME DEFAULT CURRENT_TIMESTAMP,
  Adulto_id INT NOT NULL,
  Cuidador_id INT NOT NULL,
  UNIQUE (Adulto_id, Cuidador_id),
  FOREIGN KEY (Adulto_id) REFERENCES Usuarios(Id_Usuario),
  FOREIGN KEY (Cuidador_id) REFERENCES Usuarios(Id_Usuario)
);

CREATE TABLE Alarma (
  Id_Alarma INT AUTO_INCREMENT PRIMARY KEY,
  Fecha_hora DATETIME NOT NULL,
  Mensaje VARCHAR(255) NOT NULL,
  Estado ENUM('pendiente','enviada','atendida','cancelada') DEFAULT 'pendiente',
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  Usuario_id INT NOT NULL,
  FOREIGN KEY (Usuario_id) REFERENCES Usuarios(Id_Usuario),
  INDEX idx_alarma_usuario_fecha (Usuario_id, Fecha_hora)
);

CREATE TABLE Medicamento_reconocido (
  Id_reconocimiento INT AUTO_INCREMENT PRIMARY KEY,
  imagen_ruta VARCHAR(300) NOT NULL,
  Estado ENUM('pendiente','reconocido','no_reconocido','error') DEFAULT 'pendiente',
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  usuario_id INT NOT NULL,
  FOREIGN KEY (usuario_id) REFERENCES Usuarios(Id_Usuario)
);

CREATE TABLE Orden_voz (
  Id_Orden INT AUTO_INCREMENT PRIMARY KEY,
  Texto TEXT NOT NULL,
  intent VARCHAR(100) NULL,
  respuesta TEXT NULL,
  meta JSON NULL,
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  Usuario_id INT NOT NULL,
  FOREIGN KEY (Usuario_id) REFERENCES Usuarios(Id_Usuario),
  INDEX idx_orden_usuario_fecha (Usuario_id, creado_en)
);

CREATE TABLE Patron_voz (
  Id INT AUTO_INCREMENT PRIMARY KEY,
  comando_original VARCHAR(255) NOT NULL,
  texto_reconocido VARCHAR(255) NOT NULL,
  similitud DECIMAL(5,4) NOT NULL,
  aciertos INT DEFAULT 0,
  errores INT DEFAULT 0,
  ultimo_uso DATETIME NULL,
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  Usuario_id INT NOT NULL,
  FOREIGN KEY (Usuario_id) REFERENCES Usuarios(Id_Usuario),
  UNIQUE (Usuario_id, comando_original)
);

CREATE TABLE push_tokens (
  Id_push INT AUTO_INCREMENT PRIMARY KEY,
  endpoint VARCHAR(500) NOT NULL UNIQUE,
  auth VARCHAR(255) NOT NULL,
  p256dh VARCHAR(255) NOT NULL,
  activo BOOL DEFAULT TRUE,
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  usuario_id INT NOT NULL,
  FOREIGN KEY (usuario_id) REFERENCES Usuarios(Id_Usuario)
);

CREATE TABLE chat_voz (
  id INT AUTO_INCREMENT PRIMARY KEY,
  mensaje TEXT NULL,
  audio_ruta VARCHAR(255) NULL,
  tipo ENUM('texto','audio') NOT NULL,
  duracion_segundos INT NULL,
  escuchado BOOL DEFAULT FALSE,
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  adulto_id INT NOT NULL,
  cuidador_id INT NOT NULL,
  emisor_id INT NOT NULL,
  FOREIGN KEY (adulto_id) REFERENCES Usuarios(Id_Usuario),
  FOREIGN KEY (cuidador_id) REFERENCES Usuarios(Id_Usuario),
  FOREIGN KEY (emisor_id) REFERENCES Usuarios(Id_Usuario),
  INDEX idx_chat_conv (adulto_id, cuidador_id, creado_en)
);

CREATE TABLE ubicacion_actual (
  usuario_id INT PRIMARY KEY,
  lat DECIMAL(10,7) NOT NULL,
  lng DECIMAL(10,7) NOT NULL,
  precision_m FLOAT NULL,
  actualizado_en DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (usuario_id) REFERENCES Usuarios(Id_Usuario)
);

CREATE TABLE emergencia (
  id_emergencia INT AUTO_INCREMENT PRIMARY KEY,
  lat DECIMAL(10,7) NULL,
  lng DECIMAL(10,7) NULL,
  estado ENUM('enviada','vista','atendida','cerrada') DEFAULT 'enviada',
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  atendido_en DATETIME NULL,
  adulto_id INT NOT NULL,
  cuidador_id INT NULL,
  FOREIGN KEY (adulto_id) REFERENCES Usuarios(Id_Usuario),
  FOREIGN KEY (cuidador_id) REFERENCES Usuarios(Id_Usuario),
  INDEX idx_emergencia_adulto (adulto_id, estado, creado_en)
);

CREATE TABLE membresia (
  id_membresia INT AUTO_INCREMENT PRIMARY KEY,
  fecha_pago DATE NOT NULL,
  fecha_renovacion DATE NOT NULL,
  estado ENUM('activa','vencida','cancelada') DEFAULT 'activa',
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  cuidador_id INT NOT NULL,
  FOREIGN KEY (cuidador_id) REFERENCES Usuarios(Id_Usuario)
);

CREATE TABLE reportes (
  id_reporte INT AUTO_INCREMENT PRIMARY KEY,
  accion VARCHAR(120) NOT NULL,
  detalles TEXT NULL,
  creado_en DATETIME DEFAULT CURRENT_TIMESTAMP,
  admin_id INT NOT NULL,
  FOREIGN KEY (admin_id) REFERENCES Usuarios(Id_Usuario)
);

CREATE TABLE registros_login (
  id_registro INT AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT NOT NULL,
  ip_address VARCHAR(45) NULL,
  fecha_entrada DATETIME DEFAULT CURRENT_TIMESTAMP,
  fecha_salida DATETIME NULL,
  user_agent VARCHAR(500) NULL,
  activo BOOL DEFAULT TRUE,
  FOREIGN KEY (usuario_id) REFERENCES Usuarios(Id_Usuario),
  INDEX idx_login_usuario_fecha (usuario_id, fecha_entrada)
);
