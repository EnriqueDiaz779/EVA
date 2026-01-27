from django.contrib import admin
from .models import Alarma, CapturaTemporal, MedicamentoReconocido

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
