from django.shortcuts import render, redirect
from django.contrib.auth import authenticate, login as auth_login, logout as auth_logout
from django.contrib.auth.decorators import login_required
from django.contrib.auth.models import User
from django.contrib import messages
from django.http import JsonResponse
from django.views.decorators.http import require_POST
from django.utils import timezone
from django.db import connection
from django.contrib.auth.hashers import make_password
from .models import OrdenVoz, Alarma, PatronVoz, CapturaTemporal
from .openai_client import preguntar_openai
from datetime import date
import logging
from difflib import SequenceMatcher
from .models import PatronVoz
from django.core.files.uploadedfile import InMemoryUploadedFile
from django.core.files.base import ContentFile
from PIL import Image
import io
import base64, json, os
from django.conf import settings
from openai import OpenAI
from django.views.decorators.csrf import csrf_exempt
from datetime import timedelta
from .models import CapturaTemporal, MedicamentoReconocido
from datetime import datetime, timedelta, time
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from .models import PushSubscription

try:
    from pywebpush import webpush, WebPushException
except Exception as e:
    print("⚠️ WebPush desactivado (cryptography/DLL):", e)
    webpush = None
    WebPushException = Exception

client = OpenAI(api_key=settings.OPENAI_API_KEY)

logger = logging.getLogger(__name__)

#---login----#
def login_view(request):
    if request.user.is_authenticated:
        return redirect('inicio')

    if request.method != "POST":
        return render(request, 'miapp/login.html')

    nombre_original = (request.POST.get('username') or '').strip()
    password = request.POST.get('password') or ''

    if not nombre_original or not password:
        messages.error(request, "Escribe tu nombre y tu contraseña.")
        return render(request, 'miapp/login.html', {"previous_username": nombre_original})

    username = nombre_original.lower()
    
    # PRIMERO: Verificar si existe en MySQL
    usuario_mysql = verificar_usuario_en_bd(nombre_original)
    print(f"🔍 Búsqueda en MySQL para: {nombre_original}")
    
    # CASO 1: Usuario existe en MySQL
    if usuario_mysql:
        print(f"✅ Usuario encontrado en MySQL con tipo: {usuario_mysql['tipo']}")
        # Intentar crear o actualizar en Django si no existe
        user = User.objects.filter(username=username).first()
        
        if user is None:
            print(f"⚠️ Usuario existe en MySQL pero no en Django, creando en Django...")
            # Crear en Django con los datos de MySQL
            user = User.objects.create_user(
                username=username, 
                password=password, 
                first_name=usuario_mysql['nombre']
            )
        
        # Verificar contraseña
        user_auth = authenticate(request, username=username, password=password)
        if user_auth is None:
            print(f"❌ Contraseña incorrecta para: {nombre_original}")
            messages.error(request, "Contraseña incorrecta.")
            return render(request, 'miapp/login.html', {"previous_username": nombre_original})
        
        # Login exitoso
        auth_login(request, user_auth)
        registrar_login_en_db(username, request)
        messages.success(request, "Bienvenido de nuevo.")
        
        # Redirigir según tipo en MySQL
        if usuario_mysql['tipo'] == "cuidador":
            print(f"🎯 Redirigiendo cuidador a interfaz_cuidador")
            return redirect('interfaz_cuidador')
        else:
            print(f"🎯 Redirigiendo adulto a inicio")
            return redirect('inicio')
    
    # CASO 2: Usuario NO existe en MySQL
    print(f"❌ Usuario NOT encontrado en MySQL: {nombre_original}")
    
    user = User.objects.filter(username=username).first()
    
    if user is None:
        print(f"👤 Usuario NUEVO: creando como adulto")
        # Crear usuario en Django
        user = User.objects.create_user(username=username, password=password, first_name=nombre_original)
        # Guardar como "adulto" en MySQL
        adulto_id = registrar_usuario_en_db(nombre_original, password, "adulto")
        if adulto_id is None:
            user.delete()
            messages.error(request, "Error al registrar el usuario en la base de datos.")
            return render(request, 'miapp/login.html', {"previous_username": nombre_original})
        auth_login(request, user)
        messages.success(request, "Bienvenido, hemos creado tu acceso como adulto.")
        return redirect('inicio')
    
    # Usuario existe en Django pero no en MySQL (inconsistencia)
    print(f"⚠️ Usuario en Django pero no en MySQL: {nombre_original}")
    user_auth = authenticate(request, username=username, password=password)
    if user_auth is None:
        messages.error(request, "Contraseña incorrecta.")
        return render(request, 'miapp/login.html', {"previous_username": nombre_original})
    
    auth_login(request, user_auth)
    registrar_login_en_db(username, request)
    messages.success(request, "Bienvenido de nuevo.")
    return redirect('inicio')

#----usuarios en bd------#
def registrar_usuario_en_db(nombre_completo, password, tipo="adulto"):
    """Registra un nuevo usuario en la tabla Usuarios"""
    try:
        password_hash = make_password(password)
        with connection.cursor() as cursor:
            cursor.execute(
                "INSERT INTO Usuarios (Nombre_Completo, password_hash, Tipo, activo) VALUES (%s, %s, %s, %s)",
                [nombre_completo, password_hash, tipo, True]
            )
            # Obtener el ID del usuario insertado
            cursor.execute("SELECT LAST_INSERT_ID()")
            usuario_id = cursor.fetchone()[0]
        # Hacer commit a la base de datos
        connection.commit()
        print(f"✅ Usuario '{nombre_completo}' registrado en tabla Usuarios con tipo '{tipo}' (ID: {usuario_id})")
        return usuario_id
    except Exception as e:
        connection.rollback()
        print(f"❌ Error al registrar usuario en DB: {e}")
        return None

#----obtener tipo de usuario----#
def obtener_tipo_usuario(nombre_completo):
    """Obtiene el tipo de usuario (adulto o cuidador) de la BD"""
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT Tipo FROM Usuarios WHERE Nombre_Completo = %s LIMIT 1",
                [nombre_completo]
            )
            row = cursor.fetchone()
            if row:
                tipo = row[0]
                print(f"✅ Tipo de usuario '{nombre_completo}' obtenido: {tipo}")
                return tipo
            else:
                print(f"⚠️ Usuario '{nombre_completo}' no encontrado en BD")
    except Exception as e:
        print(f"❌ Error al obtener tipo de usuario: {e}")
    return None

#----debug: verificar usuario en BD----#
def verificar_usuario_en_bd(nombre_completo):
    """Verifica si un usuario existe en la BD y retorna su información"""
    try:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono FROM Usuarios WHERE Nombre_Completo = %s LIMIT 1",
                [nombre_completo]
            )
            row = cursor.fetchone()
            if row:
                print(f"✅ Usuario encontrado en BD: {row}")
                return {
                    "id": row[0],
                    "nombre": row[1],
                    "tipo": row[2],
                    "correo": row[3],
                    "telefono": row[4]
                }
            else:
                print(f"⚠️ Usuario '{nombre_completo}' NO encontrado en BD MySQL")
    except Exception as e:
        print(f"❌ Error verificando usuario: {e}")
    return None
    return None
    return None

#----login en bd------#
def registrar_login_en_db(username, request):
    """Registra el login en una tabla de auditoría"""
    try:
        with connection.cursor() as cursor:
            # Primero obtener el ID del usuario por Nombre_Completo (no username)
            cursor.execute("SELECT Id_Usuario FROM Usuarios WHERE Nombre_Completo = %s LIMIT 1", [username])
            result = cursor.fetchone()
            if result:
                usuario_id = result[0]
                ip_address = get_client_ip(request)
                user_agent = request.META.get('HTTP_USER_AGENT', '')[:500]
                
                cursor.execute(
                    "INSERT INTO registros_login (usuario_id, ip_address, fecha_entrada, user_agent, activo) VALUES (%s, %s, NOW(), %s, %s)",
                    [usuario_id, ip_address, user_agent, True]
                )
                print(f"✅ Login registrado para usuario ID: {usuario_id}")
            else:
                print(f"⚠️ Usuario no encontrado en tabla Usuarios")
    except Exception as e:
        print(f"❌ Error al registrar login en DB: {e}")

#-----ip client-----#
def get_client_ip(request):
    """Obtiene la IP del cliente"""
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        ip = x_forwarded_for.split(',')[0]
    else:
        ip = request.META.get('REMOTE_ADDR')
    return ip

#-----inicio----#
@login_required
def inicio(request):
    nombre = request.user.first_name or request.user.username
    ultimas = OrdenVoz.objects.filter(usuario=request.user)[:5]
    return render(request, 'miapp/inicio.html', {"nombre": nombre, "ultimas": ultimas})

#-----interfaz_cuidador----#
@login_required
def interfaz_cuidador(request):
    nombre = request.user.first_name or request.user.username
    return render(request, 'miapp/Interfaz_cuidador.html', {"nombre": nombre})

#------salida----#
@login_required
def salir(request):
    auth_logout(request)
    messages.info(request, "Sesión cerrada. Puedes volver a entrar cuando quieras.")
    return redirect("login")

#----registro_cuidador en bd------#
def registro_cuidador_view(request):
    # GET -> muestra el formulario
    if request.method != "POST":
        return render(request, "miapp/registro_cuidador.html")

    # POST -> toma datos del FORM (no JSON)
    nombre_completo = (request.POST.get("nombre_completo") or "").strip()
    password = request.POST.get("password") or ""
    correo = (request.POST.get("correo") or "").strip().lower()
    telefono = (request.POST.get("telefono") or "").strip()
    pago_completado = request.POST.get("pago_completado") == "true"

    if not nombre_completo or not password or not correo:
        messages.error(request, "Faltan campos: nombre completo, correo y contraseña.")
        return render(request, "miapp/registro_cuidador.html")

    # Validar que el pago fue completado
    if not pago_completado:
        messages.error(request, "Debes completar el pago para registrarte.")
        return render(request, "miapp/registro_cuidador.html")

    # Validar en ambas bases de datos
    if _mysql_get_usuario_por_correo(correo):
        messages.error(request, "Ese correo ya está registrado.")
        return render(request, "miapp/registro_cuidador.html")

    django_user = User.objects.filter(username=correo).first()
    if django_user:
        # Si existe en Django pero no en MySQL, eliminarlo y continuar
        django_user.delete()

    # Crear en Django
    user = User.objects.create_user(username=correo, password=password, first_name=nombre_completo)

    # Insertar en MySQL y obtener el ID
    try:
        cuidador_id = _mysql_insert_usuario(nombre_completo, password, "cuidador", correo=correo, telefono=telefono)
    except Exception as e:
        user.delete()
        messages.error(request, f"No se pudo registrar en MySQL: {e}")
        return render(request, "miapp/registro_cuidador.html")

    # Guardar la membresía
    try:
        guardar_membresia(cuidador_id)
    except Exception as e:
        print(f"⚠️ Advertencia al guardar membresía: {e}")

    # Iniciar sesión y mandar a interfaz_cuidador
    auth_login(request, user)
    messages.success(request, "Cuidador registrado correctamente.")
    return redirect("interfaz_cuidador")

#---- OPENAI – Órdenes de voz -----#
@login_required
@require_POST
def registrar_orden_openai(request):
    texto = (request.POST.get("texto") or "").strip().lower()
    asr_conf = request.POST.get("asr_conf")

    try:
        asr_conf = float(asr_conf) if asr_conf is not None else None
    except ValueError:
        asr_conf = None

    # CASO 1: No se detectó voz
    if not texto:
        orden = OrdenVoz.objects.create(
            usuario=request.user,
            texto="(vacío)",
            respuesta="No pude escuchar nada. ¿Podrías repetir cerca del micrófono?",
            intent="no_entendido",
            meta={"reason": "asr_empty", "asr_conf": asr_conf, "provider": "openai"},
        )
        return JsonResponse({
            "ok": True,
            "id": orden.id,
            "fecha": timezone.localtime(orden.creado).strftime("%d/%m %H:%M"),
            "texto": "",
            "respuesta": orden.respuesta,
            "intent": orden.intent,
            "confidence": 0.0,
            "no_entendido": True,
            "meta": {},
            "alarm_created": False,
        })

    # CASO 2: Órdenes de cancelación
    palabras_cancelacion = ["cancelar", "anular", "me equivoqué", "olvida eso", "no eso", "borra eso"]
    if any(p in texto for p in palabras_cancelacion):
        respuesta_cancelacion = "Está bien, he cancelado la orden. Puedes decirme otra cosa cuando quieras."
        orden = OrdenVoz.objects.create(
            usuario=request.user,
            texto=texto,
            respuesta=respuesta_cancelacion,
            intent="cancelacion",
            meta={"reason": "user_cancelled", "asr_conf": asr_conf, "provider": "openai"},
        )
        return JsonResponse({
            "ok": True,
            "id": orden.id,
            "fecha": timezone.localtime(orden.creado).strftime("%d/%m %H:%M"),
            "texto": texto,
            "respuesta": respuesta_cancelacion,
            "intent": "cancelacion",
            "confidence": 1.0,
            "cancelado": True,
            "meta": {},
            "alarm_created": False,
        })
    
    #Filtro EVA Inteligente
    palabras_clave_medicamentos = [
        "medicamento", "pastilla", "tableta", "jarabe", "inyección", "cápsula",
        "medicina", "tratamiento", "dosis", "efecto", "efectos secundarios",
        "contraindicaciones", "cómo se toma", "sirve para", "farmacia"
    ]

    nombres_medicamentos = [
        "paracetamol", "ibuprofeno", "omeprazol", "amoxicilina", "loratadina",
        "diclofenaco", "ambroxol", "naproxeno", "azitromicina", "metformina",
        "losartán", "salbutamol", "prednisona", "vitamina", "antibiótico"
    ]

    palabras_alarmas = [
        "alarma", "recordar", "recordatorio", "avísame", "notificación",
        "despertar", "pon una alarma", "a las", "programa una alarma", "crear alarma"
    ]

    # Verificamos si el texto contiene una palabra de alarma
    es_alarma = any(p in texto for p in palabras_alarmas)

    # Verificamos si menciona un medicamento específico
    contiene_medicamento_nombre = any(m in texto for m in nombres_medicamentos)

    # Verificamos si habla de medicamentos (palabra clave + posible nombre de medicamento)
    es_medicamento = contiene_medicamento_nombre or (
        any(p in texto for p in palabras_clave_medicamentos) and
        any(m in texto for m in nombres_medicamentos)
    )

    # Si NO es medicamento ni alarma → bloquear
    if not (es_medicamento or es_alarma):
        respuesta_fuera = (
            "Solo puedo ayudarte con medicamentos o alarmas. "
            "Por ejemplo: ¿Para qué sirve el ambroxol? o Pon una alarma a las ocho de la mañana."
        )
        orden = OrdenVoz.objects.create(
            usuario=request.user,
            texto=texto,
            respuesta=respuesta_fuera,
            intent="fuera_de_tema",
            meta={"reason": "out_of_scope", "asr_conf": asr_conf, "provider": "openai"},
        )
        return JsonResponse({
            "ok": True,
            "id": orden.id,
            "fecha": timezone.localtime(orden.creado).strftime("%d/%m %H:%M"),
            "texto": texto,
            "respuesta": respuesta_fuera,
            "intent": "fuera_de_tema",
            "confidence": 1.0,
            "no_entendido": True,
            "meta": {},
            "alarm_created": False,
        })

    # CASO 3: Consultar a OpenAI
    result = preguntar_openai(texto)
    respuesta_ia = (result.get("respuesta") or "").strip()
    intent = result.get("intent", "desconocido")
    ia_conf = float(result.get("confidence", 0.0))
    meta = result.get("meta") or {}

    # CASO 4: OpenAI vacío
    if not respuesta_ia:
        orden = OrdenVoz.objects.create(
            usuario=request.user,
            texto=texto,
            respuesta="No entendí lo que dijiste, ¿puedes repetirlo con otras palabras?",
            intent="no_entendido",
            meta={"reason": "empty_ai_response", "asr_conf": asr_conf, "provider": "openai"},
        )
        return JsonResponse({
            "ok": True,
            "id": orden.id,
            "fecha": timezone.localtime(orden.creado).strftime("%d/%m %H:%M"),
            "texto": texto,
            "respuesta": orden.respuesta,
            "intent": orden.intent,
            "confidence": 0.0,
            "no_entendido": True,
            "meta": {},
            "alarm_created": False,
        })

    # CASO 5: Entendido correctamente
    orden = OrdenVoz.objects.create(
        usuario=request.user,
        texto=texto,
        respuesta=respuesta_ia,
        intent=intent,
        meta={"ia_conf": ia_conf, "asr_conf": asr_conf, "provider": "openai", "meta": meta},
    )

    # Si la intención es "alarma", crea la alarma en BD aquí mismo
    alarm_created = False
    if intent == "alarma":
        hora = (meta.get("hora") or "").strip()
        mensaje = (meta.get("mensaje") or "¡Alarma programada correctamente!").strip()
        if hora:
            try:
                Alarma.objects.create(
                    fecha=None,   # se asume hoy; si luego quieres fecha, la añadimos desde meta
                    hora=hora,
                    mensaje=mensaje,
                    activa=True
                )
                alarm_created = True
                logger.info(f"🟢 Alarma creada via IA: {hora} - {mensaje}")
            except Exception as e:
                logger.exception(f"Error creando alarma: {e}")

    return JsonResponse({
        "ok": True,
        "id": orden.id,
        "fecha": timezone.localtime(orden.creado).strftime("%d/%m %H:%M"),
        "texto": orden.texto,
        "respuesta": orden.respuesta,
        "intent": intent,
        "confidence": ia_conf,
        "no_entendido": False,
        "meta": meta,
        "alarm_created": alarm_created,
    })

#------pendientes------#
@login_required
def pendientes(request):
    """
    Detecta alarmas que deben sonar ahora (+/-30 s),
    marca su disparo y envía notificación Web Push si hay suscripciones.
    """
    ahora = timezone.localtime()
    margen = timedelta(seconds=30)

    inicio = (ahora - margen).time()
    fin = (ahora + margen).time()

    alarmas = (
        Alarma.objects
        .filter(activa=True, entregada=False, hora__gte=inicio, hora__lte=fin)
        .order_by("hora")
    )

    data = []
    for a in alarmas:
        # evita disparos duplicados recientes
        if a.disparada_at and (ahora - a.disparada_at).total_seconds() < 90:
            continue

        a.disparada_at = timezone.now()
        a.save(update_fields=["disparada_at"])

        data.append({
            "id": a.id,
            "mensaje": a.mensaje,
            "hora": a.hora.strftime("%H:%M"),
        })

        # Si WebPush está desactivado, NO intentar enviar push
        if webpush is None:
            continue

        # === 📤 Notificación Web Push ===
        payload = {
            "title": "⏰ EVA",
            "body": a.mensaje,
            "tag": f"alarma-{a.id}",
            "url": "/inicio/",
            "id": a.id,
        }

        vapid_private = getattr(settings, "VAPID_PRIVATE_KEY", None)
        vapid_claims = {"sub": "mailto:tuequipo@eva.com"}

        # Enviar a todas las suscripciones registradas
        for sub in PushSubscription.objects.all():
            try:
                webpush(
                    subscription_info={
                        "endpoint": sub.endpoint,
                        "keys": {"p256dh": sub.p256dh, "auth": sub.auth},
                    },
                    data=json.dumps(payload),
                    vapid_private_key=vapid_private,
                    vapid_claims=vapid_claims,
                )
                print(f"📨 Push enviado a {sub.usuario.username if sub.usuario else 'desconocido'}")
            except WebPushException as e:
                print(f"⚠️ Error push: {e}")
                sub.delete()  # limpia suscripciones caducadas

    return JsonResponse({"ok": True, "alarmas": data})

#--------Marcar entregada (alarmas)----#
@login_required
@require_POST
@csrf_exempt
def marcar_entregada(request):
    _id = request.POST.get("id")
    try:
        a = Alarma.objects.get(id=_id)

        # 🟢 Si la alarma NO tiene días definidos (una sola vez)
        if not a.dias:
            a.entregada = True
            a.activa = False
            logger.info(f"✅ Alarma única desactivada: #{a.id}")
        else:
            # 🟡 Si la alarma es recurrente (tiene días)
            # Solo marcamos que ya sonó, pero la mantenemos activa
            a.disparada_at = timezone.now()
            logger.info(f"🔁 Alarma recurrente sonó pero sigue activa: #{a.id}")

        a.save()
        return JsonResponse({"ok": True})

    except Alarma.DoesNotExist:
        return JsonResponse({"ok": False, "error": "No existe"}, status=404)

#-------reprogramar alarma------#
@login_required
@require_POST
@csrf_exempt
def reprogramar_alarma(request):
    """
    Reprograma una alarma omitida a +5 minutos y la reactiva correctamente.
    """
    _id = request.POST.get("id")
    try:
        a = Alarma.objects.get(id=_id)
        ahora = timezone.localtime()

        base_dt = datetime.combine(ahora.date(), a.hora)
        nueva_dt = base_dt + timedelta(minutes=5)

        # 🟢 Actualiza todos los campos para permitir nuevo disparo
        a.hora = nueva_dt.time()
        a.entregada = False
        a.disparada_at = None
        a.activa = True
        a.save(update_fields=["hora", "entregada", "disparada_at", "activa"])

        print(f"🔁 Alarma #{a.id} reprogramada para {a.hora.strftime('%H:%M')}")

        # 🔔 Notifica al navegador para mostrar aviso inmediato de “Reprogramada”
        return JsonResponse({
            "ok": True,
            "nueva_hora": a.hora.strftime("%H:%M"),
            "mensaje": a.mensaje
        })
    except Exception as e:
        print("❌ Error al reprogramar alarma:", e)
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

#-----comandos de aprendizaje-----#
@login_required
@require_POST
def procesar_comando_aprendizaje(request):
    """
    Recibe el texto reconocido por voz, lo compara con comandos conocidos
    y guarda el patrón de pronunciación del usuario.
    """
    usuario = request.user
    texto_reconocido = (request.POST.get("texto") or "").strip().lower()

    if not texto_reconocido:
        return JsonResponse({"ok": False, "mensaje": "No se recibió texto."}, status=400)

    # Lista base de comandos conocidos por EVA
    comandos_base = [
        "activar alarma",
        "detener alarma",
        "recordar medicamento",
        "buscar medicamento",
        "cancelar alarma"
    ]

    def similitud_texto(a, b):
        return SequenceMatcher(None, a.lower(), b.lower()).ratio()

    mejor_coincidencia = None
    mayor_similitud = 0.0

    # Compara el texto reconocido con cada comando base
    for comando in comandos_base:
        porcentaje = similitud_texto(texto_reconocido, comando)
        if porcentaje > mayor_similitud:
            mayor_similitud = porcentaje
            mejor_coincidencia = comando

    # Guarda el patrón de pronunciación
    PatronVoz.objects.create(
        usuario=usuario,
        comando_original=mejor_coincidencia,
        texto_reconocido=texto_reconocido,
        similitud=mayor_similitud
    )

    # Genera la respuesta adaptativa
    if mayor_similitud >= 0.7:
        mensaje = f"Entendí que quisiste decir: '{mejor_coincidencia}'."
    else:
        mensaje = f"No estoy seguro, ¿quisiste decir '{mejor_coincidencia}'?"

    return JsonResponse({
        "ok": True,
        "mensaje": mensaje,
        "comando": mejor_coincidencia,
        "similitud": round(mayor_similitud * 100, 1)
    })

#-----------imagen temporal-------------#
@login_required
@require_POST
def upload_temporal(request):
    """
    Recibe un archivo 'foto' (image/*), valida, opcionalmente comprime,
    guarda CapturaTemporal y analiza con OpenAI.
    Devuelve JSON con nombre/para_que_sirve/confianza.
    """
    try:
        f = request.FILES.get("foto")
        if not f:
            return JsonResponse({"ok": False, "error": "No llegó la imagen."}, status=400)

        # ✅ Validar mime simple (de la versión 1)
        content_type = (getattr(f, "content_type", "") or "").lower()
        if not content_type.startswith("image/"):
            return JsonResponse({"ok": False, "error": "Formato no válido."}, status=400)

        # ✅ (Opcional) Comprimir/redimensionar ANTES de guardar (de la versión 1)
        # Esto reduce peso y acelera el análisis.
        try:
            img = Image.open(f).convert("RGB")
            max_side = 1280
            w, h = img.size
            scale = min(max_side / float(max(w, h)), 1.0)
            if scale < 1.0:
                img = img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)

            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=85, optimize=True)
            buf.seek(0)

            archivo = InMemoryUploadedFile(
                buf, field_name="foto", name="captura.jpg",
                content_type="image/jpeg", size=buf.getbuffer().nbytes, charset=None
            )
        except Exception:
            # Si falla compresión, usamos el original sin romper el flujo
            archivo = f

        # Guardar temporal
        cap = CapturaTemporal.objects.create(
            usuario=request.user,
            imagen=archivo,
            estado="pendiente"
        )

        # Analizar con IA
        img_path = cap.imagen.path
        nombre, para_que_sirve, confianza, debug_text = analizar_imagen_openai(img_path)

        cap.estado = "analizado"
        cap.save(update_fields=["estado"])

        if nombre:
            MedicamentoReconocido.objects.create(
                usuario=request.user,
                captura=cap,
                nombre_detectado=nombre,
                descripcion=para_que_sirve,
                confianza=confianza
            )
            return JsonResponse({
                "ok": True,
                "cap_id": cap.id,
                "nombre": nombre,
                "para_que_sirve": para_que_sirve,
                "confianza": round(confianza, 3)
            })

        return JsonResponse({
            "ok": False,
            "cap_id": cap.id,
            "error": "No pude identificar el medicamento en la foto.",
            "debug": debug_text
        }, status=200)

    except Exception as e:
        return JsonResponse({"ok": False, "error": f"Error guardando/analizando: {e}"}, status=500)

#-----Extraer json-----#
def _extraer_json_seguro(texto):
    """
    Intenta extraer JSON aunque venga rodeado de texto/markdown.
    """
    try:
        return json.loads(texto)
    except Exception:
        pass
    # recorte simple entre la primera y última llave
    try:
        start = texto.find("{")
        end = texto.rfind("}")
        if start != -1 and end != -1:
            return json.loads(texto[start:end+1])
    except Exception:
        return {}

#--------analizar imagen (escaner)-----------""
def analizar_imagen_openai(image_path: str):
    """
    Envía la imagen a OpenAI (modelo con visión) pidiendo un JSON con:
    - nombre del medicamento
    - para_que_sirve (breve descripción)
    - confianza (0-1)
    """
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()

    # PROMPT 
    prompt = (
        "Eres un asistente experto en farmacología. "
        "Analiza la foto de un medicamento (empaque o caja) y devuelve SOLO un JSON claro en español "
        "con la siguiente estructura:\n\n"
        '{'
        '"nombre": "nombre exacto que aparece en el empaque", '
        '"para_que_sirve": "explicación breve (máximo 2 oraciones) sobre su uso o propósito terapéutico", '
        '"confianza": 0.xx'
        '}\n\n'
        "Si no puedes reconocer el medicamento, deja nombre y para_que_sirve vacíos y pon confianza baja."
    )

    try:

        print("\n🖼 Enviando imagen a OpenAI...")
        print("Prompt enviado:", prompt[:100], "...")
        print("Tamaño base64:", len(b64))

        resp = client.chat.completions.create(
            model="gpt-4o",  # modelo con visión
            messages=[
                {"role": "system", "content": "Eres conciso y exacto."},
                {"role": "user", "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}}
                ]}
            ],
            temperature=0.2,
        )
       
        texto = resp.choices[0].message.content.strip()
        print("🔹 Respuesta OpenAI bruta:", texto, "\n")
        data = _extraer_json_seguro(texto)
        nombre = data.get("nombre", "").strip()
        para_que_sirve = data.get("para_que_sirve", "").strip()
        confianza = float(data.get("confianza", 0.0) or 0.0)
        print(f"✅ Nombre detectado: {nombre or '(vacío)'} | Confianza: {confianza}")
        return nombre, para_que_sirve, confianza, texto
    except Exception as e:
        print(f"❌ ERROR en OpenAI: {e}")
        return "", "", 0.0, f"ERROR_OPENAI: {e}"

#-----crear alarmas-----#
@login_required
@require_POST
def crear_alarma(request):
    fecha = request.POST.get("fecha")  # opcional
    hora = request.POST.get("hora")
    mensaje = request.POST.get("mensaje", "¡Es hora de tu alarma!")
    dias = request.POST.get("dias", "")  # 🟢 añade esto

    if not hora:
        return JsonResponse({"ok": False, "error": "Hora requerida"}, status=400)

    try:
        alarma = Alarma.objects.create(
            usuario=request.user,   # 🟢 aquí está la clave
            fecha=fecha or None,
            hora=hora,
            mensaje=mensaje,
            dias=dias,              # 🟢 guarda los días del modal
            activa=True
        )
        logger.info(f"🟢 Alarma creada por {request.user.username}: {alarma.hora} - {alarma.mensaje}")
        return JsonResponse({"ok": True, "id": alarma.id})
    except Exception as e:
        logger.exception("❌ Error al crear alarma")
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

#-------obtener alarma-----#
@login_required
def obtener_alarmas(request):
    """Devuelve las alarmas activas en formato JSON"""
    alarmas = Alarma.objects.filter(activa=True).order_by('hora')
    data = [
        {
            "id": a.id,
            "hora": a.hora.strftime("%H:%M"),
            "mensaje": a.mensaje,
            "dias": a.dias or ""
        }
        for a in alarmas
    ]
    return JsonResponse({"ok": True, "alarmas": data})

#------eliminar alarma----#
@login_required
@require_POST
@csrf_exempt
def eliminar_alarma_ajax(request):
    try:
        print("🟡 Petición recibida para eliminar alarma.")
        print("POST data:", request.POST)

        _id = request.POST.get("id")
        if not _id:
            print("⚠️ ID no recibido.")
            return JsonResponse({"ok": False, "error": "ID no recibido"}, status=400)

        alarma = Alarma.objects.filter(id=_id).first()
        if not alarma:
            print("⚠️ No existe alarma con ese ID.")
            return JsonResponse({"ok": False, "error": "No existe"}, status=404)

        alarma.delete()
        print(f"✅ Alarma eliminada correctamente: ID {_id}")
        return JsonResponse({"ok": True})

    except Exception as e:
        print(f"❌ Error al eliminar alarma: {e}")
        return JsonResponse({"ok": False, "error": str(e)}, status=500)
3
#------notificar SW-----#
@csrf_exempt
def notificar_serviceworker(request):
    """
    Endpoint que recibe notificaciones del scheduler
    y las reenvía al navegador (Service Worker activo).
    """
    try:
        data = json.loads(request.body)
        print(f"📢 Notificación local recibida: {data}")

        # Respuesta rápida para el scheduler
        from django.http import HttpResponse
        response = JsonResponse({"ok": True})
        response["Access-Control-Allow-Origin"] = "*"

        # Inyección de script en páginas abiertas (BroadcastChannel)
        script = f"""
        <script>
        if ('BroadcastChannel' in window) {{
            const ch = new BroadcastChannel('eva_notif');
            ch.postMessage({json.dumps(data)});
        }}
        </script>
        """
        return HttpResponse(script)
    except Exception as e:
        print("❌ Error reenviando notificación:", e)
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

#--------push------#
@csrf_exempt
@login_required
def save_subscription(request):
    """Guarda la suscripción push enviada por el navegador."""
    try:
        data = json.loads(request.body.decode("utf-8"))
        endpoint = data.get("endpoint")
        keys = data.get("keys", {})
        p256dh = keys.get("p256dh")
        auth = keys.get("auth")

        if not endpoint or not p256dh or not auth:
            return JsonResponse({"ok": False, "error": "Datos incompletos"}, status=400)

        sub, created = PushSubscription.objects.get_or_create(
            endpoint=endpoint,
            defaults={"usuario": request.user, "p256dh": p256dh, "auth": auth},
        )
        if not created:
            sub.p256dh = p256dh
            sub.auth = auth
            sub.save(update_fields=["p256dh", "auth"])

        return JsonResponse({"ok": True})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

#--------notificacion prueba----#
@csrf_exempt
def send_push_notification(request):
    """Envía una notificación push de prueba a todas las suscripciones guardadas."""
    if webpush is None:
        return JsonResponse({"ok": False, "error": "WebPush desactivado en este entorno."}, status=503)
    
    from django.utils import timezone

    payload = {
        "title": "⏰ EVA",
        "body": "Notificación de prueba (Web Push)",
        "url": "/inicio/",
        "timestamp": timezone.now().isoformat(),
    }

    vapid_private = getattr(settings, "VAPID_PRIVATE_KEY", None)
    vapid_claims = {"sub": "mailto:tuequipo@eva.com"}

    total = 0
    for sub in PushSubscription.objects.all():
        try:
            webpush(
                subscription_info={
                    "endpoint": sub.endpoint,
                    "keys": {"p256dh": sub.p256dh, "auth": sub.auth},
                },
                data=json.dumps(payload),
                vapid_private_key=vapid_private,
                vapid_claims=vapid_claims,
            )
            total += 1
        except WebPushException as e:
            print("⚠️ Error enviando push:", e)
            sub.delete()  # borra suscripción inválida

    return JsonResponse({"ok": True, "enviadas": total})

#-----flutter------#
from django.views.decorators.csrf import csrf_exempt
from django.contrib.auth.hashers import make_password
import json

def _json_body(request):
    try:
        return json.loads(request.body.decode("utf-8") or "{}")
    except Exception:
        return {}

def _mysql_insert_usuario(nombre_completo, password, tipo, correo=None, telefono=None):
    password_hash = make_password(password)
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO Usuarios (Nombre_Completo, password_hash, Tipo, correo, Telefono, activo)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            [nombre_completo, password_hash, tipo, correo or None, telefono or None, True]
        )
        # Obtener el ID del usuario insertado
        cursor.execute("SELECT LAST_INSERT_ID()")
        usuario_id = cursor.fetchone()[0]
    # Hacer commit a la base de datos
    connection.commit()
    return usuario_id

#----guardar membresía----#
def guardar_membresia(cuidador_id):
    """Guarda la membresía del cuidador en la BD"""
    try:
        fecha_pago = date.today()
        # Fecha de renovación: 1 año desde hoy
        fecha_renovacion = fecha_pago + timedelta(days=365)
        
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO membresia (fecha_pago, fecha_renovacion, estado, cuidador_id)
                VALUES (%s, %s, %s, %s)
                """,
                [fecha_pago, fecha_renovacion, 'activa', cuidador_id]
            )
        # Hacer commit a la base de datos
        connection.commit()
        print(f"✅ Membresía guardada para cuidador ID: {cuidador_id}")
        return True
    except Exception as e:
        connection.rollback()
        print(f"❌ Error al guardar membresía: {e}")
        return False

#----procesar pago----#
@require_POST
@csrf_exempt
def procesar_pago(request):
    """Procesa el pago y guarda la membresía"""
    try:
        data = json.loads(request.body)
        cuidador_id = data.get('cuidador_id')
        
        if not cuidador_id:
            return JsonResponse({'error': 'ID de cuidador no proporcionado'}, status=400)
        
        # Guardar la membresía (sin guardar datos sensibles de tarjeta)
        if guardar_membresia(cuidador_id):
            return JsonResponse({'success': True, 'message': 'Pago procesado exitosamente'})
        else:
            return JsonResponse({'error': 'Error al procesar el pago'}, status=500)
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)

def _mysql_get_usuario_por_correo(correo):
    if not correo:
        return None
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono FROM Usuarios WHERE correo=%s LIMIT 1",
            [correo]
        )
        row = cursor.fetchone()
        if not row:
            return None
        return {
            "id": row[0],
            "nombre_completo": row[1],
            "tipo": row[2],
            "correo": row[3],
            "telefono": row[4],
        }

@csrf_exempt
def api_v1_register_cuidador(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)

    data = _json_body(request)
    nombre_completo = (data.get("nombre_completo") or "").strip()
    password = data.get("password") or ""
    correo = (data.get("correo") or "").strip().lower()
    telefono = (data.get("telefono") or "").strip()

    if not nombre_completo or not password or not correo:
        return JsonResponse({"ok": False, "error": "Faltan campos (nombre_completo, correo, password)."}, status=400)

    # 1) Evitar duplicado en MySQL por correo (UNIQUE)
    if _mysql_get_usuario_por_correo(correo):
        return JsonResponse({"ok": False, "error": "Ese correo ya está registrado."}, status=409)

    # 2) En Django usamos el correo como username (ideal para Flutter)
    if User.objects.filter(username=correo).exists():
        return JsonResponse({"ok": False, "error": "Ese usuario ya existe."}, status=409)

    # 3) Crear en Django
    user = User.objects.create_user(username=correo, password=password, first_name=nombre_completo)

    # 4) Insertar en MySQL
    try:
        _mysql_insert_usuario(nombre_completo, password, "cuidador", correo=correo, telefono=telefono)
    except Exception as e:
        user.delete()
        return JsonResponse({"ok": False, "error": f"No se pudo registrar en MySQL: {e}"}, status=500)

    # 5) Iniciar sesión (sesión/cookies) — útil también en web
    auth_login(request, user)

    return JsonResponse({
        "ok": True,
        "user": {"username": user.username, "nombre_completo": nombre_completo, "tipo": "cuidador", "correo": correo, "telefono": telefono}
    })

@csrf_exempt
def api_v1_register_adulto(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)

    data = _json_body(request)
    nombre_completo = (data.get("nombre_completo") or "").strip()
    password = data.get("password") or ""
    correo = (data.get("correo") or "").strip().lower()
    telefono = (data.get("telefono") or "").strip()

    if not nombre_completo or not password or not correo:
        return JsonResponse({"ok": False, "error": "Faltan campos (nombre_completo, correo, password)."}, status=400)

    if _mysql_get_usuario_por_correo(correo):
        return JsonResponse({"ok": False, "error": "Ese correo ya está registrado."}, status=409)

    if User.objects.filter(username=correo).exists():
        return JsonResponse({"ok": False, "error": "Ese usuario ya existe."}, status=409)

    user = User.objects.create_user(username=correo, password=password, first_name=nombre_completo)

    try:
        _mysql_insert_usuario(nombre_completo, password, "adulto", correo=correo, telefono=telefono)
    except Exception as e:
        user.delete()
        return JsonResponse({"ok": False, "error": f"No se pudo registrar en MySQL: {e}"}, status=500)

    auth_login(request, user)
    return JsonResponse({
        "ok": True,
        "user": {"username": user.username, "nombre_completo": nombre_completo, "tipo": "adulto", "correo": correo, "telefono": telefono}
    })

@csrf_exempt
def api_v1_login(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)

    data = _json_body(request)
    correo = (data.get("correo") or data.get("username") or "").strip().lower()
    password = data.get("password") or ""

    if not correo or not password:
        return JsonResponse({"ok": False, "error": "Faltan campos (correo/username, password)."}, status=400)

    user_auth = authenticate(request, username=correo, password=password)
    if user_auth is None:
        return JsonResponse({"ok": False, "error": "Credenciales incorrectas."}, status=401)

    auth_login(request, user_auth)

    # opcional: leer tipo desde MySQL por correo
    mysql_user = _mysql_get_usuario_por_correo(correo)
    tipo = (mysql_user.get("tipo") if mysql_user else "desconocido")
    nombre = (mysql_user.get("nombre_completo") if mysql_user else (user_auth.first_name or ""))

    return JsonResponse({
        "ok": True,
        "user": {"username": correo, "nombre_completo": nombre, "tipo": tipo, "correo": correo}
    })

@login_required
def api_v1_me(request):
    correo = request.user.username
    mysql_user = _mysql_get_usuario_por_correo(correo)
    if mysql_user:
        return JsonResponse({"ok": True, "user": mysql_user})
    return JsonResponse({"ok": True, "user": {"username": correo, "nombre_completo": request.user.first_name or "", "tipo": "desconocido"}})

@csrf_exempt
@login_required
def api_v1_logout(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)
    auth_logout(request)
    return JsonResponse({"ok": True})
