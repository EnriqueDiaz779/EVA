from django.contrib import admin
from .models import (
    Alarma,
    CapturaTemporal,
    MedicamentoReconocido,
    OrdenVoz,
    PatronVoz,
    PerfilUsuario,
    PushSubscription,
)


@admin.register(PerfilUsuario)
class PerfilUsuarioAdmin(admin.ModelAdmin):
    list_display = ("id", "usuario", "tipo_cuenta")
    list_filter = ("tipo_cuenta",)
    search_fields = ("usuario__username",)


@admin.register(OrdenVoz)
class OrdenVozAdmin(admin.ModelAdmin):
    list_display = ("id", "usuario", "intent", "creado")
    list_filter = ("intent", "creado")
    search_fields = ("usuario__username", "texto", "respuesta")


@admin.register(PatronVoz)
class PatronVozAdmin(admin.ModelAdmin):
    list_display = ("id", "usuario", "comando_original", "similitud", "aciertos", "errores", "fecha_ultimo_uso")
    list_filter = ("fecha_ultimo_uso",)
    search_fields = ("usuario__username", "comando_original", "texto_reconocido")

@admin.register(Alarma)
class AlarmaAdmin(admin.ModelAdmin):
    list_display = ("id", "fecha", "hora", "mensaje", "activa", "disparada_at", "entregada", "creada")
    list_filter = ("activa", "entregada", "fecha")
    search_fields = ("mensaje",)

@admin.register(CapturaTemporal)
class CapturaTemporalAdmin(admin.ModelAdmin):
    list_display = ("id", "usuario", "estado", "creado")
    list_filter = ("estado", "creado")
    search_fields = ("usuario__username",)

@admin.register(MedicamentoReconocido)
class MedicamentoReconocidoAdmin(admin.ModelAdmin):
    list_display = ("id", "usuario", "nombre_detectado", "confianza", "creado")
    search_fields = ("usuario__username", "nombre_detectado")
    list_filter = ("creado",)


@admin.register(PushSubscription)
class PushSubscriptionAdmin(admin.ModelAdmin):
    list_display = ("id", "usuario", "endpoint", "creado")
    list_filter = ("creado",)
    search_fields = ("usuario__username", "endpoint")
