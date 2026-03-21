from django.urls import path, re_path
from django.views.generic import TemplateView
from django.conf import settings
from django.conf.urls.static import static
from . import views
from django.views.static import serve

urlpatterns = [

    path("crear-alarmas-receta/", views.crear_alarmas_receta, name="crear_alarmas_receta"),
    # --- Autenticación ---
    path("", views.login_view, name="login"),
    path("inicio/", views.inicio, name="inicio"),
    path('registro-cuidador/', views.registro_cuidador_view, name='registro_cuidador'),
    path('interfaz-cuidador/', views.interfaz_cuidador, name='interfaz_cuidador'),
    #-- Ruta para que el cuidador cree alarmas a partir de una receta escaneada --
    path("cuidador/crear-alarmas-receta/", views.crear_alarmas_receta_cuidador, name="crear_alarmas_receta_cuidador"),
    #--------- ADMIN--------- 
    path('interfaz-admin/', views.interfaz_admin, name='interfaz_admin'),
    # --- ADMIN GESTIÓN DE USUARIO --------
    path('gestion-usuarios/', views.gestion_usuarios, name='gestion_usuarios'),
    path('gestion-usuarios/<int:user_id>/estado/', views.cambiar_estado_usuario, name='cambiar_estado_usuario'),
    path('gestion-usuarios/<int:user_id>/tipo/', views.cambiar_tipo_usuario, name='cambiar_tipo_usuario'),
    path('gestion-usuarios/<int:user_id>/reset-password/', views.restablecer_password_usuario, name='restablecer_password_usuario'),
    path('gestion-usuarios/<int:user_id>/eliminar/', views.eliminar_usuario_inactivo, name='eliminar_usuario_inactivo'),
    path("monitoreo-sistema/", views.monitoreo_sistema, name="monitoreo_sistema"),
    # --------
    path('logout/', views.logout_view, name='logout'),
    path("salir/", views.salir, name="salir"),
    path("procesar-pago/", views.procesar_pago, name="procesar_pago"),
    path("cuidador/vincular/", views.vincular_adulto_por_codigo, name="vincular_adulto_por_codigo"),
    path("cuidador/cambiar-adulto/", views.cambiar_adulto_actual, name="cambiar_adulto_actual"),
    
    path("ubicacion/estado/", views.ubicacion_estado, name="ubicacion_estado"),
    path("ubicacion/toggle/", views.ubicacion_toggle, name="ubicacion_toggle"),
    path("ubicacion/ping/", views.ubicacion_ping, name="ubicacion_ping"),
    path("cuidador/ubicacion/ultima/", views.cuidador_ultima_ubicacion, name="cuidador_ultima_ubicacion"),
    path("cuidador/ubicacion/historial/", views.cuidador_historial_ubicacion, name="cuidador_historial_ubicacion"),
    
    path("chat/mensajes", views.chat_get_mensajes, name="chat_get_mensajes"),
    path("chat/enviar", views.chat_post_enviar, name="chat_post_enviar"),
    path("chat/visto", views.chat_post_marcar_visto, name="chat_post_marcar_visto"),

    #--------flutter-----------#
    path("api/v1/login/", views.api_v1_login, name="api_v1_login"),
    path("api/v1/login-nombre/", views.api_v1_login_nombre, name="api_v1_login_nombre"),
    path("api/v1/inicio/", views.api_v1_inicio, name="api_v1_inicio"),
    path("api/v1/voz/procesar/", views.api_v1_registrar_orden_openai, name="api_v1_registrar_orden_openai"),
    path("api/v1/voz/registrar-orden/", views.api_v1_registrar_orden_openai, name="api_v1_registrar_orden_openai"),
    path("api/v1/medicamentos/analizar/", views.api_v1_medicamentos_analizar, name="api_v1_medicamentos_analizar"),
    path("api/v1/alarmas/pendientes/", views.api_v1_alarmas_pendientes, name="api_v1_alarmas_pendientes"),
    path("api/v1/alarmas/", views.api_v1_alarmas, name="api_v1_alarmas"),
    path("api/v1/alarmas/marcar-entregada/", views.api_v1_marcar_entregada, name="api_v1_marcar_entregada"),
    path("api/v1/alarmas/eliminar/", views.api_v1_eliminar_alarma, name="api_v1_eliminar_alarma"),
    path("api/v1/ubicacion/estado/", views.api_v1_ubicacion_estado, name="api_v1_ubicacion_estado"),
    path("api/v1/ubicacion/toggle/", views.api_v1_ubicacion_toggle, name="api_v1_ubicacion_toggle"),
    path("api/v1/ubicacion/ping/", views.api_v1_ubicacion_ping, name="api_v1_ubicacion_ping"),
    path("api/v1/me/", views.api_v1_me, name="api_v1_me"),
    path("api/v1/logout/", views.api_v1_logout, name="api_v1_logout"),
    path("api/v1/register/adulto/", views.api_v1_register_adulto, name="api_v1_register_adulto"),
    path("api/v1/register/cuidador/", views.api_v1_register_cuidador, name="api_v1_register_cuidador"),
    path('api/v1/interfaz-cuidador/', views.api_v1_interfaz_cuidador, name='api_v1_interfaz_cuidador'),
    path("api/v1/cuidador/alarmas/", views.api_v1_cuidador_alarmas, name="api_v1_cuidador_alarmas"),
    path("api/v1/cuidador/alarmas/crear/", views.api_v1_cuidador_alarmas_crear, name="api_v1_cuidador_alarmas_crear"),
    path("api/v1/cuidador/alarmas/editar/", views.api_v1_cuidador_alarmas_editar, name="api_v1_cuidador_alarmas_editar"),
    path("api/v1/cuidador/alarmas/eliminar/", views.api_v1_cuidador_alarmas_eliminar, name="api_v1_cuidador_alarmas_eliminar"),
    path("api/v1/cuidador/receta/crear-alarmas/", views.api_v1_cuidador_crear_alarmas_receta, name="api_v1_cuidador_crear_alarmas_receta"),
    path("api/v1/cuidador/ubicacion/ultima/", views.api_v1_cuidador_ubicacion_ultima, name="api_v1_cuidador_ubicacion_ultima"),
    path("api/v1/cuidador/ubicacion/historial/", views.api_v1_cuidador_ubicacion_historial, name="api_v1_cuidador_ubicacion_historial"),
    path("api/v1/chat/mensajes/", views.api_v1_chat_mensajes, name="api_v1_chat_mensajes"),
    path("api/v1/chat/enviar/", views.api_v1_chat_enviar, name="api_v1_chat_enviar"),
    path("api/v1/chat/marcar-visto/", views.api_v1_chat_marcar_visto, name="api_v1_chat_marcar_visto"),
    path('vincular-adulto-por-codigo/', views.vincular_adulto_por_codigo, name='vincular_adulto_por_codigo'),
    path("api/v1/emergencia/crear/", views.api_v1_emergencia_crear, name="api_v1_emergencia_crear"),
    path("api/v1/emergencia/pendientes/", views.api_v1_emergencia_pendientes, name="api_v1_emergencia_pendientes"),
    path("api/v1/emergencia/actualizar/", views.api_v1_emergencia_actualizar, name="api_v1_emergencia_actualizar"),

    # --- Órdenes de voz / OpenAI ---
    path("registrar-openai/", views.registrar_orden_openai, name="registrar_orden_openai"),
    path("procesar_comando_aprendizaje/", views.procesar_comando_aprendizaje, name="procesar_comando_aprendizaje"),

    # --- Alarmas ---
    path("crear-alarma/", views.crear_alarma, name="crear_alarma"),
    path("alarmas/pendientes/", views.pendientes, name="alarmas_pendientes"),
    path("alarmas/marcar-entregada/", views.marcar_entregada, name="marcar_entregada"),
    path("alarmas/reprogramar/", views.reprogramar_alarma, name="reprogramar_alarma"),
    path("api/alarmas/", views.obtener_alarmas, name="obtener_alarmas"),
    path("api/cuidador/alarmas/", views.obtener_alarmas_cuidador, name="obtener_alarmas_cuidador"),
    path("api/cuidador/alarmas/crear/", views.crear_alarma_cuidador, name="crear_alarma_cuidador"),
    path("api/cuidador/alarmas/editar/", views.editar_alarma_cuidador, name="editar_alarma_cuidador"),
    path("api/cuidador/alarmas/eliminar/", views.eliminar_alarma_cuidador, name="eliminar_alarma_cuidador"),
    path("api/alarmas/eliminar/", views.eliminar_alarma_ajax, name="eliminar_alarma_ajax"),
    path("api/alarmas/eliminar-todas/", views.eliminar_todas_alarmas_ajax, name="eliminar_todas_alarmas_ajax"),
    path("api/emergencia/crear/", views.crear_emergencia, name="crear_emergencia"),
    path("api/cuidador/emergencias/pendientes/", views.cuidador_emergencias_pendientes, name="cuidador_emergencias_pendientes"),
    path("api/cuidador/emergencias/estado/", views.actualizar_estado_emergencia, name="actualizar_estado_emergencia"),

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
