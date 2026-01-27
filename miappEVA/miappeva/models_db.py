# This is an auto-generated Django model module.
# These models map to existing tables in the database.
# Django will NOT create, modify, or delete these tables (managed = False)

from django.db import models


class Usuarios(models.Model):
    id_usuario = models.AutoField(db_column='Id_Usuario', primary_key=True)
    nombre_completo = models.CharField(db_column='Nombre_Completo', max_length=128)
    password_hash = models.CharField(max_length=255)
    tipo = models.CharField(db_column='Tipo', max_length=8)
    correo = models.CharField(unique=True, max_length=255, blank=True, null=True)
    telefono = models.CharField(db_column='Telefono', max_length=20, blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    activo = models.IntegerField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'usuarios'

    def __str__(self):
        return self.nombre_completo


class AdultoCuidador(models.Model):
    id_adultocuidador = models.AutoField(db_column='Id_AdultoCuidador', primary_key=True)
    codigo_unico = models.CharField(db_column='Codigo_unico', unique=True, max_length=20, blank=True, null=True)
    activo = models.IntegerField(db_column='Activo', blank=True, null=True)
    fecha_asignacion = models.DateTimeField(blank=True, null=True)
    adulto = models.ForeignKey(Usuarios, models.DO_NOTHING, db_column='Adulto_id')
    cuidador = models.ForeignKey(Usuarios, models.DO_NOTHING, db_column='Cuidador_id', related_name='adultocuidador_cuidador_set')

    class Meta:
        managed = False
        db_table = 'adulto_cuidador'
        unique_together = (('adulto', 'cuidador'),)


class Alarma(models.Model):
    id_alarma = models.AutoField(db_column='Id_Alarma', primary_key=True)
    fecha_hora = models.DateTimeField(db_column='Fecha_hora')
    mensaje = models.CharField(db_column='Mensaje', max_length=255)
    estado = models.CharField(db_column='Estado', max_length=9, blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    usuario = models.ForeignKey(Usuarios, models.DO_NOTHING, db_column='Usuario_id')

    class Meta:
        managed = False
        db_table = 'alarma'


class MedicamentoReconocido(models.Model):
    id_reconocimiento = models.AutoField(db_column='Id_reconocimiento', primary_key=True)
    imagen_ruta = models.CharField(max_length=300)
    estado = models.CharField(db_column='Estado', max_length=13, blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    usuario = models.ForeignKey(Usuarios, models.DO_NOTHING)

    class Meta:
        managed = False
        db_table = 'medicamento_reconocido'


class OrdenVoz(models.Model):
    id_orden = models.AutoField(db_column='Id_Orden', primary_key=True)
    texto = models.TextField(db_column='Texto')
    intent = models.CharField(max_length=100, blank=True, null=True)
    respuesta = models.TextField(blank=True, null=True)
    meta = models.JSONField(blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    usuario = models.ForeignKey(Usuarios, models.DO_NOTHING, db_column='Usuario_id')

    class Meta:
        managed = False
        db_table = 'orden_voz'


class PatronVoz(models.Model):
    id = models.AutoField(db_column='Id', primary_key=True)
    comando_original = models.CharField(max_length=255)
    texto_reconocido = models.CharField(max_length=255)
    similitud = models.DecimalField(max_digits=5, decimal_places=4)
    aciertos = models.IntegerField(blank=True, null=True)
    errores = models.IntegerField(blank=True, null=True)
    ultimo_uso = models.DateTimeField(blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    usuario = models.ForeignKey(Usuarios, models.DO_NOTHING, db_column='Usuario_id')

    class Meta:
        managed = False
        db_table = 'patron_voz'
        unique_together = (('usuario', 'comando_original'),)


class PushTokens(models.Model):
    id_push = models.AutoField(db_column='Id_push', primary_key=True)
    endpoint = models.CharField(unique=True, max_length=500)
    auth = models.CharField(max_length=255)
    p256dh = models.CharField(max_length=255)
    activo = models.IntegerField(blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    usuario = models.ForeignKey(Usuarios, models.DO_NOTHING)

    class Meta:
        managed = False
        db_table = 'push_tokens'


class ChatVoz(models.Model):
    mensaje = models.TextField(blank=True, null=True)
    audio_ruta = models.CharField(max_length=255, blank=True, null=True)
    tipo = models.CharField(max_length=5)
    duracion_segundos = models.IntegerField(blank=True, null=True)
    escuchado = models.IntegerField(blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    adulto = models.ForeignKey(Usuarios, models.DO_NOTHING)
    cuidador = models.ForeignKey(Usuarios, models.DO_NOTHING, related_name='chatvoz_cuidador_set')
    emisor = models.ForeignKey(Usuarios, models.DO_NOTHING, related_name='chatvoz_emisor_set')

    class Meta:
        managed = False
        db_table = 'chat_voz'


class UbicacionActual(models.Model):
    usuario = models.OneToOneField(Usuarios, models.DO_NOTHING, primary_key=True)
    lat = models.DecimalField(max_digits=10, decimal_places=7)
    lng = models.DecimalField(max_digits=10, decimal_places=7)
    precision_m = models.FloatField(blank=True, null=True)
    actualizado_en = models.DateTimeField(blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'ubicacion_actual'


class Emergencia(models.Model):
    id_emergencia = models.AutoField(primary_key=True)
    lat = models.DecimalField(max_digits=10, decimal_places=7, blank=True, null=True)
    lng = models.DecimalField(max_digits=10, decimal_places=7, blank=True, null=True)
    estado = models.CharField(max_length=8, blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    atendido_en = models.DateTimeField(blank=True, null=True)
    adulto = models.ForeignKey(Usuarios, models.DO_NOTHING)
    cuidador = models.ForeignKey(Usuarios, models.DO_NOTHING, related_name='emergencia_cuidador_set', blank=True, null=True)

    class Meta:
        managed = False
        db_table = 'emergencia'


class Membresia(models.Model):
    id_membresia = models.AutoField(primary_key=True)
    fecha_pago = models.DateField()
    fecha_renovacion = models.DateField()
    estado = models.CharField(max_length=9, blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    cuidador = models.ForeignKey(Usuarios, models.DO_NOTHING)

    class Meta:
        managed = False
        db_table = 'membresia'


class Reportes(models.Model):
    id_reporte = models.AutoField(primary_key=True)
    accion = models.CharField(max_length=120)
    detalles = models.TextField(blank=True, null=True)
    creado_en = models.DateTimeField(blank=True, null=True)
    admin = models.ForeignKey(Usuarios, models.DO_NOTHING)

    class Meta:
        managed = False
        db_table = 'reportes'
