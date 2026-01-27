from django.urls import path, re_path
from django.views.generic import TemplateView
from django.conf import settings
from django.conf.urls.static import static
from . import views
from django.views.static import serve

urlpatterns = [
    # --- Autenticación ---
    path("", views.login_view, name="login"),
    path("inicio/", views.inicio, name="inicio"),
    path("salir/", views.salir, name="salir"),

    # --- Órdenes de voz / OpenAI ---
    path("registrar-openai/", views.registrar_orden_openai, name="registrar_orden_openai"),
    path("procesar_comando_aprendizaje/", views.procesar_comando_aprendizaje, name="procesar_comando_aprendizaje"),

    # --- Alarmas ---
    path("crear-alarma/", views.crear_alarma, name="crear_alarma"),
    path("alarmas/pendientes/", views.pendientes, name="alarmas_pendientes"),
    path("alarmas/marcar-entregada/", views.marcar_entregada, name="marcar_entregada"),
    path("alarmas/reprogramar/", views.reprogramar_alarma, name="reprogramar_alarma"),
    path("api/alarmas/", views.obtener_alarmas, name="obtener_alarmas"),
    path("api/alarmas/eliminar/", views.eliminar_alarma_ajax, name="eliminar_alarma_ajax"),

    # --- Cámara / Escáner ---
    path("upload-temporal/", views.upload_temporal, name="upload_temporal"),

    # --- Service Worker / Notificaciones locales ---
    path("api/notify/", views.notificar_serviceworker, name="notificar_serviceworker"),

    # --- Web Push real ---
    path("save_subscription/", views.save_subscription, name="save_subscription"),
    path("send_push_notification/", views.send_push_notification, name="send_push_notification"),

    # --- Archivos PWA ---
    path("manifest.json", TemplateView.as_view(
        template_name="miapp/manifest.json",
        content_type="application/json"
    )),
    re_path(
        r"^service-worker\.js$",
        TemplateView.as_view(template_name="miapp/service-worker.js", content_type="application/javascript"),
        name="service_worker"
    ),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
