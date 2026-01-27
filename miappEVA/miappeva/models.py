from django.db import models 
from django.contrib.auth.models import User
from django.conf import settings

class OrdenVoz(models.Model):
    usuario = models.ForeignKey(User, on_delete=models.CASCADE)
    texto = models.TextField()
    respuesta = models.TextField(blank=True, null=True)  # 🔹 respuesta generada por la IA
    intent = models.CharField(max_length=100, default="desconocido")  # 🔹 tipo de intención detectada
    meta = models.JSONField(default=dict, blank=True)  # 🔹 datos extra (confidence, entities, etc.)
    creado = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.usuario.username} - {self.texto[:30]}"


class Alarma(models.Model):
    usuario = models.ForeignKey(User, on_delete=models.CASCADE)  # 🔹 quién creó la alarma
    fecha = models.DateField(null=True, blank=True)              # 🔹 opcional (si es para un día específico)
    hora = models.TimeField()                                   # 🔹 hora de la alarma
    mensaje = models.CharField(max_length=120, default="¡Es hora de tu medicamento!")
    dias = models.CharField(max_length=120, blank=True, default="")  # 🔹 nuevo campo para "Lun, Mar, Vie"
    activa = models.BooleanField(default=True)                  # 🔹 indica si sigue activa
    disparada_at = models.DateTimeField(null=True, blank=True)  # 🔹 cuándo se activó por última vez
    entregada = models.BooleanField(default=False)              # 🔹 si ya se notificó
    creada = models.DateTimeField(auto_now_add=True)            # 🔹 cuándo se creó

    def __str__(self):
        f = self.fecha.isoformat() if self.fecha else "hoy"
        d = f" ({self.dias})" if self.dias else ""
        return f"[{f} {self.hora}]{d} {self.mensaje}"


# 🧠 NUEVO MODELO: aprendizaje de pronunciación personalizada
class PatronVoz(models.Model):
    usuario = models.ForeignKey(User, on_delete=models.CASCADE)
    comando_original = models.CharField(max_length=100)          # el comando base correcto
    texto_reconocido = models.CharField(max_length=100)          # cómo lo pronunció el usuario
    similitud = models.FloatField(default=0.0)                   # porcentaje de similitud (0.0 a 1.0)
    aciertos = models.IntegerField(default=0)                    # veces que se reconoció correctamente
    errores = models.IntegerField(default=0)                     # veces que se confundió
    fecha_ultimo_uso = models.DateTimeField(auto_now=True)       # para saber cuándo se usó por última vez

    def __str__(self):
        return f"{self.usuario.username} → {self.comando_original} ({self.similitud*100:.1f}%)"


def captura_upload_to(instance, filename):
    # opcional: prefijo por usuario y fecha
    import uuid, datetime, os
    ext = os.path.splitext(filename)[1].lower() or ".jpg"
    today = datetime.date.today().isoformat()
    return f"capturas/{instance.usuario_id}/{today}/{uuid.uuid4().hex}{ext}"

class CapturaTemporal(models.Model):
    usuario = models.ForeignKey(User, on_delete=models.CASCADE)
    imagen = models.ImageField(upload_to=captura_upload_to)
    creado = models.DateTimeField(auto_now_add=True)
    estado = models.CharField(max_length=20, default="pendiente")  # pendiente | analizado | descartado

    def __str__(self):
        return f"{self.usuario.username} - {self.creado:%Y-%m-%d %H:%M}" 
    
class MedicamentoReconocido(models.Model):
    usuario = models.ForeignKey(User, on_delete=models.CASCADE)
    captura = models.ForeignKey('CapturaTemporal', on_delete=models.CASCADE, related_name='resultados')
    nombre_detectado = models.CharField(max_length=120)
    descripcion = models.TextField(blank=True)
    confianza = models.FloatField(default=0.0)
    creado = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.usuario.username} - {self.nombre_detectado} ({self.confianza:.2f})"
    
class PushSubscription(models.Model):
    usuario = models.ForeignKey(User, on_delete=models.CASCADE, related_name="push_subs")
    endpoint = models.TextField(unique=True)
    p256dh = models.CharField(max_length=255)
    auth = models.CharField(max_length=255)
    creado = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"PushSub de {self.usuario.username}"