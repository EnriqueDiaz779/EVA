from django.contrib.auth import authenticate, login as auth_login, logout as auth_logout
from django.contrib.auth.models import User
from django.contrib import messages
from django.http import JsonResponse
from django.views.decorators.http import require_POST
from django.utils import timezone
from django.db import connection, transaction
from django.db.models import Q
from django.contrib.auth.hashers import make_password
from .models import OrdenVoz, Alarma, PatronVoz, CapturaTemporal
from .openai_client import preguntar_openai
from datetime import date
import logging
from difflib import SequenceMatcher
from django.core.files.uploadedfile import InMemoryUploadedFile
from django.core.files.base import ContentFile
from PIL import Image
import io
import base64, json, os
import re
import unicodedata
from django.conf import settings
from openai import OpenAI
from django.views.decorators.csrf import csrf_exempt
from .models import  MedicamentoReconocido
from datetime import datetime, timedelta, time
from django.utils import timezone
from .models import PushSubscription
import secrets
import string
from django.views.decorators.http import require_POST, require_GET
from django.http import JsonResponse
import math
# ------ ADMIN -----------
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required, user_passes_test
from django.utils.crypto import get_random_string
from .models import PerfilUsuario
from django.contrib.auth import logout


try:
    from pywebpush import webpush, WebPushException
except Exception:
    webpush = None

    class WebPushException(Exception):
        pass

#------bloqueo premum------#
def _mysql_cuidador_premium_activo(cuidador_id: int) -> bool:
    """
    Premium del cuidador = existe una membresía 'activa' cuya fecha_renovacion >= hoy.
    """
    hoy = timezone.localdate()
    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT 1
            FROM membresia
            WHERE cuidador_id=%s
              AND estado='activa'
              AND fecha_renovacion >= %s
            ORDER BY fecha_renovacion DESC
            LIMIT 1
        """, [cuidador_id, hoy])
        row = cursor.fetchone()
    return bool(row)

def _mysql_adulto_premium_activo(adulto_id: int) -> bool:
    """
    Premium del adulto = está vinculado con un cuidador y ese cuidador tiene premium activo.
    """
    cuidador = _mysql_get_cuidador_por_adulto(adulto_id)  # tú ya tienes este helper
    if not cuidador:
        return False
    return _mysql_cuidador_premium_activo(int(cuidador["id"]))


def _resolver_mysql_usuario_id(request):
    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident) if ident else None
    if not mysql_user:
        nombre = (request.user.first_name or "").strip()
        mysql_user = verificar_usuario_en_bd(nombre) if nombre else None
    return mysql_user.get("id") if mysql_user else None


def _safe_int(value):
    try:
        if value is None or value == "":
            return None
        return int(value)
    except Exception:
        return None


def _safe_float(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return float(default)


def _parse_hora(valor):
    if not valor:
        return None
    texto = str(valor).strip()
    for fmt in ("%H:%M", "%H:%M:%S"):
        try:
            return datetime.strptime(texto, fmt).time()
        except Exception:
            continue
    return None


def _parse_fecha(valor):
    if not valor:
        return None
    texto = str(valor).strip()
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y"):
        try:
            return datetime.strptime(texto, fmt).date()
        except Exception:
            continue
    return None


def _parse_lista_horas(valores):
    horas = []
    if not isinstance(valores, list):
        return horas
    for v in valores:
        h = _parse_hora(v)
        if h:
            horas.append(h)
    # quita duplicados conservando orden
    out = []
    seen = set()
    for h in sorted(horas):
        k = h.strftime("%H:%M")
        if k in seen:
            continue
        seen.add(k)
        out.append(h)
    return out


def _momentos_a_horas(momentos):
    # Horarios por defecto pensados para adulto mayor.
    mapa = {
        "despertar": time(7, 0),
        "antes_desayuno": time(7, 40),
        "desayuno": time(8, 0),
        "antes_almuerzo": time(13, 40),
        "almuerzo": time(14, 0),
        "comida": time(16, 0),
        "mediodia": time(12, 0),
        "antes_cena": time(19, 40),
        "cena": time(20, 0),
        "noche": time(22, 0),
    }
    horas = []
    if isinstance(momentos, list):
        for m in momentos:
            clave = str(m or "").strip().lower()
            if clave in mapa:
                horas.append(mapa[clave])
    # únicos ordenados
    out = []
    seen = set()
    for h in sorted(horas):
        k = h.strftime("%H:%M")
        if k in seen:
            continue
        seen.add(k)
        out.append(h)
    return out


def _inferir_momentos_desde_texto(texto):
    t = (texto or "").lower()
    if not t:
        return []
    momentos = []
    if "despert" in t:
        momentos.append("despertar")
    if "antes del almuerzo" in t or "antes de almuerzo" in t:
        momentos.append("antes_almuerzo")
    if "almuerzo" in t and "antes del almuerzo" not in t:
        momentos.append("almuerzo")
    if "comida" in t:
        momentos.append("comida")
    if "antes de cena" in t or "antes del cena" in t or "antes cena" in t:
        momentos.append("antes_cena")
    if "cena" in t and "antes de cena" not in t and "antes cena" not in t:
        momentos.append("cena")
    if "medio dia" in t or "mediodia" in t:
        momentos.append("mediodia")
    return momentos


def _extraer_horas_de_texto(texto):
    t = (texto or "").lower()
    if not t:
        return []
    # Evita confundir "cada 6 hrs" (intervalo) con hora fija.
    if "cada" in t and "hr" in t and ":" not in t:
        return []

    horas = []
    for hh, mm in re.findall(r"\b([01]?\d|2[0-3]):([0-5]\d)\b", t):
        try:
            horas.append(time(int(hh), int(mm)))
        except Exception:
            pass

    # Casos "a las 10 y 18" o "10 y 18:00"
    if not horas and ("a las" in t or "alas" in t):
        segmento = t.split("a las", 1)[-1]
        nums = re.findall(r"\b([01]?\d|2[0-3])\b", segmento)
        if len(nums) >= 2:
            try:
                horas.extend([time(int(nums[0]), 0), time(int(nums[1]), 0)])
            except Exception:
                pass

    out = []
    seen = set()
    for h in sorted(horas):
        k = h.strftime("%H:%M")
        if k in seen:
            continue
        seen.add(k)
        out.append(h)
    return out


def _normalizar_fases(raw_fases, fecha_base, duracion_default, unidad_default):
    fases = []
    if not isinstance(raw_fases, list):
        return fases
    for fase in raw_fases:
        if not isinstance(fase, dict):
            continue
        dur_val = _safe_int(fase.get("duracion_valor")) or duracion_default
        dur_uni = str(fase.get("duracion_unidad") or unidad_default).strip().lower()
        if dur_uni not in ("dias", "semanas", "meses"):
            dur_uni = "dias"

        horas_fijas = _parse_lista_horas(fase.get("horas_fijas"))
        if not horas_fijas:
            horas_fijas = _momentos_a_horas(fase.get("momentos"))
        if not horas_fijas:
            momentos_txt = _inferir_momentos_desde_texto(fase.get("frecuencia_texto") or "")
            horas_fijas = _momentos_a_horas(momentos_txt)
        if not horas_fijas:
            horas_fijas = _extraer_horas_de_texto(fase.get("frecuencia_texto") or "")

        frecuencia_cada_valor = _safe_int(fase.get("frecuencia_cada_valor"))
        frecuencia_unidad = str(fase.get("frecuencia_unidad") or "").strip().lower()
        if frecuencia_unidad not in ("horas", "dias"):
            frecuencia_unidad = None
        fases.append(
            {
                "duracion_valor": dur_val,
                "duracion_unidad": dur_uni,
                "horas_fijas": horas_fijas,
                "frecuencia_cada_valor": frecuencia_cada_valor,
                "frecuencia_unidad": frecuencia_unidad,
            }
        )
    return fases


def _normalizar_medicamento_receta(raw):
    if not isinstance(raw, dict):
        return None

    nombre = (
        str(raw.get("nombre") or raw.get("medicamento") or raw.get("nombre_medicamento") or "")
        .strip()
    )
    if not nombre:
        return None

    frecuencia_texto = str(raw.get("frecuencia_texto") or raw.get("cada_cuanto") or "").strip()
    frecuencia_unidad = str(raw.get("frecuencia_unidad") or "").strip().lower()
    frecuencia_cada_valor = _safe_int(raw.get("frecuencia_cada_valor"))

    if (frecuencia_cada_valor is None or frecuencia_cada_valor <= 0) and frecuencia_texto:
        m = re.search(r"cada\s+(\d+)\s*(hora|horas|dia|dias)", frecuencia_texto.lower())
        if m:
            frecuencia_cada_valor = int(m.group(1))
            frecuencia_unidad = "horas" if "hora" in m.group(2) else "dias"

    if frecuencia_unidad not in ("horas", "dias"):
        frecuencia_unidad = "horas" if "hora" in frecuencia_texto.lower() else "dias"

    if not frecuencia_cada_valor or frecuencia_cada_valor <= 0:
        frecuencia_cada_valor = 8 if frecuencia_unidad == "horas" else 1

    duracion_valor = _safe_int(raw.get("duracion_valor"))
    duracion_unidad = str(raw.get("duracion_unidad") or "").strip().lower()
    duracion_texto = str(raw.get("duracion_texto") or "").strip()
    if (duracion_valor is None or duracion_valor <= 0) and duracion_texto:
        m = re.search(r"(\d+)\s*(dia|dias|semana|semanas|mes|meses)", duracion_texto.lower())
        if m:
            duracion_valor = int(m.group(1))
            token = m.group(2)
            if "semana" in token:
                duracion_unidad = "semanas"
            elif "mes" in token:
                duracion_unidad = "meses"
            else:
                duracion_unidad = "dias"
    if not duracion_valor or duracion_valor <= 0:
        duracion_valor = 7
    if duracion_unidad not in ("dias", "semanas", "meses"):
        duracion_unidad = "dias"

    horas_fijas = _parse_lista_horas(raw.get("horas_fijas"))
    if not horas_fijas:
        horas_fijas = _momentos_a_horas(raw.get("momentos"))
    if not horas_fijas:
        horas_fijas = _momentos_a_horas(_inferir_momentos_desde_texto(frecuencia_texto))
    if not horas_fijas:
        horas_fijas = _extraer_horas_de_texto(frecuencia_texto)

    horario_tipo = str(raw.get("horario_tipo") or "").strip().lower()
    if horario_tipo not in ("horas_fijas", "intervalo"):
        horario_tipo = "horas_fijas" if horas_fijas else "intervalo"

    fecha_inicio_raw = _parse_fecha(raw.get("fecha_inicio"))
    hoy = timezone.localdate()
    fecha_inicio = fecha_inicio_raw or hoy
    # Si la receta trae fecha antigua impresa, iniciamos desde hoy para crear alarmas vigentes.
    if fecha_inicio < hoy:
        fecha_inicio = hoy

    fases = _normalizar_fases(
        raw.get("fases"),
        fecha_inicio,
        duracion_valor,
        duracion_unidad,
    )

    # Si no hay nada claro, mejor 1 vez al dia (evita alarmas fuera de control).
    if not horas_fijas and not fases and (not frecuencia_cada_valor or frecuencia_cada_valor <= 0):
        frecuencia_cada_valor = 1
        frecuencia_unidad = "dias"

    return {
        "nombre_medicamento": nombre,
        "dosis_texto": str(raw.get("dosis") or raw.get("dosis_texto") or "").strip(),
        "horario_tipo": horario_tipo,
        "horas_fijas": horas_fijas,
        "frecuencia_cada_valor": frecuencia_cada_valor,
        "frecuencia_unidad": frecuencia_unidad,
        "frecuencia_texto": frecuencia_texto or f"cada {frecuencia_cada_valor} {frecuencia_unidad}",
        "duracion_valor": duracion_valor,
        "duracion_unidad": duracion_unidad,
        "duracion_texto": duracion_texto or f"{duracion_valor} {duracion_unidad}",
        "hora_inicio": _parse_hora(raw.get("hora_inicio")) or time(8, 0),
        "fecha_inicio": fecha_inicio,
        "notas": str(raw.get("notas") or "").strip(),
        "confianza": max(0.0, min(1.0, _safe_float(raw.get("confianza"), 0.75))),
        "fases": fases,
    }


def _duracion_en_dias(valor, unidad):
    if valor <= 0:
        return 7
    if unidad == "semanas":
        return valor * 7
    if unidad == "meses":
        return valor * 30
    return valor


def _generar_fechas_alarma(med):
    fecha_inicio = med["fecha_inicio"]
    hora_inicio = med["hora_inicio"]
    cada = med["frecuencia_cada_valor"]
    unidad = med["frecuencia_unidad"]
    dur_dias = _duracion_en_dias(med["duracion_valor"], med["duracion_unidad"])

    fases = med.get("fases") or []
    horas_fijas = med.get("horas_fijas") or []

    fechas = []

    if fases:
        cursor_day = fecha_inicio
        for fase in fases:
            fase_dias = _duracion_en_dias(fase["duracion_valor"], fase["duracion_unidad"])
            fase_horas = fase.get("horas_fijas") or horas_fijas
            if fase_horas:
                for d in range(max(fase_dias, 1)):
                    dia = cursor_day + timedelta(days=d)
                    for h in fase_horas:
                        fechas.append(datetime.combine(dia, h))
            else:
                f_val = fase.get("frecuencia_cada_valor") or cada
                f_uni = fase.get("frecuencia_unidad") or unidad
                inicio_dt = datetime.combine(cursor_day, hora_inicio)
                fin_dt = datetime.combine(cursor_day + timedelta(days=max(fase_dias - 1, 0)), time(23, 59))
                paso = timedelta(hours=f_val) if f_uni == "horas" else timedelta(days=f_val)
                actual = inicio_dt
                while actual <= fin_dt and len(fechas) < 365:
                    fechas.append(actual)
                    actual += paso
            cursor_day = cursor_day + timedelta(days=max(fase_dias, 1))
        fecha_fin = (cursor_day - timedelta(days=1)) if cursor_day > fecha_inicio else fecha_inicio
        return sorted(fechas), fecha_fin

    if horas_fijas:
        for d in range(max(dur_dias, 1)):
            dia = fecha_inicio + timedelta(days=d)
            for h in horas_fijas:
                fechas.append(datetime.combine(dia, h))
        fecha_fin = fecha_inicio + timedelta(days=max(dur_dias - 1, 0))
        return sorted(fechas), fecha_fin

    inicio_dt = datetime.combine(fecha_inicio, hora_inicio)
    fin_dt = datetime.combine(fecha_inicio + timedelta(days=max(dur_dias - 1, 0)), time(23, 59))
    paso = timedelta(hours=cada) if unidad == "horas" else timedelta(days=cada)
    actual = inicio_dt
    while actual <= fin_dt and len(fechas) < 365:
        fechas.append(actual)
        actual += paso
    if not fechas:
        fechas = [inicio_dt]
    return fechas, fin_dt.date()


def _analizar_receta_openai(image_bytes):
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    max_side = 1600
    w, h = img.size
    scale = min(max_side / float(max(w, h)), 1.0)
    if scale < 1.0:
        img = img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85, optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode("utf-8")

    prompt = (
        "Analiza la receta medica y devuelve SOLO JSON valido. "
        "Extrae horarios reales para alarmas sin inventar datos. "
        "Formato exacto:\n"
        '{"medicamentos":[{"nombre":"", "dosis":"", "frecuencia_texto":"", '
        '"horario_tipo":"horas_fijas|intervalo", '
        '"horas_fijas":["10:00","18:00"], '
        '"momentos":["despertar","antes_almuerzo","antes_cena","mediodia"], '
        '"frecuencia_cada_valor":6, "frecuencia_unidad":"horas|dias", '
        '"duracion_valor":8, "duracion_unidad":"dias|semanas|meses", '
        '"fases":[{"duracion_valor":8,"duracion_unidad":"dias","momentos":["antes_almuerzo","comida","cena"]},'
        '{"duracion_valor":1,"duracion_unidad":"meses","momentos":["antes_almuerzo","antes_cena"]}], '
        '"hora_inicio":"08:00", "fecha_inicio":"YYYY-MM-DD", "notas":"", "confianza":0.90}]}\n'
        "Reglas: "
        "1) Si el texto tiene horas explicitas, ponlas en horas_fijas. "
        "2) Si dice cada X horas, usa horario_tipo=intervalo con frecuencia_cada_valor/unidad. "
        "3) Si hay cambios por periodos (ej. '8 dias... despues 1 mes...'), usa fases. "
        "4) Si dice PRN, agregalo en notas y no elimines el esquema principal. "
        "5) Si no se reconoce receta, devuelve medicamentos=[]."
    )

    resp = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": "Extrae datos clinicos de recetas. Responde solo JSON."},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                ],
            },
        ],
        temperature=0.1,
    )
    texto = (resp.choices[0].message.content or "").strip()
    data = _extraer_json_seguro(texto)
    meds_raw = data.get("medicamentos", []) if isinstance(data, dict) else []

    meds = []
    for item in meds_raw:
        med = _normalizar_medicamento_receta(item)
        if med:
            meds.append(med)
    return meds, texto


def _guardar_tratamiento_medicamentos_alarmas(usuario_id, medicamentos, django_user=None):
    resumen = []
    total_alarmas = 0
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute(
                "INSERT INTO tratamientos (usuario_id, origen, estado) VALUES (%s, %s, %s)",
                [usuario_id, "OCR", "activo"],
            )
            tratamiento_id = cursor.lastrowid

            for med in medicamentos:
                fechas_alarma, fecha_fin = _generar_fechas_alarma(med)
                cursor.execute(
                    """
                    INSERT INTO tratamiento_medicamentos (
                        tratamiento_id, nombre_medicamento, dosis_texto,
                        frecuencia_cada_valor, frecuencia_unidad, frecuencia_texto,
                        duracion_valor, duracion_unidad, duracion_texto,
                        fecha_inicio, hora_inicio, fecha_fin,
                        regla_horario, notas, confianza, confirmado
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    [
                        tratamiento_id,
                        med["nombre_medicamento"],
                        med["dosis_texto"] or None,
                        med["frecuencia_cada_valor"],
                        med["frecuencia_unidad"],
                        med["frecuencia_texto"] or None,
                        med["duracion_valor"],
                        med["duracion_unidad"],
                        med["duracion_texto"] or None,
                        med["fecha_inicio"],
                        med["hora_inicio"],
                        fecha_fin,
                        (
                            "horas_fijas: " + ", ".join([h.strftime("%H:%M") for h in (med.get("horas_fijas") or [])])
                            if (med.get("horas_fijas") or [])
                            else f"cada {med['frecuencia_cada_valor']} {med['frecuencia_unidad']}"
                        ),
                        med["notas"] or None,
                        round(med["confianza"] * 100.0, 2),
                        0,
                    ],
                )
                id_tm = cursor.lastrowid

                creadas = 0
                for fecha_hora in fechas_alarma:
                    mensaje = f"Tomar {med['nombre_medicamento']}"
                    if med["dosis_texto"]:
                        mensaje = f"{mensaje} ({med['dosis_texto']})"
                    cursor.execute(
                        """
                        INSERT INTO alarma (Fecha_hora, Mensaje, Estado, tipo, tratamiento_id, id_tm, Usuario_id)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """,
                        [fecha_hora, mensaje, "pendiente", "medicamento", tratamiento_id, id_tm, usuario_id],
                    )
                    if django_user is not None:
                        Alarma.objects.create(
                            usuario=django_user,
                            fecha=fecha_hora.date(),
                            hora=fecha_hora.time(),
                            mensaje=mensaje,
                            activa=True,
                            entregada=False,
                        )
                    creadas += 1
                    total_alarmas += 1

                resumen.append(
                    {
                        "id_tm": id_tm,
                        "nombre": med["nombre_medicamento"],
                        "dosis": med["dosis_texto"],
                        "frecuencia": med["frecuencia_texto"],
                        "alarmas_creadas": creadas,
                    }
                )
    return tratamiento_id, total_alarmas, resumen


@login_required
@require_POST
def crear_alarmas_receta(request):
    ok, resp = _require_premium_adulto(request)
    if not ok:
        return resp
    
    try:
        foto = request.FILES.get("foto")
        if not foto:
            payload = json.loads(request.body.decode("utf-8") or "{}")
            items = payload.get("items", [])
            return JsonResponse(
                {
                    "ok": True,
                    "message": f"Detecte {len(items)} medicamentos",
                    "detectados": len(items),
                    "medicamentos": items,
                }
            )

        content_type = (getattr(foto, "content_type", "") or "").lower()
        if not content_type.startswith("image/"):
            return JsonResponse({"ok": False, "error": "Formato no valido. Debe ser imagen."}, status=400)

        image_bytes = foto.read()
        if not image_bytes:
            return JsonResponse({"ok": False, "error": "No se pudo leer la imagen."}, status=400)

        medicamentos, debug_text = _analizar_receta_openai(image_bytes)
        if not medicamentos:
            return JsonResponse(
                {
                    "ok": False,
                    "message": "Detecte 0 medicamentos",
                    "detectados": 0,
                    "medicamentos": [],
                    "error": "No pude extraer medicamentos de la receta.",
                    "debug": debug_text,
                },
                status=200,
            )

        usuario_id = _resolver_mysql_usuario_id(request)
        if not usuario_id:
            return JsonResponse({"ok": False, "error": "No pude resolver el Usuario_id."}, status=400)

        tratamiento_id, total_alarmas, resumen = _guardar_tratamiento_medicamentos_alarmas(
            usuario_id, medicamentos, django_user=request.user
        )
        detectados = len(resumen)

        return JsonResponse(
            {
                "ok": True,
                "message": f"Detecte {detectados} medicamentos",
                "detectados": detectados,
                "tratamiento_id": tratamiento_id,
                "alarmas_creadas": total_alarmas,
                "medicamentos": resumen,
            }
        )
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=400)

client = OpenAI(api_key=settings.OPENAI_API_KEY)

logger = logging.getLogger(__name__)

#-- función para cuidadores que escanean receta para su adulto vinculado --#
@login_required
@require_POST
def crear_alarmas_receta_cuidador(request):
    """
    El cuidador escanea una receta, pero las alarmas/tratamiento
    se guardan para el adulto vinculado.
    """
    try:
        ident = (request.user.username or "").strip()
        mysql_user = verificar_usuario_en_bd(ident)

        if not mysql_user or mysql_user.get("tipo") != "cuidador":
            return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

        cuidador_id = mysql_user["id"]

        # Validar premium del cuidador
        if not _mysql_cuidador_premium_activo(int(cuidador_id)):
            return JsonResponse(
                {"ok": False, "error": "Función premium. Activa tu membresía para usar recetas."},
                status=403
            )

        adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
        if not adulto_vinculado:
            return JsonResponse(
                {"ok": False, "error": "No tienes un adulto vinculado."},
                status=403
            )

        adulto_id = int(adulto_vinculado["id"])

        # Obtener correo del adulto para mapearlo a Django user
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT Nombre_Completo, correo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
                [adulto_id],
            )
            row = cursor.fetchone()

        if not row:
            return JsonResponse({"ok": False, "error": "No encontré al adulto vinculado."}, status=404)

        nombre_adulto = row[0] or ""
        correo_adulto = row[1] or ""

        adulto_django = _django_user_from_mysql_adulto(nombre_adulto, correo_adulto)
        if not adulto_django:
            return JsonResponse(
                {"ok": False, "error": "No encontré el usuario Django del adulto."},
                status=404
            )

        foto = request.FILES.get("foto")
        if not foto:
            payload = json.loads(request.body.decode("utf-8") or "{}")
            items = payload.get("items", [])
            return JsonResponse(
                {
                    "ok": True,
                    "message": f"Detecté {len(items)} medicamentos",
                    "detectados": len(items),
                    "medicamentos": items,
                }
            )

        content_type = (getattr(foto, "content_type", "") or "").lower()
        if not content_type.startswith("image/"):
            return JsonResponse({"ok": False, "error": "Formato no válido. Debe ser imagen."}, status=400)

        image_bytes = foto.read()
        if not image_bytes:
            return JsonResponse({"ok": False, "error": "No se pudo leer la imagen."}, status=400)

        medicamentos, debug_text = _analizar_receta_openai(image_bytes)

        if not medicamentos:
            return JsonResponse(
                {
                    "ok": False,
                    "message": "Detecté 0 medicamentos",
                    "detectados": 0,
                    "medicamentos": [],
                    "error": "No pude extraer medicamentos de la receta.",
                    "debug": debug_text,
                },
                status=200,
            )

        tratamiento_id, total_alarmas, resumen = _guardar_tratamiento_medicamentos_alarmas(
            adulto_id,
            medicamentos,
            django_user=adulto_django
        )

        detectados = len(resumen)

        return JsonResponse(
            {
                "ok": True,
                "message": f"Detecté {detectados} medicamentos para {adulto_vinculado['nombre']}",
                "detectados": detectados,
                "tratamiento_id": tratamiento_id,
                "alarmas_creadas": total_alarmas,
                "medicamentos": resumen,
                "adulto": {
                    "id": adulto_id,
                    "nombre": adulto_vinculado["nombre"]
                }
            }
        )

    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=400)

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

        if not usuario_mysql.get("activo", True):
            print(f"⛔ Usuario desactivado: {nombre_original}")
            messages.error(request, "Tu cuenta está desactivada. Contacta al administrador.")
            return render(request, 'miapp/login.html', {"previous_username": nombre_original})
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
        
        # Redirigir según tipo en MySQL
        tipo_usuario = (usuario_mysql.get('tipo') or '').strip().lower()

        if tipo_usuario == "admin":
            print(f"🎯 Redirigiendo admin a interfaz_admin")
            return redirect('interfaz_admin')
        elif tipo_usuario == "cuidador":
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
    #####################################################################
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
def verificar_usuario_en_bd(identificador):
    """Busca por correo (si coincide) o por Nombre_Completo"""
    try:
        ident = (identificador or "").strip()
        if not ident:
            return None

        with connection.cursor() as cursor:
            # 1) buscar por correo
            cursor.execute(
                "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono, activo "
                "FROM Usuarios WHERE correo = %s LIMIT 1",
                [ident.lower()]
            )
            row = cursor.fetchone()
            if row:
                return {
                    "id": row[0],
                    "nombre": row[1],
                    "tipo": row[2],
                    "correo": row[3],
                    "telefono": row[4],
                    "activo": bool(row[5]),
                }

            # 2) buscar por nombre
            cursor.execute(
                "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono, activo "
                "FROM Usuarios WHERE Nombre_Completo = %s LIMIT 1",
                [ident]
            )
            row = cursor.fetchone()
            if row:
                return {
                    "id": row[0],
                    "nombre": row[1],
                    "tipo": row[2],
                    "correo": row[3],
                    "telefono": row[4],
                    "activo": bool(row[5]),
                }
    except Exception as e:
        print(f"❌ Error verificando usuario: {e}")
    return None
    
#--- CAMBIOS ADMIN ---------
def _mysql_get_tipo_usuario_logueado(request):
    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)

    if not mysql_user:
        nombre = (request.user.first_name or "").strip()
        mysql_user = verificar_usuario_en_bd(nombre)

    if not mysql_user:
        return None

    return (mysql_user.get("tipo") or "").strip().lower()

def _es_admin(request):
    return _mysql_get_tipo_usuario_logueado(request) == "admin"

#--- PROTEGER DE LOS DEMAS USUARIOS, SOLO ADMIN PUEDE ACCEDER -----------
def _require_admin(request):
    tipo = _mysql_get_tipo_usuario_logueado(request)
    if tipo != "admin":
        return False, JsonResponse({"ok": False, "error": "Acceso solo para administradores."}, status=403)
    return True, None


#----login en bd------#
def registrar_login_en_db(identificador, request):
    try:
        ident = (identificador or "").strip()

        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT Id_Usuario FROM Usuarios WHERE correo=%s OR Nombre_Completo=%s LIMIT 1",
                [ident.lower(), ident]
            )
            result = cursor.fetchone()
            if not result:
                print("⚠️ Usuario no encontrado en tabla Usuarios")
                return

            usuario_id = result[0]
            ip_address = get_client_ip(request)
            user_agent = request.META.get('HTTP_USER_AGENT', '')[:500]

            cursor.execute(
                "INSERT INTO registros_login (usuario_id, ip_address, fecha_entrada, user_agent, activo) "
                "VALUES (%s, %s, NOW(), %s, %s)",
                [usuario_id, ip_address, user_agent, True]
            )
            connection.commit()
            print(f"✅ Login registrado para usuario ID: {usuario_id}")
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

#-------- ADMINISTRADOR ----------#
@login_required
def inicio(request):
    tipo_usuario = _mysql_get_tipo_usuario_logueado(request)

    if tipo_usuario == "admin":
        return redirect("interfaz_admin")

    nombre = request.user.first_name or request.user.username
    ultimas = OrdenVoz.objects.filter(usuario=request.user)[:5]

    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)

    codigo_unico = None
    es_premium = False
    esta_vinculado = False

    if mysql_user and mysql_user.get("tipo") == "adulto":
        usuario_id = int(mysql_user.get("id") or 0)
        if usuario_id:
            codigo_unico = _mysql_get_or_create_codigo_unico(usuario_id)
            es_premium = _mysql_adulto_premium_activo(usuario_id)

            vinculo = _mysql_get_vinculo_por_adulto(usuario_id)
            esta_vinculado = bool(vinculo and vinculo.get("activo"))

    return render(request, 'miapp/inicio.html', {
        "nombre": nombre,
        "ultimas": ultimas,
        "codigo_unico": codigo_unico,
        "es_premium": es_premium,
        "esta_vinculado": esta_vinculado,
    })

# ---------CÓDIGO ÚNICO (ADULTO)------#
def _mysql_get_codigo_unico(usuario_id: int):
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT Codigo_unico FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
            [usuario_id],
        )
        row = cursor.fetchone()
        return row[0] if row and row[0] else None


def _mysql_set_codigo_unico(usuario_id: int, codigo: str):
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE Usuarios SET Codigo_unico=%s WHERE Id_Usuario=%s",
            [codigo, usuario_id],
        )
    connection.commit()


def _generar_codigo_unico(longitud=10):
    alfabeto = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alfabeto) for _ in range(longitud))


def _mysql_get_or_create_codigo_unico(usuario_id: int):
    codigo = _mysql_get_codigo_unico(usuario_id)
    if codigo:
        return codigo

    for _ in range(20):
        nuevo = _generar_codigo_unico(10)
        try:
            _mysql_set_codigo_unico(usuario_id, nuevo)
            return nuevo
        except Exception:
            try:
                connection.rollback()
            except Exception:
                pass
    return None


def _mysql_get_adulto_por_codigo(codigo: str):
    """Busca al adulto en Usuarios por Codigo_unico."""
    codigo = (codigo or "").strip().upper()
    if not codigo:
        return None

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT Id_Usuario, Nombre_Completo, correo, Tipo "
            "FROM Usuarios WHERE UPPER(Codigo_unico)=UPPER(%s) LIMIT 1",
            [codigo],
        )
        row = cursor.fetchone()

    if not row or row[3] != "adulto":
        return None

    return {"id": row[0], "nombre": row[1], "correo": row[2]}


def _mysql_get_vinculo_por_adulto(adulto_id: int):
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT Id_AdultoCuidador, Cuidador_id, Activo "
            "FROM adulto_cuidador WHERE Adulto_id=%s AND Activo=1 "
            "ORDER BY fecha_asignacion DESC LIMIT 1",
            [adulto_id],
        )
        row = cursor.fetchone()
        if not row:
            return None
        return {"id": row[0], "cuidador_id": row[1], "activo": row[2]}


def _django_user_from_mysql_usuario(nombre: str, correo: str):
    """Mapea un usuario MySQL a un User de Django por correo o nombre."""
    correo_norm = (correo or "").strip().lower()
    nombre_norm = (nombre or "").strip()

    if correo_norm:
        u = (
            User.objects
            .filter(Q(username__iexact=correo_norm) | Q(email__iexact=correo_norm))
            .first()
        )
        if u:
            return u

    if nombre_norm:
        u = User.objects.filter(first_name__iexact=nombre_norm).first()
        if u:
            return u
        u = User.objects.filter(username__iexact=nombre_norm).first()
        if u:
            return u

    return None


def _django_user_from_mysql_adulto(nombre: str, correo: str):
    """Compat: mantiene el helper previo para usos existentes."""
    return _django_user_from_mysql_usuario(nombre, correo)


def _enviar_webpush_a_usuario(django_user, payload: dict) -> int:
    if webpush is None or not django_user:
        return 0

    subs = PushSubscription.objects.filter(usuario=django_user)
    if not subs.exists():
        return 0

    vapid_private = getattr(settings, "VAPID_PRIVATE_KEY", None)
    vapid_claims = {"sub": "mailto:tuequipo@eva.com"}
    total = 0

    for sub in subs:
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
            sub.delete()

    return total


#------vincular adulto por codigo-------#
@csrf_exempt
@require_POST
def vincular_adulto_por_codigo(request):
    username = (request.POST.get("username") or "").strip()
    if not username:
        return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

    mysql_user = _mysql_get_usuario_por_identificador(username) or verificar_usuario_en_bd(username)
    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return JsonResponse({"ok": False, "error": "Solo cuidadores pueden vincular."}, status=403)

    cuidador_id = mysql_user["id"]
    codigo = (request.POST.get("codigo") or "").strip().upper()

    if not codigo:
        return JsonResponse({"ok": False, "error": "Ingresa el código único."}, status=400)

    adulto = _mysql_get_adulto_por_codigo(codigo)
    if not adulto:
        return JsonResponse({"ok": False, "error": "Código inválido."}, status=404)

    try:
        _mysql_crear_vinculo_unico(cuidador_id, adulto["id"], codigo)
    except ValueError as ve:
        code = str(ve)
        if code == "YA_VINCULADO":
            return JsonResponse({"ok": False, "error": "Ya tienes un adulto vinculado."}, status=409)
        if code == "ADULTO_CON_OTRO_CUIDADOR":
            return JsonResponse({"ok": False, "error": "Este adulto ya está vinculado con otro cuidador."}, status=409)
        return JsonResponse({"ok": False, "error": "No se pudo vincular."}, status=500)

    return JsonResponse({
        "ok": True,
        "adulto": {
            "id": adulto["id"],
            "nombre": adulto["nombre"],
        }
    })

#----------cambiar adulto mayor------#
@login_required
@require_POST
def cambiar_adulto_actual(request):
    return JsonResponse({"ok": False, "error": "No disponible en plan sencillo."}, status=403)

#------interfaz cuidador-----#
@login_required
def interfaz_cuidador(request):
    if _es_admin(request):
        return redirect("interfaz_admin")

    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)

    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return redirect("inicio")

    nombre = ""
    correo = ""
    telefono = ""
    cuidador_id = None

    if mysql_user:
        cuidador_id = mysql_user.get("id")
        nombre = mysql_user.get("nombre") or ""
        correo = (mysql_user.get("correo") or "").strip()
        telefono = (mysql_user.get("telefono") or "").strip()
    else:
        nombre = request.user.first_name or ""
        correo = request.user.username or ""

    adulto_vinculado = None
    meds_payload = []

    if cuidador_id:
        adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
        if adulto_vinculado:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT correo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
                    [adulto_vinculado["id"]],
                )
                r = cursor.fetchone()
            correo_adulto = (r[0] if r else "") or ""

            adulto_django = _django_user_from_mysql_adulto(adulto_vinculado["nombre"], correo_adulto)
            if adulto_django:
                meds_payload = (
                    MedicamentoReconocido.objects.filter(usuario=adulto_django)
                    .order_by("-creado")[:10]
                )

    return render(
        request,
        "miapp/Interfaz_cuidador.html",
        {
            "cuidador_nombre": nombre,
            "cuidador_correo": correo,
            "cuidador_telefono": telefono,
            "adulto_vinculado": adulto_vinculado,
            "meds_adulto": meds_payload,
            "bloqueado_por_vinculo": (adulto_vinculado is None),
            "mapbox_token": settings.MAPBOX_TOKEN_PUBLIC,
        },
    )

#------MYSQL IDENTIFICADOR------#
def _mysql_get_usuario_por_identificador(identificador: str):
    """Busca al usuario por correo (si parece correo) o por Nombre_Completo."""
    ident = (identificador or "").strip()
    if not ident:
        return None

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono "
            "FROM Usuarios WHERE correo=%s LIMIT 1",
            [ident.lower()],
        )
        row = cursor.fetchone()
        if row:
            return {
                "id": row[0],
                "nombre_completo": row[1],
                "tipo": row[2],
                "correo": row[3],
                "telefono": row[4],
            }

        cursor.execute(
            "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono "
            "FROM Usuarios WHERE Nombre_Completo=%s LIMIT 1",
            [ident],
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

    # NO iniciar sesión aquí
    # Mandar a login con mensaje corto
    messages.success(request, "✅ Pago realizado con éxito. Ahora inicia sesión.")
    return redirect("login")


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
        try:
            alarm_created = _crear_alarma_desde_meta(request.user, meta)
            if alarm_created:
                logger.info(f"🟢 Alarma creada vía IA: meta={meta}")
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

def _mapear_dia_a_abrev(valor):
    if valor is None:
        return None

    if isinstance(valor, int):
        mapa_num = {
            1: "lun",
            2: "mar",
            3: "mie",
            4: "jue",
            5: "vie",
            6: "sab",
            7: "dom",
        }
        return mapa_num.get(valor)

    txt = unicodedata.normalize("NFKD", str(valor).strip().lower())
    txt = txt.encode("ascii", "ignore").decode("ascii")
    txt = re.sub(r"[^a-z]", "", txt)

    mapa = {
        "lun": "lun",
        "lunes": "lun",
        "mar": "mar",
        "martes": "mar",
        "mie": "mie",
        "miercoles": "mie",
        "jue": "jue",
        "jueves": "jue",
        "vie": "vie",
        "viernes": "vie",
        "sab": "sab",
        "sábado": "sab",
        "sabado": "sab",
        "dom": "dom",
        "domingo": "dom",
    }
    return mapa.get(txt)


def _normalizar_dias_meta(meta):
    """
    Recibe meta de OpenAI y devuelve string listo para guardar en Django:
    'lun,mar,vie'
    """
    if not isinstance(meta, dict):
        return ""

    raw = (
        meta.get("dias")
        or meta.get("dias_semana")
        or meta.get("dia")
        or meta.get("repetir")
        or ""
    )

    items = []

    if isinstance(raw, list):
        items = raw
    elif isinstance(raw, str) and raw.strip():
        items = re.split(r"[,;/]+", raw.strip())
    else:
        items = []

    normalizados = []
    seen = set()

    for item in items:
        dia = _mapear_dia_a_abrev(item)
        if dia and dia not in seen:
            seen.add(dia)
            normalizados.append(dia)

    return ",".join(normalizados)


def _normalizar_fecha_meta(meta):
    """
    Devuelve objeto date o None.
    """
    if not isinstance(meta, dict):
        return None

    fecha_raw = meta.get("fecha")
    fecha = _parse_fecha(fecha_raw)

    if fecha:
        return fecha

    relativo = str(meta.get("fecha_relativa") or meta.get("dia_relativo") or "").strip().lower()
    hoy = timezone.localdate()

    if relativo == "hoy":
        return hoy
    if relativo == "mañana" or relativo == "manana":
        return hoy + timedelta(days=1)

    return None


def _normalizar_hora_meta(meta):
    """
    Devuelve objeto time o None.
    """
    if not isinstance(meta, dict):
        return None

    hora_raw = meta.get("hora")
    hora = _parse_hora(hora_raw)
    return hora

def _crear_alarma_desde_meta(django_user, meta):
    if not isinstance(meta, dict):
        return False

    hora_obj = _normalizar_hora_meta(meta)
    if not hora_obj:
        return False

    mensaje = str(meta.get("mensaje") or "¡Alarma programada correctamente!").strip()
    dias_str = _normalizar_dias_meta(meta)

    # Si hay días recurrentes, NO guardar fecha fija.
    if dias_str:
        fecha_obj = None
    else:
        fecha_obj = _normalizar_fecha_meta(meta)

    Alarma.objects.create(
        usuario=django_user,
        fecha=fecha_obj,
        hora=hora_obj,
        mensaje=mensaje,
        dias=dias_str,
        activa=True,
        entregada=False,
    )
    return True

#------pendientes------#
@login_required
def pendientes(request):
    """
    Detecta alarmas que deben sonar ahora (ventana tolerante),
    marca su disparo y envía notificación Web Push si hay suscripciones.
    """
    ahora = timezone.localtime()

    def _norm_dia(token):
        txt = unicodedata.normalize("NFKD", str(token or ""))
        txt = txt.encode("ascii", "ignore").decode("ascii").lower().strip()
        txt = re.sub(r"[^a-z]", "", txt)
        return txt[:3]

    def _aplica_hoy(alarma):
        if alarma.fecha and alarma.fecha != ahora.date():
            return False
        raw = (alarma.dias or "").strip()
        if not raw:
            return True

        hoy_tokens = {
            0: {"lun", "mon"},
            1: {"mar", "tue"},
            2: {"mie", "wed"},
            3: {"jue", "thu"},
            4: {"vie", "fri"},
            5: {"sab", "sat"},
            6: {"dom", "sun"},
        }[ahora.weekday()]
        dias = {_norm_dia(x) for x in re.split(r"[,;/\s]+", raw) if _norm_dia(x)}
        return bool(dias & hoy_tokens)

    # Tomamos alarmas candidatas del día y validamos por diferencia real en segundos.
    alarmas = (
        Alarma.objects
        .filter(usuario=request.user, activa=True)
        .filter(Q(fecha__isnull=True) | Q(fecha=ahora.date()))
        .order_by("hora")
    )

    data = []
    for a in alarmas:
        if not _aplica_hoy(a):
            continue

        # evita disparos duplicados recientes
        if a.disparada_at and (ahora - a.disparada_at).total_seconds() < 90:
            continue

        base_dt = timezone.make_aware(
    datetime.combine(ahora.date(), a.hora),
    timezone.get_current_timezone(),
)

# ✅ SOLO después de la hora (nunca antes)
        delta = (ahora - base_dt).total_seconds()
        if delta < 0 or delta > 40:
            continue

        # ✅ evita duplicados más fuertes
        if a.disparada_at and (ahora - a.disparada_at).total_seconds() < 300:
            continue
        # Margen mayor al polling para no perder la alarma por desfase de segundos.
        if abs((base_dt - ahora).total_seconds()) > 75:
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

        _enviar_webpush_a_usuario(request.user, payload)

    return JsonResponse({"ok": True, "alarmas": data})

#--------Marcar entregada (alarmas)----#
@login_required
@require_POST
@csrf_exempt
def marcar_entregada(request):
    _id = request.POST.get("id")
    try:
        a = Alarma.objects.get(id=_id, usuario=request.user)

        dias = (a.dias or "").strip()
        # Si tiene fecha específica y no es recurrente, es de una sola vez.
        if not dias and a.fecha:
            a.entregada = True
            a.activa = False
            logger.info(f"✅ Alarma única desactivada: #{a.id}")
        else:
            # Recurrente por días o diaria (sin fecha): sigue activa.
            a.entregada = False
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
        a = Alarma.objects.get(id=_id, usuario=request.user)
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

        # Validar mime simple (de la versión 1)
        content_type = (getattr(f, "content_type", "") or "").lower()
        if not content_type.startswith("image/"):
            return JsonResponse({"ok": False, "error": "Formato no válido."}, status=400)

        # (Opcional) Comprimir/redimensionar ANTES de guardar (de la versión 1)
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
def analizar_imagen_openai_bytes(image_bytes):
    """
    Analiza una imagen de medicamento desde memoria (bytes), sin guardar archivo.
    Devuelve:
    - nombre
    - para_que_sirve
    - confianza
    - texto bruto/debug
    """
    try:
        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")

        max_side = 1280
        w, h = img.size
        scale = min(max_side / float(max(w, h)), 1.0)
        if scale < 1.0:
            img = img.resize((int(w * scale), int(h * scale)), Image.LANCZOS)

        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=85, optimize=True)
        b64 = base64.b64encode(buf.getvalue()).decode()

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

        resp = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "Eres conciso y exacto."},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}}
                    ]
                }
            ],
            temperature=0.2,
        )

        texto = (resp.choices[0].message.content or "").strip()
        data = _extraer_json_seguro(texto)

        nombre = str(data.get("nombre", "")).strip()
        para_que_sirve = str(data.get("para_que_sirve", "")).strip()

        try:
            confianza = float(data.get("confianza", 0.0) or 0.0)
        except Exception:
            confianza = 0.0

        return nombre, para_que_sirve, texto

    except Exception as e:
        print(f"❌ ERROR en OpenAI (bytes): {e}")
        return "", "", 0.0, f"ERROR_OPENAI: {e}"

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
    hoy = timezone.localdate()
    alarmas = (
        Alarma.objects
        .filter(usuario=request.user, activa=True)
        .filter(Q(fecha__isnull=True) | Q(fecha__gte=hoy))
        .order_by('fecha', 'hora')
    )
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

#-------obtener alarmas del adulto vinculado (cuidador)-----#
@login_required
def obtener_alarmas_cuidador(request):
    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)
    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

    cuidador_id = mysql_user["id"]
    adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
    if not adulto_vinculado:
        return JsonResponse({"ok": True, "alarmas": []})

    # Obtener correo del adulto para mapear a usuario Django
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT correo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
            [adulto_vinculado["id"]],
        )
        r = cursor.fetchone()
    correo_adulto = (r[0] if r else "") or ""

    adulto_django = _django_user_from_mysql_adulto(adulto_vinculado["nombre"], correo_adulto)
    if not adulto_django:
        return JsonResponse({"ok": True, "alarmas": []})

    hoy = timezone.localdate()
    alarmas = (
        Alarma.objects
        .filter(usuario=adulto_django, activa=True)
        .filter(Q(fecha__isnull=True) | Q(fecha__gte=hoy))
        .order_by("fecha", "hora")
    )

    data = [
        {
            "id": a.id,
            "hora": a.hora.strftime("%H:%M"),
            "mensaje": a.mensaje,
            "dias": a.dias or "",
            "fecha": a.fecha.isoformat() if a.fecha else None,
            "activa": bool(a.activa),
        }
        for a in alarmas
    ]
    return JsonResponse({"ok": True, "alarmas": data})


#------helpers cuidador -> adulto-----#
def _cuidador_get_adulto_django(request):
    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)
    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return None, "Solo cuidadores."

    cuidador_id = mysql_user["id"]
    adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
    if not adulto_vinculado:
        return None, "No hay adulto vinculado."

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT correo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
            [adulto_vinculado["id"]],
        )
        r = cursor.fetchone()
    correo_adulto = (r[0] if r else "") or ""

    adulto_django = _django_user_from_mysql_adulto(adulto_vinculado["nombre"], correo_adulto)
    if not adulto_django:
        return None, "No se encontr? usuario Django del adulto."

    return adulto_django, None

def _cuidador_get_adulto_django_from_username(username):
    ident = (username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)
    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return None, "Solo cuidadores."

    cuidador_id = mysql_user["id"]
    adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
    if not adulto_vinculado:
        return None, "No hay adulto vinculado."

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT correo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
            [adulto_vinculado["id"]],
        )
        r = cursor.fetchone()
    correo_adulto = (r[0] if r else "") or ""

    adulto_django = _django_user_from_mysql_adulto(adulto_vinculado["nombre"], correo_adulto)
    if not adulto_django:
        return None, "No se encontro usuario Django del adulto."

    return adulto_django, None

#------crear alarma (cuidador)-----#
@login_required
@require_POST
@csrf_exempt

def crear_alarma_cuidador(request):
    adulto_django, err = _cuidador_get_adulto_django(request)
    if err:
        return JsonResponse({"ok": False, "error": err}, status=403)

    fecha_raw = request.POST.get("fecha")
    hora_raw = request.POST.get("hora")
    mensaje = (request.POST.get("mensaje") or "?Es hora de tu alarma!").strip()
    dias = (request.POST.get("dias") or "").strip()
    activa_raw = request.POST.get("activa")

    if not hora_raw:
        return JsonResponse({"ok": False, "error": "Hora requerida"}, status=400)

    hora = _parse_hora(hora_raw)
    if not hora:
        return JsonResponse({"ok": False, "error": "Hora inv?lida"}, status=400)

    fecha = _parse_fecha(fecha_raw) if fecha_raw else None
    activa = True if activa_raw is None else str(activa_raw).lower() in ("1", "true", "on", "si", "s?")

    try:
        alarma = Alarma.objects.create(
            usuario=adulto_django,
            fecha=fecha,
            hora=hora,
            mensaje=mensaje,
            dias=dias,
            activa=activa,
        )
        return JsonResponse({"ok": True, "id": alarma.id})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

#------editar alarma (cuidador)-----#
@login_required
@require_POST
@csrf_exempt

def editar_alarma_cuidador(request):
    adulto_django, err = _cuidador_get_adulto_django(request)
    if err:
        return JsonResponse({"ok": False, "error": err}, status=403)

    _id = request.POST.get("id")
    if not _id:
        return JsonResponse({"ok": False, "error": "ID requerido"}, status=400)

    hora_raw = request.POST.get("hora")
    mensaje = (request.POST.get("mensaje") or "").strip()
    fecha_raw = request.POST.get("fecha")
    dias = (request.POST.get("dias") or "").strip()
    activa_raw = request.POST.get("activa")

    if not hora_raw:
        return JsonResponse({"ok": False, "error": "Hora requerida"}, status=400)
    if not mensaje:
        return JsonResponse({"ok": False, "error": "Mensaje requerido"}, status=400)

    hora = _parse_hora(hora_raw)
    if not hora:
        return JsonResponse({"ok": False, "error": "Hora inv?lida"}, status=400)

    fecha = _parse_fecha(fecha_raw) if fecha_raw else None
    activa = True if activa_raw is None else str(activa_raw).lower() in ("1", "true", "on", "si", "s?")

    alarma = Alarma.objects.filter(id=_id, usuario=adulto_django).first()
    if not alarma:
        return JsonResponse({"ok": False, "error": "Alarma no encontrada"}, status=404)

    alarma.hora = hora
    alarma.mensaje = mensaje
    alarma.fecha = fecha
    alarma.dias = dias
    alarma.activa = activa
    alarma.save(update_fields=["hora", "mensaje", "fecha", "dias", "activa"])

    return JsonResponse({"ok": True})

#------eliminar alarma (cuidador)-----#
@login_required
@require_POST
@csrf_exempt

def eliminar_alarma_cuidador(request):
    adulto_django, err = _cuidador_get_adulto_django(request)
    if err:
        return JsonResponse({"ok": False, "error": err}, status=403)

    _id = request.POST.get("id")
    if not _id:
        return JsonResponse({"ok": False, "error": "ID requerido"}, status=400)

    alarma = Alarma.objects.filter(id=_id, usuario=adulto_django).first()
    if not alarma:
        return JsonResponse({"ok": False, "error": "Alarma no encontrada"}, status=404)

    alarma.delete()
    return JsonResponse({"ok": True})

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

        alarma = Alarma.objects.filter(id=_id, usuario=request.user).first()
        if not alarma:
            print("⚠️ No existe alarma con ese ID.")
            return JsonResponse({"ok": False, "error": "No existe"}, status=404)

        alarma.delete()
        print(f"✅ Alarma eliminada correctamente: ID {_id}")
        return JsonResponse({"ok": True})

    except Exception as e:
        print(f"❌ Error al eliminar alarma: {e}")
        return JsonResponse({"ok": False, "error": str(e)}, status=500)


@login_required
@require_POST
@csrf_exempt
def eliminar_todas_alarmas_ajax(request):
    try:
        # Borra todas las alarmas activas del usuario en Django (UI / scheduler actual)
        total_django = Alarma.objects.filter(usuario=request.user, activa=True).count()
        Alarma.objects.filter(usuario=request.user, activa=True).delete()

        # Mantiene consistencia con tabla MySQL de alarmas de receta
        usuario_id = _resolver_mysql_usuario_id(request)
        total_mysql = 0
        if usuario_id:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT COUNT(*)
                    FROM alarma
                    WHERE Usuario_id=%s AND Estado='pendiente'
                    """,
                    [usuario_id],
                )
                total_mysql = cursor.fetchone()[0] or 0
                cursor.execute(
                    """
                    UPDATE alarma
                    SET Estado='cancelada'
                    WHERE Usuario_id=%s AND Estado='pendiente'
                    """,
                    [usuario_id],
                )

        return JsonResponse(
            {
                "ok": True,
                "eliminadas": int(total_django),
                "canceladas_mysql": int(total_mysql),
            }
        )
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

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
            sub.usuario = request.user
            sub.p256dh = p256dh
            sub.auth = auth
            sub.save(update_fields=["usuario", "p256dh", "auth"])

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


@csrf_exempt
@login_required
@require_POST
def crear_emergencia(request):
    ok, resp = _require_premium_adulto(request)
    if not ok:
        return resp
    mysql_user = None
    usuario_id = _resolver_mysql_usuario_id(request)
    if usuario_id:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono "
                "FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
                [usuario_id],
            )
            row = cursor.fetchone()
            if row:
                mysql_user = {"id": row[0], "nombre": row[1], "tipo": row[2], "correo": row[3], "telefono": row[4]}
    if not mysql_user or mysql_user.get("tipo") != "adulto":
        return JsonResponse({"ok": False, "error": "Solo adultos pueden emitir SOS."}, status=403)

    adulto_id = mysql_user["id"]
    cuidador = _mysql_get_cuidador_por_adulto(adulto_id)
    if not cuidador:
        return JsonResponse({"ok": False, "error": "No hay cuidador vinculado."}, status=409)

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT id_emergencia FROM emergencia "
            "WHERE adulto_id=%s AND estado='enviada' AND creado_en >= (NOW() - INTERVAL 45 SECOND) "
            "ORDER BY id_emergencia DESC LIMIT 1",
            [adulto_id],
        )
        row_recent = cursor.fetchone()
        if row_recent:
            return JsonResponse(
                {"ok": True, "duplicada": True, "id_emergencia": int(row_recent[0])},
                status=200,
            )

        cursor.execute(
            "SELECT lat, lng FROM ubicacion_actual WHERE usuario_id=%s LIMIT 1",
            [adulto_id],
        )
        row_pos = cursor.fetchone()
        lat = float(row_pos[0]) if row_pos and row_pos[0] is not None else None
        lng = float(row_pos[1]) if row_pos and row_pos[1] is not None else None

        cursor.execute(
            "INSERT INTO emergencia (lat, lng, estado, creado_en, adulto_id, cuidador_id) "
            "VALUES (%s, %s, 'enviada', NOW(), %s, %s)",
            [lat, lng, adulto_id, cuidador["id"]],
        )
        emergencia_id = int(cursor.lastrowid)
    connection.commit()

    cuidador_django = _django_user_from_mysql_usuario(cuidador.get("nombre"), cuidador.get("correo"))
    payload = {
        "type": "EMERGENCIA",
        "kind": "emergencia",
        "title": "SOS EVA",
        "body": f"{mysql_user.get('nombre') or 'Adulto'} solicitó ayuda urgente.",
        "tag": f"emergencia-{emergencia_id}",
        "url": "/interfaz-cuidador/",
        "id_emergencia": emergencia_id,
        "adulto_id": adulto_id,
        "adulto_nombre": mysql_user.get("nombre") or "",
        "lat": lat,
        "lng": lng,
    }
    push_enviadas = _enviar_webpush_a_usuario(cuidador_django, payload)

    return JsonResponse(
        {
            "ok": True,
            "id_emergencia": emergencia_id,
            "push_enviadas": int(push_enviadas),
            "cuidador": cuidador.get("nombre"),
        }
    )


@login_required
def cuidador_emergencias_pendientes(request):
    mysql_user = None
    usuario_id = _resolver_mysql_usuario_id(request)
    if usuario_id:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono "
                "FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
                [usuario_id],
            )
            row = cursor.fetchone()
            if row:
                mysql_user = {"id": row[0], "nombre": row[1], "tipo": row[2], "correo": row[3], "telefono": row[4]}
    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

    cuidador_id = mysql_user["id"]
    adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
    if not adulto_vinculado:
        return JsonResponse({"ok": True, "emergencias": []})

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT id_emergencia, lat, lng, estado, creado_en, atendido_en "
            "FROM emergencia "
            "WHERE cuidador_id=%s AND adulto_id=%s AND estado IN ('enviada','vista') "
            "ORDER BY creado_en DESC LIMIT 20",
            [cuidador_id, adulto_vinculado["id"]],
        )
        rows = cursor.fetchall()

    emergencias = []
    for r in rows:
        emergencias.append(
            {
                "id_emergencia": int(r[0]),
                "lat": float(r[1]) if r[1] is not None else None,
                "lng": float(r[2]) if r[2] is not None else None,
                "estado": r[3],
                "creado_en": r[4].isoformat() if r[4] else None,
                "atendido_en": r[5].isoformat() if r[5] else None,
                "adulto": adulto_vinculado,
            }
        )

    return JsonResponse({"ok": True, "emergencias": emergencias})


@csrf_exempt
@login_required
@require_POST
def actualizar_estado_emergencia(request):
    mysql_user = None
    usuario_id = _resolver_mysql_usuario_id(request)
    if usuario_id:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono "
                "FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
                [usuario_id],
            )
            row = cursor.fetchone()
            if row:
                mysql_user = {"id": row[0], "nombre": row[1], "tipo": row[2], "correo": row[3], "telefono": row[4]}
    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

    payload = {}
    try:
        payload = json.loads((request.body or b"{}").decode("utf-8"))
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    emergencia_id = payload.get("id_emergencia") or request.POST.get("id_emergencia")
    nuevo_estado = (payload.get("estado") or request.POST.get("estado") or "").strip().lower()

    try:
        emergencia_id = int(emergencia_id)
    except Exception:
        return JsonResponse({"ok": False, "error": "id_emergencia inválido."}, status=400)

    if nuevo_estado not in ("vista", "atendida", "cerrada"):
        return JsonResponse({"ok": False, "error": "Estado inválido."}, status=400)

    cuidador_id = mysql_user["id"]
    with connection.cursor() as cursor:
        if nuevo_estado in ("atendida", "cerrada"):
            cursor.execute(
                "UPDATE emergencia SET estado=%s, atendido_en=NOW() "
                "WHERE id_emergencia=%s AND cuidador_id=%s",
                [nuevo_estado, emergencia_id, cuidador_id],
            )
        else:
            cursor.execute(
                "UPDATE emergencia SET estado=%s "
                "WHERE id_emergencia=%s AND cuidador_id=%s",
                [nuevo_estado, emergencia_id, cuidador_id],
            )
        updated = int(cursor.rowcount or 0)
    connection.commit()

    if updated <= 0:
        return JsonResponse({"ok": False, "error": "Emergencia no encontrada."}, status=404)

    return JsonResponse({"ok": True, "id_emergencia": emergencia_id, "estado": nuevo_estado})

#---------UBICACION---------#
def _mysql_get_compartir_ubicacion(usuario_id: int) -> bool:
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT compartir_ubicacion FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
            [usuario_id],
        )
        row = cursor.fetchone()
    return bool(row[0]) if row else False


def _mysql_set_compartir_ubicacion(usuario_id: int, activo: bool):
    with connection.cursor() as cursor:
        cursor.execute(
            "UPDATE Usuarios SET compartir_ubicacion=%s WHERE Id_Usuario=%s",
            [1 if activo else 0, usuario_id],
        )
    connection.commit()

@login_required
def ubicacion_estado(request):
    ok, resp = _require_premium_adulto(request)
    if not ok:
        return resp
    usuario_id = _resolver_mysql_usuario_id(request)
    if not usuario_id:
        return JsonResponse({"ok": False, "error": "No pude resolver tu usuario MySQL."}, status=400)

    activo = _mysql_get_compartir_ubicacion(usuario_id)
    return JsonResponse({
        "ok": True,
        "compartir_ubicacion": activo,
        "mapbox_token": getattr(settings, "MAPBOX_TOKEN_PUBLIC", ""),
    })

@login_required
@require_POST
def ubicacion_toggle(request):
    ok, resp = _require_premium_adulto(request)
    if not ok:
        return resp
    usuario_id = _resolver_mysql_usuario_id(request)
    if not usuario_id:
        return JsonResponse({"ok": False, "error": "No pude resolver tu usuario MySQL."}, status=400)

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except Exception:
        body = {}

    # ✅ Soporta: { force: "on" | "off" }  (tu nuevo JS)
    force = (body.get("force") or "").strip().lower()
    if force in ("on", "true", "1"):
        activar = True
    elif force in ("off", "false", "0"):
        activar = False
    else:
        # ✅ Soporta: { activar: true/false }  (tu versión anterior)
        if "activar" in body:
            activar = bool(body.get("activar"))
        else:
            # ✅ Si no mandan nada, hacemos toggle real
            activar = not _mysql_get_compartir_ubicacion(usuario_id)

    _mysql_set_compartir_ubicacion(usuario_id, activar)

    return JsonResponse({"ok": True, "compartir_ubicacion": activar})

@login_required
@require_POST
def ubicacion_ping(request):
    ok, resp = _require_premium_adulto(request)
    if not ok:
        return resp
    usuario_id = _resolver_mysql_usuario_id(request)
    if not usuario_id:
        return JsonResponse({"ok": False, "error": "No pude resolver tu usuario MySQL."}, status=400)

    if not _mysql_get_compartir_ubicacion(usuario_id):
        return JsonResponse({"ok": False, "error": "Ubicación desactivada"}, status=403)

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
        lat = float(body.get("lat"))
        lng = float(body.get("lng"))
        precision = body.get("accuracy")
        precision = float(precision) if precision is not None else None
    except Exception:
        return JsonResponse({"ok": False, "error": "Datos inválidos (lat/lng)."}, status=400)

    # 1) siempre actualiza ubicacion_actual (tu comportamiento actual)
    with connection.cursor() as cursor:
        cursor.execute("""
            INSERT INTO ubicacion_actual (usuario_id, lat, lng, precision_m)
            VALUES (%s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
              lat = VALUES(lat),
              lng = VALUES(lng),
              precision_m = VALUES(precision_m),
              actualizado_en = CURRENT_TIMESTAMP
        """, [usuario_id, lat, lng, precision])

        try:
            cursor.execute("""
                UPDATE Usuarios SET ubicacion_actualizada_en=CURRENT_TIMESTAMP
                WHERE Id_Usuario=%s
            """, [usuario_id])
        except Exception:
            pass

    GUARDAR_CADA_SEG = 180
    GUARDAR_SI_MOVIO_M = 30

    ultimo = _mysql_get_ultimo_punto_historial(usuario_id)
    debe_guardar = False

    if not ultimo:
        debe_guardar = True
    else:
        # tiempo
        try:
            diff = (timezone.now() - ultimo["creado_en"]).total_seconds()
        except Exception:
            diff = 999999
        if diff >= GUARDAR_CADA_SEG:
            debe_guardar = True
        else:
            # distancia
            try:
                dist_m = _haversine_m(ultimo["lat"], ultimo["lng"], lat, lng)
                if dist_m >= GUARDAR_SI_MOVIO_M:
                    debe_guardar = True
            except Exception:
                pass

    if debe_guardar:
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO ubicacion_historial (usuario_id, lat, lng, precision_m)
                VALUES (%s, %s, %s, %s)
            """, [usuario_id, lat, lng, precision])
        # (no pasa nada si guardas 1 punto cada 3 min aprox)

    connection.commit()
    return JsonResponse({"ok": True, "guardado_historial": bool(debe_guardar)})

@login_required
def cuidador_ultima_ubicacion(request):
    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)
    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

    cuidador_id = mysql_user["id"]
    adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
    if not adulto_vinculado:
        return JsonResponse({
            "ok": True,
            "adulto": None,
            "compartir_ubicacion": False,
            "sin_senal": True,
            "ultima": None
        })

    adulto_id = adulto_vinculado["id"]
    compartir = _mysql_get_compartir_ubicacion(adulto_id)

    # Si desactivó, no regresamos coordenadas (para privacidad)
    if not compartir:
        return JsonResponse({
            "ok": True,
            "adulto": adulto_vinculado,
            "compartir_ubicacion": False,
            "sin_senal": False,
            "ultima": None
        })

    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT lat, lng, precision_m, actualizado_en,
                   TIMESTAMPDIFF(SECOND, actualizado_en, NOW()) AS diff_seg
            FROM ubicacion_actual
            WHERE usuario_id=%s
            LIMIT 1
        """, [adulto_id])
        row = cursor.fetchone()

    if not row:
        return JsonResponse({
            "ok": True,
            "adulto": adulto_vinculado,
            "compartir_ubicacion": True,
            "sin_senal": True,
            "ultima": None
        })

    lat, lng, precision, actualizado_en, diff_seg = row

    # “sin señal” si pasaron más de 3 min desde el último ping (según MySQL)
    try:
        sin_senal = (diff_seg is None) or (int(diff_seg) > 180)  # 180s = 3 min
    except Exception:
        sin_senal = False

    return JsonResponse({
        "ok": True,
        "adulto": adulto_vinculado,
        "compartir_ubicacion": True,
        "sin_senal": sin_senal,
        "ultima": {
            "lat": float(lat),
            "lng": float(lng),
            "accuracy": float(precision) if precision is not None else None,
            "timestamp": actualizado_en.isoformat() if actualizado_en else None
        }
    })

def _haversine_m(lat1, lng1, lat2, lng2):
    R = 6371000.0
    phi1 = math.radians(lat1); phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1-a))

def _mysql_get_ultimo_punto_historial(usuario_id: int):
    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT lat, lng, creado_en
            FROM ubicacion_historial
            WHERE usuario_id=%s
            ORDER BY creado_en DESC
            LIMIT 1
        """, [usuario_id])
        row = cursor.fetchone()
    if not row:
        return None
    return {"lat": float(row[0]), "lng": float(row[1]), "creado_en": row[2]}

@login_required
def cuidador_historial_ubicacion(request):
    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)
    if not mysql_user or mysql_user.get("tipo") != "cuidador":
        return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

    cuidador_id = mysql_user["id"]
    adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
    if not adulto_vinculado:
        return JsonResponse({"ok": True, "adulto": None, "puntos": []})

    adulto_id = adulto_vinculado["id"]

    if not _mysql_get_compartir_ubicacion(adulto_id):
        return JsonResponse({"ok": True, "adulto": adulto_vinculado, "compartir_ubicacion": False, "puntos": []})

    horas = 24  # 🔒 fijo siempre

    limite = request.GET.get("limite")
    try:
        limite = int(limite) if limite else 500
        limite = max(50, min(limite, 2000))
    except Exception:
        limite = 500

    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT lat, lng, precision_m, creado_en
            FROM ubicacion_historial
            WHERE usuario_id=%s
              AND creado_en >= (NOW() - INTERVAL %s HOUR)
            ORDER BY creado_en ASC
            LIMIT %s
        """, [adulto_id, horas, limite])
        rows = cursor.fetchall()

    puntos = [
        {
            "lat": float(r[0]),
            "lng": float(r[1]),
            "accuracy": float(r[2]) if r[2] is not None else None,
            "timestamp": r[3].isoformat() if r[3] else None,
        }
        for r in rows
    ]

    return JsonResponse({
        "ok": True,
        "adulto": adulto_vinculado,
        "compartir_ubicacion": True,
        "puntos": puntos
    })


def _chat_resolver_contexto(request):
    """
    Retorna (adulto_id, cuidador_id, emisor_id, tipo_usuario) basándose en tu vínculo activo.
    Usa tu tabla Usuarios + adulto_cuidador.
    """
    ident = (request.user.username or "").strip()
    mysql_user = verificar_usuario_en_bd(ident)  # tú ya la tienes
    if not mysql_user:
        nombre = (request.user.first_name or "").strip()
        mysql_user = verificar_usuario_en_bd(nombre)

    if not mysql_user:
        return None, None, None, "No pude resolver tu usuario MySQL."

    emisor_id = int(mysql_user["id"])
    tipo = mysql_user.get("tipo")

    if tipo == "adulto":
        adulto_id = emisor_id
        cuidador = _mysql_get_cuidador_por_adulto(adulto_id)  # tú ya la tienes
        if not cuidador:
            return None, None, None, "No hay cuidador vinculado."
        cuidador_id = int(cuidador["id"])
        return adulto_id, cuidador_id, emisor_id, None

    if tipo == "cuidador":
        cuidador_id = emisor_id
        adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id) # tú ya la tienes
        if not adulto_vinculado:
            return None, None, None, "No hay adulto vinculado."
        adulto_id = int(adulto_vinculado["id"])
        return adulto_id, cuidador_id, emisor_id, None

    return None, None, None, "Tipo de usuario inválido para chat."

def _mysql_get_usuario_por_identificador_casefold(identificador: str):
    ident = (identificador or "").strip()
    if not ident:
        return None

    by_ident = _mysql_get_usuario_por_identificador(ident)
    if by_ident:
        return {
            "id": by_ident.get("id"),
            "nombre": by_ident.get("nombre_completo") or "",
            "tipo": by_ident.get("tipo") or "",
            "correo": by_ident.get("correo") or "",
            "telefono": by_ident.get("telefono") or "",
            "activo": True,
        }

    by_verify = verificar_usuario_en_bd(ident)
    if by_verify:
        return by_verify

    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT Id_Usuario, Nombre_Completo, Tipo, correo, Telefono, activo "
            "FROM Usuarios WHERE LOWER(Nombre_Completo)=LOWER(%s) LIMIT 1",
            [ident],
        )
        row = cursor.fetchone()

    if not row:
        return None

    return {
        "id": row[0],
        "nombre": row[1],
        "tipo": row[2],
        "correo": row[3],
        "telefono": row[4],
        "activo": bool(row[5]),
    }


def _require_premium_chat_mobile(mysql_user):
    if not mysql_user:
        return False, JsonResponse({"ok": False, "error": "No pude resolver tu usuario MySQL."}, status=400)

    usuario_id = int(mysql_user["id"])
    tipo = (mysql_user.get("tipo") or "").strip().lower()

    if tipo == "adulto":
        if not _mysql_adulto_premium_activo(usuario_id):
            return False, JsonResponse(
                {"ok": False, "error": "Chat es premium. Vinculate con tu cuidador para activarlo."},
                status=403,
            )
        return True, None

    if tipo == "cuidador":
        if not _mysql_cuidador_premium_activo(usuario_id):
            return False, JsonResponse(
                {"ok": False, "error": "Chat es premium. Activa tu membresia para usarlo."},
                status=403,
            )
        return True, None

    return False, JsonResponse({"ok": False, "error": "Tipo invalido para chat."}, status=403)


def _chat_resolver_contexto_mobile(username):
    mysql_user = _mysql_get_usuario_por_identificador_casefold(username)
    if not mysql_user:
        return None, None, None, None, "No pude resolver tu usuario MySQL."

    emisor_id = int(mysql_user["id"])
    tipo = (mysql_user.get("tipo") or "").strip().lower()

    if tipo == "adulto":
        adulto_id = emisor_id
        cuidador = _mysql_get_cuidador_por_adulto(adulto_id)
        if not cuidador:
            return None, None, None, mysql_user, "No hay cuidador vinculado."
        cuidador_id = int(cuidador["id"])
        return adulto_id, cuidador_id, emisor_id, mysql_user, None

    if tipo == "cuidador":
        cuidador_id = emisor_id
        adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
        if not adulto_vinculado:
            return None, None, None, mysql_user, "No hay adulto vinculado."
        adulto_id = int(adulto_vinculado["id"])
        return adulto_id, cuidador_id, emisor_id, mysql_user, None

    return None, None, None, mysql_user, "Tipo de usuario invalido para chat."
def _mysql_get_usuario_basico(usuario_id: int):
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT Id_Usuario, Nombre_Completo, correo, Tipo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
            [usuario_id],
        )
        row = cursor.fetchone()
    if not row:
        return None
    return {"id": int(row[0]), "nombre": row[1] or "", "correo": row[2] or "", "tipo": row[3] or ""}

@login_required
@require_GET
def chat_get_mensajes(request):
    ok, resp = _require_premium_chat(request)
    if not ok:
        return resp
    adulto_id, cuidador_id, emisor_id, err = _chat_resolver_contexto(request)
    if err:
        return JsonResponse({"ok": False, "error": err}, status=403)

    after_id = request.GET.get("after_id") or "0"
    limit = request.GET.get("limit") or "50"
    try:
        after_id = int(after_id)
    except Exception:
        after_id = 0
    try:
        limit = int(limit)
        limit = max(1, min(limit, 200))
    except Exception:
        limit = 50

    with connection.cursor() as cursor:
        cursor.execute("""
            SELECT id, mensaje, creado_en, emisor_id, escuchado, tipo
            FROM chat_voz
            WHERE adulto_id=%s AND cuidador_id=%s AND id > %s
            ORDER BY id ASC
            LIMIT %s
        """, [adulto_id, cuidador_id, after_id, limit])
        rows = cursor.fetchall()

    mensajes = []
    last_id = after_id
    for r in rows:
        mid = int(r[0])
        last_id = max(last_id, mid)
        mensajes.append({
            "id": mid,
            "mensaje": r[1] or "",
            "creado_en": r[2].isoformat() if r[2] else None,
            "emisor_id": int(r[3]),
            "escuchado": bool(r[4]),
            "tipo": r[5] or "texto",
        })

    return JsonResponse({
        "ok": True,
        "adulto_id": adulto_id,
        "cuidador_id": cuidador_id,
        "emisor_id": emisor_id,
        "mensajes": mensajes,
        "last_id": last_id,
    })

@login_required
@require_POST
def chat_post_enviar(request):
    ok, resp = _require_premium_chat(request)
    if not ok:
        return resp
    adulto_id, cuidador_id, emisor_id, err = _chat_resolver_contexto(request)
    if err:
        return JsonResponse({"ok": False, "error": err}, status=403)

    # soporta form o JSON
    texto = (request.POST.get("mensaje") or "").strip()
    if not texto:
        try:
            body = json.loads((request.body or b"{}").decode("utf-8"))
            texto = (body.get("mensaje") or "").strip()
        except Exception:
            texto = ""

    if not texto:
        return JsonResponse({"ok": False, "error": "Mensaje vacío."}, status=400)

    with connection.cursor() as cursor:
        cursor.execute("""
            INSERT INTO chat_voz (mensaje, tipo, escuchado, adulto_id, cuidador_id, emisor_id)
            VALUES (%s, 'texto', 0, %s, %s, %s)
        """, [texto, adulto_id, cuidador_id, emisor_id])
        new_id = int(cursor.lastrowid)

        cursor.execute("SELECT creado_en FROM chat_voz WHERE id=%s LIMIT 1", [new_id])
        row = cursor.fetchone()

    connection.commit()

    # Push al destinatario de la conversación (si tiene suscripciones activas)
    receptor_id = cuidador_id if int(emisor_id) == int(adulto_id) else adulto_id
    receptor = _mysql_get_usuario_basico(receptor_id)
    receptor_django = None
    if receptor:
        receptor_django = _django_user_from_mysql_usuario(receptor.get("nombre") or "", receptor.get("correo") or "")

    if receptor_django:
        nombre_emisor = (request.user.first_name or request.user.username or "EVA").strip()
        texto_corto = texto if len(texto) <= 120 else (texto[:117] + "...")
        url_destino = "/interfaz-cuidador/" if int(receptor_id) == int(cuidador_id) else "/inicio/"
        payload = {
            "kind": "chat",
            "title": f"Nuevo mensaje de {nombre_emisor}",
            "body": texto_corto,
            "tag": f"chat-{adulto_id}-{cuidador_id}",
            "url": url_destino,
            "id": new_id,
        }
        _enviar_webpush_a_usuario(receptor_django, payload)

    return JsonResponse({
        "ok": True,
        "id": new_id,
        "creado_en": row[0].isoformat() if row and row[0] else None,
    })

@login_required
@require_POST
def chat_post_marcar_visto(request):
    ok, resp = _require_premium_chat(request)
    if not ok:
        return resp
    adulto_id, cuidador_id, emisor_id, err = _chat_resolver_contexto(request)
    if err:
        return JsonResponse({"ok": False, "error": err}, status=403)

    up_to_id = None
    try:
        up_to_id = request.POST.get("up_to_id")
        if up_to_id is None:
            body = json.loads((request.body or b"{}").decode("utf-8"))
            up_to_id = body.get("up_to_id")
        up_to_id = int(up_to_id) if up_to_id is not None else None
    except Exception:
        up_to_id = None

    params = [adulto_id, cuidador_id, emisor_id]
    extra = ""
    if up_to_id is not None:
        extra = " AND id <= %s "
        params.append(up_to_id)

    with connection.cursor() as cursor:
        cursor.execute(f"""
            UPDATE chat_voz
            SET escuchado=1
            WHERE adulto_id=%s AND cuidador_id=%s
              AND emisor_id <> %s
              AND escuchado=0
              {extra}
        """, params)
        updated = int(cursor.rowcount or 0)

    connection.commit()
    return JsonResponse({"ok": True, "updated": updated})

@csrf_exempt
def api_v1_chat_mensajes(request):
    try:
        if request.method != "GET":
            return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

        username = (request.GET.get("username") or "").strip()
        adulto_id, cuidador_id, emisor_id, mysql_user, err = _chat_resolver_contexto_mobile(username)
        if err:
            return JsonResponse({"ok": False, "error": err}, status=403)

        ok, resp = _require_premium_chat_mobile(mysql_user)
        if not ok:
            return resp

        after_id = request.GET.get("after_id") or "0"
        limit = request.GET.get("limit") or "50"
        try:
            after_id = int(after_id)
        except Exception:
            after_id = 0
        try:
            limit = int(limit)
            limit = max(1, min(limit, 200))
        except Exception:
            limit = 50

        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT id, mensaje, creado_en, emisor_id, escuchado, tipo
                FROM chat_voz
                WHERE adulto_id=%s AND cuidador_id=%s AND id > %s
                ORDER BY id ASC
                LIMIT %s
            """, [adulto_id, cuidador_id, after_id, limit])
            rows = cursor.fetchall()

        mensajes = []
        last_id = after_id
        for r in rows:
            mid = int(r[0])
            last_id = max(last_id, mid)
            mensajes.append({
                "id": mid,
                "mensaje": r[1] or "",
                "creado_en": r[2].isoformat() if r[2] else None,
                "emisor_id": int(r[3]),
                "escuchado": bool(r[4]),
                "tipo": r[5] or "texto",
            })

        return JsonResponse({
            "ok": True,
            "adulto_id": adulto_id,
            "cuidador_id": cuidador_id,
            "emisor_id": emisor_id,
            "tipo_usuario": (mysql_user.get("tipo") or "").strip().lower(),
            "mensajes": mensajes,
            "last_id": last_id,
        })
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)


@csrf_exempt
def api_v1_chat_enviar(request):
    try:
        if request.method != "POST":
            return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

        body = _json_body(request)
        username = (body.get("username") or "").strip()
        texto = (body.get("mensaje") or "").strip()
        tipo_mensaje = (body.get("tipo") or "texto").strip().lower()
        if tipo_mensaje == "voz":
            tipo_mensaje = "audio"
        if tipo_mensaje not in ("texto", "audio"):
            tipo_mensaje = "texto"

        adulto_id, cuidador_id, emisor_id, mysql_user, err = _chat_resolver_contexto_mobile(username)
        if err:
            return JsonResponse({"ok": False, "error": err}, status=403)

        ok, resp = _require_premium_chat_mobile(mysql_user)
        if not ok:
            return resp

        if not texto:
            return JsonResponse({"ok": False, "error": "Mensaje vacio."}, status=400)

        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO chat_voz (mensaje, tipo, escuchado, adulto_id, cuidador_id, emisor_id)
                VALUES (%s, %s, 0, %s, %s, %s)
            """, [texto, tipo_mensaje, adulto_id, cuidador_id, emisor_id])
            new_id = int(cursor.lastrowid)

            cursor.execute("SELECT creado_en FROM chat_voz WHERE id=%s LIMIT 1", [new_id])
            row = cursor.fetchone()

        connection.commit()

        receptor_id = cuidador_id if int(emisor_id) == int(adulto_id) else adulto_id
        receptor = _mysql_get_usuario_basico(receptor_id)
        receptor_django = None
        if receptor:
            receptor_django = _django_user_from_mysql_usuario(receptor.get("nombre") or "", receptor.get("correo") or "")

        if receptor_django:
            nombre_emisor = (mysql_user.get("nombre") or username or "EVA").strip()
            texto_corto = texto if len(texto) <= 120 else (texto[:117] + "...")
            url_destino = "/interfaz-cuidador/" if int(receptor_id) == int(cuidador_id) else "/inicio/"
            payload = {
                "kind": "chat",
                "title": f"Nuevo mensaje de {nombre_emisor}",
                "body": texto_corto,
                "tag": f"chat-{adulto_id}-{cuidador_id}",
                "url": url_destino,
                "id": new_id,
            }
            _enviar_webpush_a_usuario(receptor_django, payload)

        return JsonResponse({
            "ok": True,
            "id": new_id,
            "creado_en": row[0].isoformat() if row and row[0] else None,
        })
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)


@csrf_exempt
def api_v1_chat_marcar_visto(request):
    try:
        if request.method != "POST":
            return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

        body = _json_body(request)
        username = (body.get("username") or "").strip()

        adulto_id, cuidador_id, emisor_id, mysql_user, err = _chat_resolver_contexto_mobile(username)
        if err:
            return JsonResponse({"ok": False, "error": err}, status=403)

        ok, resp = _require_premium_chat_mobile(mysql_user)
        if not ok:
            return resp

        up_to_id = body.get("up_to_id")
        try:
            up_to_id = int(up_to_id) if up_to_id is not None else None
        except Exception:
            up_to_id = None

        params = [adulto_id, cuidador_id, emisor_id]
        extra = ""
        if up_to_id is not None:
            extra = " AND id <= %s "
            params.append(up_to_id)

        with connection.cursor() as cursor:
            cursor.execute(f"""
                UPDATE chat_voz
                SET escuchado=1
                WHERE adulto_id=%s AND cuidador_id=%s
                  AND emisor_id <> %s
                  AND escuchado=0
                  {extra}
            """, params)
            updated = int(cursor.rowcount or 0)

        connection.commit()
        return JsonResponse({"ok": True, "updated": updated})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)
#-----Vinculacion 1 a 1 -----
def _mysql_get_unico_vinculo_cuidador(cuidador_id: int):
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT a.Adulto_id, u.Nombre_Completo "
            "FROM adulto_cuidador a "
            "JOIN Usuarios u ON u.Id_Usuario=a.Adulto_id "
            "WHERE a.Cuidador_id=%s AND a.Activo=1 "
            "ORDER BY a.fecha_asignacion DESC LIMIT 1",
            [cuidador_id],
        )
        row = cursor.fetchone()
    if not row:
        return None
    return {"id": row[0], "nombre": row[1]}

def _mysql_crear_vinculo_unico(cuidador_id: int, adulto_id: int, codigo: str):
    ya = _mysql_get_unico_vinculo_cuidador(cuidador_id)
    if ya:
        raise ValueError("YA_VINCULADO")

    existente = _mysql_get_vinculo_por_adulto(adulto_id)
    if existente and int(existente["cuidador_id"]) != int(cuidador_id):
        raise ValueError("ADULTO_CON_OTRO_CUIDADOR")

    with connection.cursor() as cursor:
        cursor.execute(
            "INSERT INTO adulto_cuidador (Codigo_unico, Activo, Adulto_id, Cuidador_id, fecha_asignacion) "
            "VALUES (%s, 1, %s, %s, NOW())",
            [codigo, adulto_id, cuidador_id],
        )
    connection.commit()

def _mysql_get_cuidador_por_adulto(adulto_id: int):
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT a.Cuidador_id, u.Nombre_Completo, u.correo "
            "FROM adulto_cuidador a "
            "JOIN Usuarios u ON u.Id_Usuario=a.Cuidador_id "
            "WHERE a.Adulto_id=%s AND a.Activo=1 "
            "ORDER BY a.fecha_asignacion DESC LIMIT 1",
            [adulto_id],
        )
        row = cursor.fetchone()
    if not row:
        return None
    return {"id": row[0], "nombre": row[1], "correo": row[2]}

#-------Bloqueo premium---------#
def _require_premium_adulto(request):
    usuario_id = _resolver_mysql_usuario_id(request)
    if not usuario_id:
        return False, JsonResponse({"ok": False, "error": "No pude resolver tu usuario MySQL."}, status=400)

    mysql_user = None
    with connection.cursor() as cursor:
        cursor.execute("SELECT Tipo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1", [usuario_id])
        row = cursor.fetchone()
        if row:
            mysql_user = {"tipo": row[0]}

    if not mysql_user or mysql_user.get("tipo") != "adulto":
        return False, JsonResponse({"ok": False, "error": "Solo adultos."}, status=403)

    if not _mysql_adulto_premium_activo(int(usuario_id)):
        return False, JsonResponse({"ok": False, "error": "Función premium. Vincúlate con tu cuidador para activarla."}, status=403)

    return True, None

def _require_premium_chat(request):
    """
    Chat premium:
    - Si eres adulto: debes estar vinculado a cuidador premium.
    - Si eres cuidador: debes tener membresía activa.
    """
    usuario_id = _resolver_mysql_usuario_id(request)
    if not usuario_id:
        return False, JsonResponse({"ok": False, "error": "No pude resolver tu usuario MySQL."}, status=400)

    # Tipo en MySQL
    with connection.cursor() as cursor:
        cursor.execute("SELECT Tipo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1", [usuario_id])
        row = cursor.fetchone()
    tipo = (row[0] if row else None)

    if tipo == "adulto":
        if not _mysql_adulto_premium_activo(int(usuario_id)):
            return False, JsonResponse(
                {"ok": False, "error": "Chat es premium. Vincúlate con tu cuidador para activarlo."},
                status=403
            )
        return True, None

    if tipo == "cuidador":
        if not _mysql_cuidador_premium_activo(int(usuario_id)):
            return False, JsonResponse(
                {"ok": False, "error": "Chat es premium. Activa tu membresía para usarlo."},
                status=403
            )
        return True, None

    return False, JsonResponse({"ok": False, "error": "Tipo inválido para chat."}, status=403)

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
        return JsonResponse(
            {"ok": False, "error": "Faltan campos (correo/username, password)."},
            status=400
        )

    mysql_user = _mysql_get_usuario_por_correo(correo)
    if not mysql_user:
        return JsonResponse({"ok": False, "error": "Usuario no encontrado."}, status=404)

    # si quieres validar activo desde MySQL, agrega activo al helper
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT activo FROM Usuarios WHERE correo=%s LIMIT 1",
            [correo]
        )
        row = cursor.fetchone()
        if row and not bool(row[0]):
            return JsonResponse(
                {"ok": False, "error": "Tu cuenta está desactivada."},
                status=403
            )

    user_auth = authenticate(request, username=correo, password=password)
    if user_auth is None:
        return JsonResponse({"ok": False, "error": "Credenciales incorrectas."}, status=401)

    auth_login(request, user_auth)
    registrar_login_en_db(correo, request)

    return JsonResponse({
        "ok": True,
        "user": {
            "username": correo,
            "nombre_completo": mysql_user.get("nombre_completo"),
            "tipo": mysql_user.get("tipo"),
            "correo": mysql_user.get("correo"),
            "telefono": mysql_user.get("telefono"),
        }
    })

@csrf_exempt
def api_v1_login_nombre(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)

    data = _json_body(request)
    nombre_original = (data.get("username") or "").strip()
    password = data.get("password") or ""

    if not nombre_original or not password:
        return JsonResponse({"ok": False, "error": "Escribe tu nombre y tu contraseña."}, status=400)

    username = nombre_original.lower()
    usuario_mysql = verificar_usuario_en_bd(nombre_original)

    if usuario_mysql:
        if not usuario_mysql.get("activo", True):
            return JsonResponse({"ok": False, "error": "Tu cuenta está desactivada."}, status=403)

        user = User.objects.filter(username=username).first()

        if user is None:
            user = User.objects.create_user(
                username=username,
                password=password,
                first_name=usuario_mysql['nombre']
            )

        user_auth = authenticate(request, username=username, password=password)
        if user_auth is None:
            return JsonResponse({"ok": False, "error": "Contraseña incorrecta."}, status=401)

        auth_login(request, user_auth)
        registrar_login_en_db(username, request)

        tipo_usuario = (usuario_mysql.get('tipo') or '').strip().lower()

        return JsonResponse({
            "ok": True,
            "user": {
                "username": username,
                "nombre_completo": usuario_mysql.get("nombre"),
                "tipo": tipo_usuario,
                "correo": usuario_mysql.get("correo"),
                "telefono": usuario_mysql.get("telefono"),
            }
        })

    user = User.objects.filter(username=username).first()

    if user is None:
        user = User.objects.create_user(
            username=username,
            password=password,
            first_name=nombre_original
        )
        adulto_id = registrar_usuario_en_db(nombre_original, password, "adulto")
        if adulto_id is None:
            user.delete()
            return JsonResponse(
                {"ok": False, "error": "Error al registrar el usuario en la base de datos."},
                status=500
            )

        auth_login(request, user)
        registrar_login_en_db(nombre_original, request)

        return JsonResponse({
            "ok": True,
            "user": {
                "username": username,
                "nombre_completo": nombre_original,
                "tipo": "adulto",
            }
        })

    user_auth = authenticate(request, username=username, password=password)
    if user_auth is None:
        return JsonResponse({"ok": False, "error": "Contraseña incorrecta."}, status=401)

    auth_login(request, user_auth)
    registrar_login_en_db(nombre_original, request)

    return JsonResponse({
        "ok": True,
        "user": {
            "username": username,
            "nombre_completo": user.first_name or nombre_original,
            "tipo": "adulto",
        }
    })

@csrf_exempt
def api_v1_register_cuidador(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)

    data = _json_body(request)
    nombre_completo = (data.get("nombre_completo") or "").strip()
    password = data.get("password") or ""
    correo = (data.get("correo") or "").strip().lower()
    telefono = (data.get("telefono") or "").strip()
    pago_completado = bool(data.get("pago_completado"))

    if not nombre_completo or not password or not correo or not telefono:
        return JsonResponse({
            "ok": False,
            "error": "Faltan campos (nombre_completo, correo, telefono, password)."
        }, status=400)

    if not pago_completado:
        return JsonResponse({
            "ok": False,
            "error": "Debes completar el pago para registrarte."
        }, status=400)

    if _mysql_get_usuario_por_correo(correo):
        return JsonResponse({"ok": False, "error": "Ese correo ya está registrado."}, status=409)

    if User.objects.filter(username=correo).exists():
        return JsonResponse({"ok": False, "error": "Ese usuario ya existe."}, status=409)

    user = User.objects.create_user(
        username=correo,
        password=password,
        first_name=nombre_completo
    )

    try:
        cuidador_id = _mysql_insert_usuario(
            nombre_completo,
            password,
            "cuidador",
            correo=correo,
            telefono=telefono
        )
    except Exception as e:
        user.delete()
        return JsonResponse({"ok": False, "error": f"No se pudo registrar en MySQL: {e}"}, status=500)

    try:
        ok_membresia = guardar_membresia(cuidador_id)
        if not ok_membresia:
            user.delete()
            with connection.cursor() as cursor:
                cursor.execute("DELETE FROM Usuarios WHERE Id_Usuario=%s", [cuidador_id])
            connection.commit()
            return JsonResponse({"ok": False, "error": "No se pudo guardar la membresía."}, status=500)
    except Exception as e:
        user.delete()
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM Usuarios WHERE Id_Usuario=%s", [cuidador_id])
        connection.commit()
        return JsonResponse({"ok": False, "error": f"Error guardando membresía: {e}"}, status=500)

    return JsonResponse({
        "ok": True,
        "message": "Cuidador registrado con membresía activa.",
        "user": {
            "username": user.username,
            "nombre_completo": nombre_completo,
            "tipo": "cuidador",
            "correo": correo,
            "telefono": telefono,
        }
    })

@csrf_exempt
def api_v1_inicio(request):
    try:
        data = _json_body(request) if request.method == "POST" else {}
        username = (request.GET.get("username") or data.get("username") or "").strip()

        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        usuario_mysql = verificar_usuario_en_bd(username)
        if not usuario_mysql:
            return JsonResponse({"ok": False, "error": "Usuario no encontrado."}, status=404)

        nombre = usuario_mysql.get("nombre") or username
        codigo_unico = None
        es_premium = False
        esta_vinculado = False

        # Buscar user Django para obtener órdenes
        django_user = User.objects.filter(username__iexact=username.lower()).first()

        if not django_user and usuario_mysql.get("correo"):
            django_user = User.objects.filter(username__iexact=usuario_mysql.get("correo")).first()

        if not django_user and usuario_mysql.get("nombre"):
            django_user = User.objects.filter(first_name__iexact=usuario_mysql.get("nombre")).first()

        ultimas = []
        if django_user:
            ordenes = OrdenVoz.objects.filter(usuario=django_user).order_by("-creado")[:5]
            ultimas = [
                {
                    "id": o.id,
                    "texto": o.texto or "",
                    "respuesta": o.respuesta or "",
                    "fecha": timezone.localtime(o.creado).strftime("%d/%m %H:%M"),
                }
                for o in ordenes
            ]

        if usuario_mysql.get("tipo") == "adulto":
            usuario_id = int(usuario_mysql.get("id") or 0)
            if usuario_id:
                codigo_unico = _mysql_get_or_create_codigo_unico(usuario_id)
                es_premium = _mysql_adulto_premium_activo(usuario_id)
                vinculo = _mysql_get_vinculo_por_adulto(usuario_id)
                esta_vinculado = bool(vinculo and vinculo.get("activo"))

        return JsonResponse({
            "ok": True,
            "nombre": nombre,
            "codigo_unico": codigo_unico,
            "es_premium": es_premium,
            "esta_vinculado": esta_vinculado,
            "ultimas": ultimas,
        })

    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

def _procesar_orden_openai_para_usuario(django_user, texto, asr_conf=None):
    texto = (texto or "").strip().lower()

    # CASO 1: No se detectó voz
    if not texto:
        orden = OrdenVoz.objects.create(
            usuario=django_user,
            texto="(vacío)",
            respuesta="No pude escuchar nada. ¿Podrías repetir cerca del micrófono?",
            intent="no_entendido",
            meta={"reason": "asr_empty", "asr_conf": asr_conf, "provider": "openai"},
        )
        return {
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
        }

    palabras_cancelacion = ["cancelar", "anular", "me equivoqué", "olvida eso", "no eso", "borra eso"]
    if any(p in texto for p in palabras_cancelacion):
        respuesta_cancelacion = "Está bien, he cancelado la orden. Puedes decirme otra cosa cuando quieras."
        orden = OrdenVoz.objects.create(
            usuario=django_user,
            texto=texto,
            respuesta=respuesta_cancelacion,
            intent="cancelacion",
            meta={"reason": "user_cancelled", "asr_conf": asr_conf, "provider": "openai"},
        )
        return {
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
        }

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

    es_alarma = any(p in texto for p in palabras_alarmas)
    contiene_medicamento_nombre = any(m in texto for m in nombres_medicamentos)
    es_medicamento = contiene_medicamento_nombre or (
        any(p in texto for p in palabras_clave_medicamentos) and
        any(m in texto for m in nombres_medicamentos)
    )

    if not (es_medicamento or es_alarma):
        respuesta_fuera = (
            "Solo puedo ayudarte con medicamentos o alarmas. "
            "Por ejemplo: ¿Para qué sirve el ambroxol? o Pon una alarma a las ocho de la mañana."
        )
        orden = OrdenVoz.objects.create(
            usuario=django_user,
            texto=texto,
            respuesta=respuesta_fuera,
            intent="fuera_de_tema",
            meta={"reason": "out_of_scope", "asr_conf": asr_conf, "provider": "openai"},
        )
        return {
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
        }

    result = preguntar_openai(texto)
    respuesta_ia = (result.get("respuesta") or "").strip()
    intent = result.get("intent", "desconocido")
    ia_conf = float(result.get("confidence", 0.0))
    meta = result.get("meta") or {}

    if not respuesta_ia:
        orden = OrdenVoz.objects.create(
            usuario=django_user,
            texto=texto,
            respuesta="No entendí lo que dijiste, ¿puedes repetirlo con otras palabras?",
            intent="no_entendido",
            meta={"reason": "empty_ai_response", "asr_conf": asr_conf, "provider": "openai"},
        )
        return {
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
        }

    orden = OrdenVoz.objects.create(
        usuario=django_user,
        texto=texto,
        respuesta=respuesta_ia,
        intent=intent,
        meta={"ia_conf": ia_conf, "asr_conf": asr_conf, "provider": "openai", "meta": meta},
    )

    alarm_created = False

    if intent == "alarma":
        try:
            alarm_created = _crear_alarma_desde_meta(django_user, meta)
            if alarm_created:
                logger.info(f"🟢 Alarma creada vía IA: meta={meta}")
        except Exception as e:
            logger.exception(f"❌ Error creando alarma: {e}")

    return {
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
    }

@csrf_exempt
def api_v1_registrar_orden_openai(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)

    data = _json_body(request)
    username = (data.get("username") or "").strip()
    texto = (data.get("texto") or "").strip()
    asr_conf = data.get("asr_conf")

    try:
        asr_conf = float(asr_conf) if asr_conf is not None else None
    except Exception:
        asr_conf = None

    if not username:
        return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

    usuario_mysql = verificar_usuario_en_bd(username)
    if not usuario_mysql:
        return JsonResponse({"ok": False, "error": "Usuario no encontrado."}, status=404)

    django_user = User.objects.filter(username__iexact=username.lower()).first()

    if not django_user and usuario_mysql.get("correo"):
        django_user = User.objects.filter(username__iexact=usuario_mysql["correo"].lower()).first()

    if not django_user and usuario_mysql.get("nombre"):
        django_user = User.objects.filter(first_name__iexact=usuario_mysql["nombre"]).first()

    if not django_user:
        return JsonResponse({"ok": False, "error": "No encontré el usuario Django."}, status=404)

    try:
        resultado = _procesar_orden_openai_para_usuario(django_user, texto, asr_conf)
        return JsonResponse(resultado)
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)


@csrf_exempt
def api_v1_alarmas_pendientes(request):
    username = (request.GET.get("username") or "").strip()
    if not username:
        return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

    usuario_mysql = verificar_usuario_en_bd(username)
    if not usuario_mysql:
        return JsonResponse({"ok": False, "error": "Usuario no encontrado."}, status=404)

    django_user = User.objects.filter(username__iexact=username.lower()).first()

    if not django_user and usuario_mysql.get("correo"):
        django_user = User.objects.filter(username__iexact=usuario_mysql["correo"].lower()).first()

    if not django_user and usuario_mysql.get("nombre"):
        django_user = User.objects.filter(first_name__iexact=usuario_mysql["nombre"]).first()

    if not django_user:
        return JsonResponse({"ok": False, "error": "No encontré el usuario Django."}, status=404)

    ahora = timezone.localtime()

    def _norm_dia(token):
        txt = unicodedata.normalize("NFKD", str(token or ""))
        txt = txt.encode("ascii", "ignore").decode("ascii").lower().strip()
        txt = re.sub(r"[^a-z]", "", txt)
        return txt[:3]

    def _aplica_hoy(alarma):
        if alarma.fecha and alarma.fecha != ahora.date():
            return False
        raw = (alarma.dias or "").strip()
        if not raw:
            return True

        hoy_tokens = {
            0: {"lun", "mon"},
            1: {"mar", "tue"},
            2: {"mie", "wed"},
            3: {"jue", "thu"},
            4: {"vie", "fri"},
            5: {"sab", "sat"},
            6: {"dom", "sun"},
        }[ahora.weekday()]
        dias = {_norm_dia(x) for x in re.split(r"[,;/\s]+", raw) if _norm_dia(x)}
        return bool(dias & hoy_tokens)

    alarmas = (
        Alarma.objects
        .filter(usuario=django_user, activa=True)
        .filter(Q(fecha__isnull=True) | Q(fecha=ahora.date()))
        .order_by("hora")
    )

    data = []
    for a in alarmas:
        if not _aplica_hoy(a):
            continue

        if a.disparada_at and (ahora - a.disparada_at).total_seconds() < 90:
            continue

        base_dt = timezone.make_aware(
            datetime.combine(ahora.date(), a.hora),
            timezone.get_current_timezone(),
        )

        delta = (ahora - base_dt).total_seconds()
        if delta < 0 or delta > 40:
            continue

        if a.disparada_at and (ahora - a.disparada_at).total_seconds() < 300:
            continue

        if abs((base_dt - ahora).total_seconds()) > 75:
            continue

        a.disparada_at = timezone.now()
        a.save(update_fields=["disparada_at"])

        data.append({
            "id": a.id,
            "mensaje": a.mensaje,
            "hora": a.hora.strftime("%H:%M"),
        })

    return JsonResponse({"ok": True, "alarmas": data})

@csrf_exempt
def api_v1_alarmas(request):
    username = (request.GET.get("username") or "").strip()
    if not username:
        return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

    usuario_mysql = verificar_usuario_en_bd(username)
    if not usuario_mysql:
        return JsonResponse({"ok": False, "error": "Usuario no encontrado."}, status=404)

    django_user = User.objects.filter(username__iexact=username.lower()).first()
    if not django_user and usuario_mysql.get("correo"):
        django_user = User.objects.filter(username__iexact=usuario_mysql["correo"].lower()).first()
    if not django_user and usuario_mysql.get("nombre"):
        django_user = User.objects.filter(first_name__iexact=usuario_mysql["nombre"]).first()
    if not django_user:
        return JsonResponse({"ok": False, "error": "No encontre el usuario Django."}, status=404)

    alarmas = (
        Alarma.objects
        .filter(usuario=django_user)
        .order_by("fecha", "hora")
    )

    data = [
        {
            "id": a.id,
            "hora": a.hora.strftime("%H:%M"),
            "mensaje": a.mensaje,
            "dias": a.dias or "",
            "fecha": a.fecha.isoformat() if a.fecha else None,
            "activa": bool(a.activa),
        }
        for a in alarmas
    ]
    return JsonResponse({"ok": True, "alarmas": data})


@csrf_exempt
def api_v1_marcar_entregada(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)

    data = _json_body(request)
    username = (data.get("username") or "").strip()
    alarma_id = data.get("id")

    if not username or not alarma_id:
        return JsonResponse({"ok": False, "error": "Username e id requeridos."}, status=400)

    usuario_mysql = verificar_usuario_en_bd(username)
    if not usuario_mysql:
        return JsonResponse({"ok": False, "error": "Usuario no encontrado."}, status=404)

    django_user = User.objects.filter(username__iexact=username.lower()).first()

    if not django_user and usuario_mysql.get("correo"):
        django_user = User.objects.filter(username__iexact=usuario_mysql["correo"].lower()).first()

    if not django_user and usuario_mysql.get("nombre"):
        django_user = User.objects.filter(first_name__iexact=usuario_mysql["nombre"]).first()

    if not django_user:
        return JsonResponse({"ok": False, "error": "No encontré el usuario Django."}, status=404)

    try:
        a = Alarma.objects.get(id=alarma_id, usuario=django_user)

        dias = (a.dias or "").strip()
        if not dias and a.fecha:
            a.entregada = True
            a.activa = False
        else:
            a.entregada = False
            a.disparada_at = timezone.now()

        a.save()
        return JsonResponse({"ok": True})
    except Alarma.DoesNotExist:
        return JsonResponse({"ok": False, "error": "No existe"}, status=404)

@csrf_exempt
def api_v1_medicamentos_analizar(request):
    """
    Endpoint para Flutter:
    - recibe multipart/form-data
    - campos esperados:
        - username
        - foto
    No guarda imagen ni captura temporal.
    """
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Método no permitido"}, status=405)

    try:
        username = (request.POST.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        usuario_mysql = verificar_usuario_en_bd(username)
        if not usuario_mysql:
            return JsonResponse({"ok": False, "error": "Usuario no encontrado."}, status=404)

        django_user = User.objects.filter(username__iexact=username.lower()).first()

        if not django_user and usuario_mysql.get("correo"):
            django_user = User.objects.filter(username__iexact=usuario_mysql["correo"].lower()).first()

        if not django_user and usuario_mysql.get("nombre"):
            django_user = User.objects.filter(first_name__iexact=usuario_mysql["nombre"]).first()

        if not django_user:
            return JsonResponse({"ok": False, "error": "No encontré el usuario Django."}, status=404)

        foto = request.FILES.get("foto")
        if not foto:
            return JsonResponse({"ok": False, "error": "No llegó la imagen."}, status=400)

        image_bytes = foto.read()
        if not image_bytes:
            return JsonResponse({"ok": False, "error": "No se pudo leer la imagen."}, status=400)

        # Validación real de imagen
        try:
            img_test = Image.open(io.BytesIO(image_bytes))
            img_test.verify()
        except Exception:
            return JsonResponse({"ok": False, "error": "El archivo seleccionado no es una imagen válida."}, status=400)

        nombre, para_que_sirve, debug_text = analizar_imagen_openai_bytes(image_bytes)

        if nombre:
            return JsonResponse({
                "ok": True,
                "nombre": nombre,
                "para_que_sirve": para_que_sirve,
            })

        return JsonResponse({
            "ok": False,
            "error": "No pude identificar el medicamento en la foto.",
            "debug": debug_text,
        }, status=200)

    except Exception as e:
        return JsonResponse({"ok": False, "error": f"Error analizando imagen: {e}"}, status=500)

@csrf_exempt
def api_v1_interfaz_cuidador(request):
    """
    Devuelve la información base del cuidador para Flutter:
    - datos del cuidador
    - adulto vinculado (si existe)
    - bloqueo por vínculo
    """
    try:
        data = _json_body(request) if request.method == "POST" else {}
        username = (request.GET.get("username") or data.get("username") or "").strip()

        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)

        if not mysql_user or mysql_user.get("tipo") != "cuidador":
            return JsonResponse(
                {"ok": False, "error": "Solo cuidadores."},
                status=403
            )

        cuidador_id = mysql_user.get("id")
        nombre = mysql_user.get("nombre") or ""
        correo = (mysql_user.get("correo") or "").strip()
        telefono = (mysql_user.get("telefono") or "").strip()

        adulto_vinculado = None
        if cuidador_id:
            adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)

        return JsonResponse({
            "ok": True,
            "cuidador": {
                "id": cuidador_id,
                "nombre": nombre,
                "correo": correo,
                "telefono": telefono,
            },
            "adulto_vinculado": (
                {
                    "id": adulto_vinculado["id"],
                    "nombre": adulto_vinculado["nombre"],
                }
                if adulto_vinculado else None
            ),
            "bloqueado_por_vinculo": adulto_vinculado is None,
        })

    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_eliminar_alarma(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

    data = _json_body(request)
    username = (data.get("username") or "").strip()
    alarma_id = data.get("id")

    if not username or not alarma_id:
        return JsonResponse({"ok": False, "error": "Username e id requeridos."}, status=400)

    usuario_mysql = verificar_usuario_en_bd(username)
    if not usuario_mysql:
        return JsonResponse({"ok": False, "error": "Usuario no encontrado."}, status=404)

    django_user = User.objects.filter(username__iexact=username.lower()).first()
    if not django_user and usuario_mysql.get("correo"):
        django_user = User.objects.filter(username__iexact=usuario_mysql["correo"].lower()).first()
    if not django_user and usuario_mysql.get("nombre"):
        django_user = User.objects.filter(first_name__iexact=usuario_mysql["nombre"]).first()
    if not django_user:
        return JsonResponse({"ok": False, "error": "No encontre el usuario Django."}, status=404)

    alarma = Alarma.objects.filter(id=alarma_id, usuario=django_user).first()
    if not alarma:
        return JsonResponse({"ok": False, "error": "Alarma no encontrada."}, status=404)

    alarma.delete()
    return JsonResponse({"ok": True})

@csrf_exempt
def api_v1_cuidador_alarmas(request):
    try:
        username = (request.GET.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        adulto_django, err = _cuidador_get_adulto_django_from_username(username)
        if err:
            return JsonResponse({"ok": False, "error": err}, status=403)

        alarmas = (
            Alarma.objects
            .filter(usuario=adulto_django)
            .order_by("fecha", "hora")
        )

        data = [
            {
                "id": a.id,
                "hora": a.hora.strftime("%H:%M"),
                "mensaje": a.mensaje,
                "dias": a.dias or "",
                "fecha": a.fecha.isoformat() if a.fecha else None,
                "activa": bool(a.activa),
            }
            for a in alarmas
        ]
        return JsonResponse({"ok": True, "alarmas": data})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_cuidador_alarmas_crear(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

    try:
        data = _json_body(request)
        username = (data.get("username") or "").strip()
        adulto_django, err = _cuidador_get_adulto_django_from_username(username)
        if err:
            return JsonResponse({"ok": False, "error": err}, status=403)

        fecha_raw = data.get("fecha")
        hora_raw = data.get("hora")
        mensaje = (data.get("mensaje") or "Es hora de tu alarma!").strip()
        dias = (data.get("dias") or "").strip()
        activa = bool(data.get("activa", True))

        if not hora_raw:
            return JsonResponse({"ok": False, "error": "Hora requerida"}, status=400)

        hora = _parse_hora(hora_raw)
        if not hora:
            return JsonResponse({"ok": False, "error": "Hora invalida"}, status=400)

        fecha = _parse_fecha(fecha_raw) if fecha_raw else None

        alarma = Alarma.objects.create(
            usuario=adulto_django,
            fecha=fecha,
            hora=hora,
            mensaje=mensaje,
            dias=dias,
            activa=activa,
        )
        return JsonResponse({"ok": True, "id": alarma.id})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_cuidador_alarmas_editar(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

    try:
        data = _json_body(request)
        username = (data.get("username") or "").strip()
        adulto_django, err = _cuidador_get_adulto_django_from_username(username)
        if err:
            return JsonResponse({"ok": False, "error": err}, status=403)

        _id = data.get("id")
        if not _id:
            return JsonResponse({"ok": False, "error": "ID requerido"}, status=400)

        hora_raw = data.get("hora")
        mensaje = (data.get("mensaje") or "").strip()
        fecha_raw = data.get("fecha")
        dias = (data.get("dias") or "").strip()
        activa = bool(data.get("activa", True))

        if not hora_raw:
            return JsonResponse({"ok": False, "error": "Hora requerida"}, status=400)
        if not mensaje:
            return JsonResponse({"ok": False, "error": "Mensaje requerido"}, status=400)

        hora = _parse_hora(hora_raw)
        if not hora:
            return JsonResponse({"ok": False, "error": "Hora invalida"}, status=400)

        fecha = _parse_fecha(fecha_raw) if fecha_raw else None

        alarma = Alarma.objects.filter(id=_id, usuario=adulto_django).first()
        if not alarma:
            return JsonResponse({"ok": False, "error": "Alarma no encontrada"}, status=404)

        alarma.hora = hora
        alarma.mensaje = mensaje
        alarma.fecha = fecha
        alarma.dias = dias
        alarma.activa = activa
        alarma.save(update_fields=["hora", "mensaje", "fecha", "dias", "activa"])
        return JsonResponse({"ok": True})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_cuidador_alarmas_eliminar(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

    try:
        data = _json_body(request)
        username = (data.get("username") or "").strip()
        adulto_django, err = _cuidador_get_adulto_django_from_username(username)
        if err:
            return JsonResponse({"ok": False, "error": err}, status=403)

        _id = data.get("id")
        if not _id:
            return JsonResponse({"ok": False, "error": "ID requerido"}, status=400)

        alarma = Alarma.objects.filter(id=_id, usuario=adulto_django).first()
        if not alarma:
            return JsonResponse({"ok": False, "error": "Alarma no encontrada"}, status=404)

        alarma.delete()
        return JsonResponse({"ok": True})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)


@csrf_exempt
def api_v1_cuidador_alertas_medicamentos(request):
    try:
        username = (request.GET.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        adulto_django, err = _cuidador_get_adulto_django_from_username(username)
        if err:
            return JsonResponse({"ok": False, "error": err}, status=403)

        ahora = timezone.localtime()
        espera_min = ahora - timedelta(minutes=10)
        recientes_min = ahora - timedelta(hours=12)

        alertas = (
            Alarma.objects
            .filter(
                usuario=adulto_django,
                activa=True,
                entregada=False,
                disparada_at__isnull=False,
                disparada_at__lte=espera_min,
                disparada_at__gte=recientes_min,
            )
            .order_by("-disparada_at")
        )

        data = []
        for alarma in alertas:
            mensaje = (alarma.mensaje or "").strip()
            if mensaje.lower().startswith("cita:"):
                continue

            data.append({
                "id": alarma.id,
                "mensaje": mensaje,
                "hora": alarma.hora.strftime("%H:%M"),
                "fecha": alarma.fecha.isoformat() if alarma.fecha else None,
                "disparada_at": alarma.disparada_at.isoformat() if alarma.disparada_at else None,
            })

        return JsonResponse({"ok": True, "alertas": data})
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)


@csrf_exempt
@require_POST
def api_v1_cuidador_crear_alarmas_receta(request):
    try:
        username = (request.POST.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "cuidador":
            return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

        cuidador_id = mysql_user["id"]
        if not _mysql_cuidador_premium_activo(int(cuidador_id)):
            return JsonResponse(
                {"ok": False, "error": "Funcion premium. Activa tu membresia para usar recetas."},
                status=403,
            )

        adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
        if not adulto_vinculado:
            return JsonResponse({"ok": False, "error": "No tienes un adulto vinculado."}, status=403)

        adulto_id = int(adulto_vinculado["id"])

        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT Nombre_Completo, correo FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
                [adulto_id],
            )
            row = cursor.fetchone()

        if not row:
            return JsonResponse({"ok": False, "error": "No encontre al adulto vinculado."}, status=404)

        nombre_adulto = row[0] or ""
        correo_adulto = row[1] or ""
        adulto_django = _django_user_from_mysql_adulto(nombre_adulto, correo_adulto)
        if not adulto_django:
            return JsonResponse({"ok": False, "error": "No encontre el usuario Django del adulto."}, status=404)

        foto = request.FILES.get("foto")
        if not foto:
            return JsonResponse({"ok": False, "error": "Falta la imagen de la receta."}, status=400)

        content_type = (getattr(foto, "content_type", "") or "").lower()
        filename = (getattr(foto, "name", "") or "").lower()
        extensiones_validas = (".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".heic")
        if not content_type.startswith("image/") and not filename.endswith(extensiones_validas):
            return JsonResponse({"ok": False, "error": "Formato no valido. Debe ser imagen."}, status=400)

        image_bytes = foto.read()
        if not image_bytes:
            return JsonResponse({"ok": False, "error": "No se pudo leer la imagen."}, status=400)

        medicamentos, debug_text = _analizar_receta_openai(image_bytes)
        if not medicamentos:
            return JsonResponse(
                {
                    "ok": False,
                    "message": "Detecte 0 medicamentos",
                    "detectados": 0,
                    "medicamentos": [],
                    "error": "No pude extraer medicamentos de la receta.",
                    "debug": debug_text,
                },
                status=200,
            )

        tratamiento_id, total_alarmas, resumen = _guardar_tratamiento_medicamentos_alarmas(
            adulto_id,
            medicamentos,
            django_user=adulto_django,
        )
        detectados = len(resumen)

        return JsonResponse(
            {
                "ok": True,
                "message": f"Detecte {detectados} medicamentos para {adulto_vinculado['nombre']}",
                "detectados": detectados,
                "tratamiento_id": tratamiento_id,
                "alarmas_creadas": total_alarmas,
                "medicamentos": resumen,
                "adulto": {
                    "id": adulto_id,
                    "nombre": adulto_vinculado["nombre"],
                },
            }
        )
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_cuidador_ubicacion_ultima(request):
    try:
        username = (request.GET.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "cuidador":
            return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

        cuidador_id = mysql_user["id"]
        adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
        if not adulto_vinculado:
            return JsonResponse({
                "ok": True,
                "adulto": None,
                "compartir_ubicacion": False,
                "sin_senal": True,
                "ultima": None,
            })

        adulto_id = adulto_vinculado["id"]
        compartir = _mysql_get_compartir_ubicacion(adulto_id)

        if not compartir:
            return JsonResponse({
                "ok": True,
                "adulto": adulto_vinculado,
                "compartir_ubicacion": False,
                "sin_senal": False,
                "ultima": None,
            })

        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT lat, lng, precision_m, actualizado_en,
                       TIMESTAMPDIFF(SECOND, actualizado_en, NOW()) AS diff_seg
                FROM ubicacion_actual
                WHERE usuario_id=%s
                LIMIT 1
            """, [adulto_id])
            row = cursor.fetchone()

        if not row:
            return JsonResponse({
                "ok": True,
                "adulto": adulto_vinculado,
                "compartir_ubicacion": True,
                "sin_senal": True,
                "ultima": None,
            })

        lat, lng, precision, actualizado_en, diff_seg = row
        try:
            sin_senal = (diff_seg is None) or (int(diff_seg) > 180)
        except Exception:
            sin_senal = False

        return JsonResponse({
            "ok": True,
            "adulto": adulto_vinculado,
            "compartir_ubicacion": True,
            "sin_senal": sin_senal,
            "ultima": {
                "lat": float(lat),
                "lng": float(lng),
                "accuracy": float(precision) if precision is not None else None,
                "timestamp": actualizado_en.isoformat() if actualizado_en else None,
            },
        })
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_cuidador_ubicacion_historial(request):
    try:
        username = (request.GET.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "cuidador":
            return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

        cuidador_id = mysql_user["id"]
        adulto_vinculado = _mysql_get_unico_vinculo_cuidador(cuidador_id)
        if not adulto_vinculado:
            return JsonResponse({"ok": True, "adulto": None, "puntos": []})

        adulto_id = adulto_vinculado["id"]
        if not _mysql_get_compartir_ubicacion(adulto_id):
            return JsonResponse({
                "ok": True,
                "adulto": adulto_vinculado,
                "compartir_ubicacion": False,
                "puntos": [],
            })

        horas = request.GET.get("horas")
        try:
            horas = int(horas) if horas else 24
            horas = max(1, min(horas, 72))
        except Exception:
            horas = 24

        limite = request.GET.get("limite")
        try:
            limite = int(limite) if limite else 500
            limite = max(50, min(limite, 2000))
        except Exception:
            limite = 500

        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT lat, lng, precision_m, creado_en
                FROM ubicacion_historial
                WHERE usuario_id=%s
                  AND creado_en >= (NOW() - INTERVAL %s HOUR)
                ORDER BY creado_en ASC
                LIMIT %s
            """, [adulto_id, horas, limite])
            rows = cursor.fetchall()

        puntos = [
            {
                "lat": float(r[0]),
                "lng": float(r[1]),
                "accuracy": float(r[2]) if r[2] is not None else None,
                "timestamp": r[3].isoformat() if r[3] else None,
            }
            for r in rows
        ]

        return JsonResponse({
            "ok": True,
            "adulto": adulto_vinculado,
            "compartir_ubicacion": True,
            "puntos": puntos,
        })
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_ubicacion_estado(request):
    try:
        username = (request.GET.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "adulto":
            return JsonResponse({"ok": False, "error": "Solo adultos."}, status=403)

        usuario_id = int(mysql_user["id"])
        compartir = _mysql_get_compartir_ubicacion(usuario_id)

        ubicacion_actualizada_en = None
        try:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SELECT ubicacion_actualizada_en FROM Usuarios WHERE Id_Usuario=%s LIMIT 1",
                    [usuario_id],
                )
                row = cursor.fetchone()
            if row and row[0]:
                ubicacion_actualizada_en = row[0].isoformat()
        except Exception:
            ubicacion_actualizada_en = None

        return JsonResponse({
            "ok": True,
            "compartir_ubicacion": compartir,
            "ubicacion_actualizada_en": ubicacion_actualizada_en,
        })
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_ubicacion_toggle(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except Exception:
        body = {}

    try:
        username = (body.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "adulto":
            return JsonResponse({"ok": False, "error": "Solo adultos."}, status=403)

        usuario_id = int(mysql_user["id"])

        if "activar" in body:
            activar = bool(body.get("activar"))
        else:
            activar = not _mysql_get_compartir_ubicacion(usuario_id)

        _mysql_set_compartir_ubicacion(usuario_id, activar)

        return JsonResponse({
            "ok": True,
            "compartir_ubicacion": activar,
            "ubicacion_actualizada_en": None,
        })
    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_ubicacion_ping(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except Exception:
        body = {}

    try:
        username = (body.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "adulto":
            return JsonResponse({"ok": False, "error": "Solo adultos."}, status=403)

        usuario_id = int(mysql_user["id"])
        if not _mysql_get_compartir_ubicacion(usuario_id):
            return JsonResponse({"ok": False, "error": "Ubicacion desactivada."}, status=403)

        lat = float(body.get("lat"))
        lng = float(body.get("lng"))
        precision = body.get("accuracy")
        precision = float(precision) if precision is not None else None

        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO ubicacion_actual (usuario_id, lat, lng, precision_m)
                VALUES (%s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                  lat = VALUES(lat),
                  lng = VALUES(lng),
                  precision_m = VALUES(precision_m),
                  actualizado_en = CURRENT_TIMESTAMP
            """, [usuario_id, lat, lng, precision])

            try:
                cursor.execute("""
                    UPDATE Usuarios SET ubicacion_actualizada_en=CURRENT_TIMESTAMP
                    WHERE Id_Usuario=%s
                """, [usuario_id])
            except Exception:
                pass

        guardar_cada_seg = 180
        guardar_si_movio_m = 30

        ultimo = _mysql_get_ultimo_punto_historial(usuario_id)
        debe_guardar = False

        if not ultimo:
            debe_guardar = True
        else:
            try:
                diff = (timezone.now() - ultimo["creado_en"]).total_seconds()
            except Exception:
                diff = 999999

            if diff >= guardar_cada_seg:
                debe_guardar = True
            else:
                try:
                    dist_m = _haversine_m(ultimo["lat"], ultimo["lng"], lat, lng)
                    if dist_m >= guardar_si_movio_m:
                        debe_guardar = True
                except Exception:
                    pass

        if debe_guardar:
            with connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO ubicacion_historial (usuario_id, lat, lng, precision_m)
                    VALUES (%s, %s, %s, %s)
                """, [usuario_id, lat, lng, precision])

        connection.commit()
        return JsonResponse({"ok": True, "guardado_historial": bool(debe_guardar)})
    except Exception:
        return JsonResponse({"ok": False, "error": "Datos invalidos (lat/lng)."}, status=400)


@csrf_exempt
def api_v1_emergencia_crear(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except Exception:
        body = {}

    try:
        username = (body.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "adulto":
            return JsonResponse({"ok": False, "error": "Solo adultos pueden emitir SOS."}, status=403)

        adulto_id = int(mysql_user["id"])
        cuidador = _mysql_get_cuidador_por_adulto(adulto_id)

        if not cuidador:
            return JsonResponse({"ok": False, "error": "No hay cuidador vinculado."}, status=409)

        lat = body.get("lat")
        lng = body.get("lng")

        try:
            lat = float(lat) if lat is not None else None
        except Exception:
            lat = None

        try:
            lng = float(lng) if lng is not None else None
        except Exception:
            lng = None

        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT id_emergencia FROM emergencia "
                "WHERE adulto_id=%s AND estado='enviada' "
                "AND creado_en >= (NOW() - INTERVAL 45 SECOND) "
                "ORDER BY id_emergencia DESC LIMIT 1",
                [adulto_id],
            )
            row_recent = cursor.fetchone()

            if row_recent:
                return JsonResponse({
                    "ok": True,
                    "duplicada": True,
                    "id_emergencia": int(row_recent[0]),
                })

            if lat is None or lng is None:
                cursor.execute(
                    "SELECT lat, lng FROM ubicacion_actual WHERE usuario_id=%s LIMIT 1",
                    [adulto_id],
                )
                row_pos = cursor.fetchone()
                lat = float(row_pos[0]) if row_pos and row_pos[0] is not None else None
                lng = float(row_pos[1]) if row_pos and row_pos[1] is not None else None

            cursor.execute(
                "INSERT INTO emergencia (lat, lng, estado, creado_en, adulto_id, cuidador_id) "
                "VALUES (%s, %s, 'enviada', NOW(), %s, %s)",
                [lat, lng, adulto_id, int(cuidador["id"])],
            )
            emergencia_id = int(cursor.lastrowid)

        return JsonResponse({
            "ok": True,
            "id_emergencia": emergencia_id,
            "estado": "enviada",
            "adulto_id": adulto_id,
            "adulto_nombre": mysql_user.get("nombre"),
            "cuidador_id": int(cuidador["id"]),
            "cuidador_nombre": cuidador.get("nombre"),
            "lat": lat,
            "lng": lng,
        })

    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)

@csrf_exempt
def api_v1_emergencia_pendientes(request):
    try:
        username = (request.GET.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "cuidador":
            return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

        cuidador_id = int(mysql_user["id"])

        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT e.id_emergencia, e.lat, e.lng, e.estado, e.creado_en, e.atendido_en, "
                "u.Id_Usuario, u.Nombre_Completo "
                "FROM emergencia e "
                "INNER JOIN Usuarios u ON u.Id_Usuario = e.adulto_id "
                "WHERE e.cuidador_id=%s AND e.estado IN ('enviada', 'vista') "
                "ORDER BY e.creado_en DESC LIMIT 20",
                [cuidador_id],
            )
            rows = cursor.fetchall()

        emergencias = []
        for r in rows:
            emergencias.append({
                "id_emergencia": int(r[0]),
                "lat": float(r[1]) if r[1] is not None else None,
                "lng": float(r[2]) if r[2] is not None else None,
                "estado": r[3],
                "creado_en": r[4].isoformat() if r[4] else None,
                "atendido_en": r[5].isoformat() if r[5] else None,
                "adulto": {
                    "id": int(r[6]),
                    "nombre": r[7],
                }
            })

        return JsonResponse({"ok": True, "emergencias": emergencias})

    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)
    
@csrf_exempt
def api_v1_emergencia_actualizar(request):
    if request.method != "POST":
        return JsonResponse({"ok": False, "error": "Metodo no permitido"}, status=405)

    try:
        body = json.loads(request.body.decode("utf-8") or "{}")
    except Exception:
        body = {}

    try:
        username = (body.get("username") or "").strip()
        if not username:
            return JsonResponse({"ok": False, "error": "Username requerido."}, status=400)

        mysql_user = verificar_usuario_en_bd(username)
        if not mysql_user or mysql_user.get("tipo") != "cuidador":
            return JsonResponse({"ok": False, "error": "Solo cuidadores."}, status=403)

        cuidador_id = int(mysql_user["id"])

        emergencia_id = body.get("id_emergencia")
        estado = (body.get("estado") or "").strip().lower()

        try:
            emergencia_id = int(emergencia_id)
        except Exception:
            return JsonResponse({"ok": False, "error": "id_emergencia invalido."}, status=400)

        if estado not in ("vista", "atendida", "cerrada"):
            return JsonResponse({"ok": False, "error": "Estado invalido."}, status=400)

        with connection.cursor() as cursor:
            if estado in ("atendida", "cerrada"):
                cursor.execute(
                    "UPDATE emergencia "
                    "SET estado=%s, atendido_en=NOW() "
                    "WHERE id_emergencia=%s AND cuidador_id=%s",
                    [estado, emergencia_id, cuidador_id],
                )
            else:
                cursor.execute(
                    "UPDATE emergencia "
                    "SET estado=%s "
                    "WHERE id_emergencia=%s AND cuidador_id=%s",
                    [estado, emergencia_id, cuidador_id],
                )

            updated = int(cursor.rowcount or 0)

        if updated <= 0:
            return JsonResponse({"ok": False, "error": "Emergencia no encontrada."}, status=404)

        return JsonResponse({
            "ok": True,
            "id_emergencia": emergencia_id,
            "estado": estado,
        })

    except Exception as e:
        return JsonResponse({"ok": False, "error": str(e)}, status=500)
    
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



# ----  VISTAS AMINISTRADOR ------
@login_required
def interfaz_admin(request):
    ok, resp = _require_admin(request)
    if not ok:
        return redirect("inicio")

    total_usuarios = 0
    total_adultos = 0
    total_cuidadores = 0
    total_admins = 0
    total_alarmas_activas = 0
    usuarios = []

    # NUEVO
    relaciones_cuidado = []
    adultos_sin_vinculo = 0

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) FROM Usuarios WHERE activo = 1")
            total_usuarios = cursor.fetchone()[0] or 0

            cursor.execute("SELECT COUNT(*) FROM Usuarios WHERE Tipo = 'adulto' AND activo = 1")
            total_adultos = cursor.fetchone()[0] or 0

            cursor.execute("SELECT COUNT(*) FROM Usuarios WHERE Tipo = 'cuidador' AND activo = 1")
            total_cuidadores = cursor.fetchone()[0] or 0

            cursor.execute("SELECT COUNT(*) FROM Usuarios WHERE Tipo = 'admin' AND activo = 1")
            total_admins = cursor.fetchone()[0] or 0

            total_alarmas_activas = Alarma.objects.filter(activa=True).count()

            cursor.execute("""
                SELECT Id_Usuario, Nombre_Completo, Tipo, activo, creado_en
                FROM Usuarios
                ORDER BY creado_en DESC
            """)
            rows = cursor.fetchall()

            for row in rows:
                usuarios.append({
                    "id": row[0],
                    "nombre": row[1],
                    "tipo": row[2],
                    "activo": bool(row[3]),
                    "fecha_registro": row[4],
                })

            # ===== NUEVO: RESUMEN DE RELACIONES ADULTO - CUIDADOR =====
            cursor.execute("""
                SELECT 
                    ua.Nombre_Completo AS adulto_nombre,
                    uc.Nombre_Completo AS cuidador_nombre
                FROM adulto_cuidador ac
                INNER JOIN Usuarios ua ON ua.Id_Usuario = ac.Adulto_id
                INNER JOIN Usuarios uc ON uc.Id_Usuario = ac.Cuidador_id
                WHERE ac.Activo = 1
                ORDER BY ac.fecha_asignacion DESC
                LIMIT 5
            """)
            relaciones_rows = cursor.fetchall()

            for row in relaciones_rows:
                relaciones_cuidado.append({
                    "adulto_nombre": row[0],
                    "cuidador_nombre": row[1],
                })

            # ===== NUEVO: CONTAR ADULTOS SIN VÍNCULO =====
            cursor.execute("""
                SELECT COUNT(*)
                FROM Usuarios u
                WHERE u.Tipo = 'adulto'
                  AND u.activo = 1
                  AND u.Id_Usuario NOT IN (
                      SELECT ac.Adulto_id
                      FROM adulto_cuidador ac
                      WHERE ac.Activo = 1
                  )
            """)
            adultos_sin_vinculo = cursor.fetchone()[0] or 0

    except Exception as e:
        print(f"❌ Error cargando dashboard admin: {e}")

    nombre = request.user.first_name or request.user.username

    return render(request, "miapp/interfaz_admin.html", {
        "nombre": nombre,
        "total_usuarios": total_usuarios,
        "total_adultos": total_adultos,
        "total_cuidadores": total_cuidadores,
        "total_admins": total_admins,
        "total_alarmas_activas": total_alarmas_activas,
        "usuarios": usuarios,

        # NUEVO
        "relaciones_cuidado": relaciones_cuidado,
        "adultos_sin_vinculo": adultos_sin_vinculo,
    })

@login_required
def gestion_usuarios(request):
    ok, resp = _require_admin(request)
    if not ok:
        return redirect("inicio")
    return redirect("interfaz_admin")

@login_required
@require_POST
def cambiar_estado_usuario(request, user_id):
    ok, resp = _require_admin(request)
    if not ok:
        return redirect("inicio")

    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT Id_Usuario, Nombre_Completo, correo, Tipo, activo
                FROM Usuarios
                WHERE Id_Usuario = %s
                LIMIT 1
            """, [user_id])
            row = cursor.fetchone()

            if not row:
                messages.error(request, "Usuario no encontrado.")
                return redirect("gestion_usuarios")

            usuario_id, nombre, correo, tipo, activo_actual = row

            # Evita que un admin se desactive a sí mismo
            admin_actual = verificar_usuario_en_bd(request.user.username) or verificar_usuario_en_bd(request.user.first_name)
            if admin_actual and int(admin_actual["id"]) == int(usuario_id):
                messages.warning(request, "No puedes desactivar tu propia cuenta.")
                return redirect("gestion_usuarios")

            nuevo_estado = 0 if activo_actual else 1

            cursor.execute("""
                UPDATE Usuarios
                SET activo = %s
                WHERE Id_Usuario = %s
            """, [nuevo_estado, usuario_id])

        connection.commit()

        # sincronizar Django
        _sincronizar_usuario_django_activo(nombre, correo, bool(nuevo_estado))

        estado = "activada" if nuevo_estado else "desactivada"
        messages.success(request, f"La cuenta de {nombre} fue {estado}.")

    except Exception as e:
        connection.rollback()
        messages.error(request, f"Error al cambiar estado: {e}")

    return redirect("gestion_usuarios")


@login_required
def cambiar_tipo_usuario(request, user_id):
    ok, resp = _require_admin(request)
    if not ok:
        return redirect("inicio")

    if request.method == "POST":
        nuevo_tipo = (request.POST.get("tipo_cuenta") or "").strip().lower()

        if nuevo_tipo not in ["adulto", "cuidador", "admin"]:
            messages.error(request, "Tipo de cuenta no válido.")
            return redirect("gestion_usuarios")

        try:
            with connection.cursor() as cursor:
                cursor.execute("""
                    UPDATE Usuarios
                    SET Tipo = %s
                    WHERE Id_Usuario = %s
                """, [nuevo_tipo, user_id])

            connection.commit()
            messages.success(request, "Tipo de cuenta actualizado correctamente.")

        except Exception as e:
            connection.rollback()
            messages.error(request, f"Error al actualizar tipo: {e}")

    return redirect("gestion_usuarios")


@login_required
def restablecer_password_usuario(request, user_id):
    ok, resp = _require_admin(request)
    if not ok:
        return redirect("inicio")

    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT Id_Usuario, Nombre_Completo
                FROM Usuarios
                WHERE Id_Usuario = %s
                LIMIT 1
            """, [user_id])
            row = cursor.fetchone()

            if not row:
                messages.error(request, "Usuario no encontrado.")
                return redirect("gestion_usuarios")

            usuario_id, nombre = row
            nueva_password = get_random_string(10)
            nuevo_hash = make_password(nueva_password)

            cursor.execute("""
                UPDATE Usuarios
                SET password_hash = %s
                WHERE Id_Usuario = %s
            """, [nuevo_hash, usuario_id])

        connection.commit()

        messages.success(
            request,
            f"Contraseña restablecida para {nombre}. Nueva contraseña temporal: {nueva_password}"
        )

    except Exception as e:
        connection.rollback()
        messages.error(request, f"Error al restablecer contraseña: {e}")

    return redirect("gestion_usuarios")


@login_required
def eliminar_usuario_inactivo(request, user_id):
    ok, resp = _require_admin(request)
    if not ok:
        return redirect("inicio")

    try:
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT Id_Usuario, Nombre_Completo, activo
                FROM Usuarios
                WHERE Id_Usuario = %s
                LIMIT 1
            """, [user_id])
            row = cursor.fetchone()

            if not row:
                messages.error(request, "Usuario no encontrado.")
                return redirect("gestion_usuarios")

            usuario_id, nombre, activo = row

            if activo:
                messages.warning(request, "Solo se pueden eliminar cuentas inactivas.")
                return redirect("gestion_usuarios")

            cursor.execute("""
                DELETE FROM Usuarios
                WHERE Id_Usuario = %s
            """, [usuario_id])

        connection.commit()
        messages.success(request, f"La cuenta inactiva de {nombre} fue eliminada.")

    except Exception as e:
        connection.rollback()
        messages.error(request, f"Error al eliminar usuario: {e}")

    return redirect("gestion_usuarios")

def logout_view(request):
    logout(request)
    return redirect('login')

# ------ SISTEMA DE MONITOREO DE ERRORES (BÁSICO) ------
def _check_db_status():
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()

        return {
            "nombre": "Base de datos",
            "estado": "activo",
            "detalle": "Conexión correcta con MySQL.",
        }
    except Exception as e:
        return {
            "nombre": "Base de datos",
            "estado": "error",
            "detalle": str(e),
        }


def _check_openai_status():
    try:
        api_key = bool(getattr(settings, "OPENAI_API_KEY", None))
        if not api_key:
            return {
                "nombre": "IA / OpenAI",
                "estado": "error",
                "detalle": "No se encontró OPENAI_API_KEY en settings.",
            }

        return {
            "nombre": "IA / OpenAI",
            "estado": "activo",
            "detalle": "Cliente configurado correctamente.",
        }
    except Exception as e:
        return {
            "nombre": "IA / OpenAI",
            "estado": "error",
            "detalle": str(e),
        }


def _check_voice_status():
    try:
        ultimas_24h = timezone.now() - timedelta(hours=24)

        total = OrdenVoz.objects.filter(creado__gte=ultimas_24h).count()
        no_entendidos = OrdenVoz.objects.filter(
            creado__gte=ultimas_24h,
            intent="no_entendido"
        ).count()

        fuera_tema = OrdenVoz.objects.filter(
            creado__gte=ultimas_24h,
            intent="fuera_de_tema"
        ).count()

        estado = "activo"
        if total == 0:
            estado = "advertencia"

        return {
            "nombre": "Reconocimiento de voz",
            "estado": estado,
            "detalle": "Monitoreo de órdenes de voz recientes.",
            "total_24h": total,
            "no_entendidos": no_entendidos,
            "fuera_de_tema": fuera_tema,
        }
    except Exception as e:
        return {
            "nombre": "Reconocimiento de voz",
            "estado": "error",
            "detalle": str(e),
        }


def _check_scanner_status():
    try:
        ultimas_24h = timezone.now() - timedelta(hours=24)

        capturas = CapturaTemporal.objects.filter(creado__gte=ultimas_24h).count()
        analizadas = CapturaTemporal.objects.filter(
            creado__gte=ultimas_24h,
            estado="analizado"
        ).count()

        reconocidos = MedicamentoReconocido.objects.filter(creado__gte=ultimas_24h).count()

        estado = "activo"
        if capturas > 0 and analizadas == 0:
            estado = "advertencia"

        return {
            "nombre": "Escáner de medicamentos",
            "estado": estado,
            "detalle": "Estado del flujo de capturas y análisis.",
            "capturas_24h": capturas,
            "analizadas_24h": analizadas,
            "reconocidos_24h": reconocidos,
        }
    except Exception as e:
        return {
            "nombre": "Escáner de medicamentos",
            "estado": "error",
            "detalle": str(e),
        }


def _check_alarm_status():
    try:
        activas = Alarma.objects.filter(activa=True).count()
        entregadas = Alarma.objects.filter(entregada=True).count()

        ultimas_24h = timezone.now() - timedelta(hours=24)
        disparadas = Alarma.objects.filter(disparada_at__gte=ultimas_24h).count()

        estado = "activo"

        return {
            "nombre": "Sistema de alarmas",
            "estado": estado,
            "detalle": "Alarmas activas y recientes.",
            "activas": activas,
            "entregadas": entregadas,
            "disparadas_24h": disparadas,
        }
    except Exception as e:
        return {
            "nombre": "Sistema de alarmas",
            "estado": "error",
            "detalle": str(e),
        }


def _check_push_status():
    try:
        total_subs = PushSubscription.objects.count()

        if webpush is None:
            return {
                "nombre": "Notificaciones push",
                "estado": "advertencia",
                "detalle": "PyWebPush no está disponible en este entorno.",
                "suscripciones": total_subs,
            }

        return {
            "nombre": "Notificaciones push",
            "estado": "activo",
            "detalle": "Servicio push disponible.",
            "suscripciones": total_subs,
        }
    except Exception as e:
        return {
            "nombre": "Notificaciones push",
            "estado": "error",
            "detalle": str(e),
        }
    

# ------- MONITOREO -------
@login_required
def monitoreo_sistema(request):
    ok, resp = _require_admin(request)
    if not ok:
        return JsonResponse({"ok": False, "error": "Acceso denegado."}, status=403)

    revision = timezone.localtime()

    servicios = [
        _check_db_status(),
        _check_openai_status(),
        _check_voice_status(),
        _check_scanner_status(),
        _check_alarm_status(),
        _check_push_status(),
    ]

    total_activos = sum(1 for s in servicios if s["estado"] == "activo")
    total_advertencias = sum(1 for s in servicios if s["estado"] == "advertencia")
    total_errores = sum(1 for s in servicios if s["estado"] == "error")

    if total_errores > 0:
        estado_general = "error"
        estado_general_label = "Error"
        estado_general_detalle = "Se detectaron fallas en uno o más módulos."
    elif total_advertencias > 0:
        estado_general = "advertencia"
        estado_general_label = "En revisión"
        estado_general_detalle = "Hay módulos con advertencias."
    else:
        estado_general = "activo"
        estado_general_label = "Activo"
        estado_general_detalle = "Sistema funcionando correctamente."

    mapa = {s["nombre"]: s for s in servicios}

    def get_servicio(nombre):
        return mapa.get(nombre, {"nombre": nombre, "estado": "error", "detalle": "Sin datos."})

    db_data = get_servicio("Base de datos")
    openai_data = get_servicio("IA / OpenAI")
    voz_data = get_servicio("Reconocimiento de voz")
    scanner_data = get_servicio("Escáner de medicamentos")
    alarmas_data = get_servicio("Sistema de alarmas")
    push_data = get_servicio("Notificaciones push")

    # --- DATOS PARA GRÁFICA 1: ESTADO DE MÓDULOS ---
    grafica_modulos = {
        "labels": ["Activos", "Advertencias", "Errores"],
        "values": [total_activos, total_advertencias, total_errores],
    }

    # --- DATOS PARA GRÁFICA 2: ACTIVIDAD DEL SISTEMA ---
    grafica_actividad = {
        "labels": ["Voz", "Escáner", "Alarmas", "Push"],
        "values": [
            int(voz_data.get("total_24h", 0) or 0),
            int(scanner_data.get("capturas_24h", 0) or 0),
            int(alarmas_data.get("disparadas_24h", 0) or 0),
            int(push_data.get("suscripciones", 0) or 0),
        ],
    }

    return JsonResponse({
        "ok": True,
        "revision": revision.strftime("%d/%m/%Y %H:%M"),
        "estado_general": estado_general,
        "estado_general_label": estado_general_label,
        "estado_general_detalle": estado_general_detalle,
        "total_activos": total_activos,
        "total_advertencias": total_advertencias,
        "total_errores": total_errores,
        "servicios": {
            "base_datos": db_data,
            "openai": openai_data,
            "voz": voz_data,
            "scanner": scanner_data,
            "alarmas": alarmas_data,
            "push": push_data,
        },
        "graficas": {
            "modulos": grafica_modulos,
            "actividad": grafica_actividad,
        }
    })

def _sincronizar_usuario_django_activo(nombre, correo, activo):
    """
    Busca el User de Django relacionado y actualiza su campo is_active.
    """
    try:
        user = None
        correo_norm = (correo or "").strip().lower()
        nombre_norm = (nombre or "").strip()

        if correo_norm:
            user = User.objects.filter(
                Q(username__iexact=correo_norm) | Q(email__iexact=correo_norm)
            ).first()

        if not user and nombre_norm:
            user = User.objects.filter(
                Q(first_name__iexact=nombre_norm) | Q(username__iexact=nombre_norm)
            ).first()

        if user:
            user.is_active = bool(activo)
            user.save(update_fields=["is_active"])
            print(f"✅ Django user sincronizado: {user.username} -> is_active={activo}")
        else:
            print(f"⚠️ No se encontró usuario Django para sincronizar: {nombre_norm} / {correo_norm}")

    except Exception as e:
        print(f"❌ Error sincronizando usuario Django: {e}")


