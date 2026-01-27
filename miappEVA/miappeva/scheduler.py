import threading
import time
from datetime import date, datetime, timedelta
from django.utils import timezone
from django.db import transaction
from django.contrib.auth import get_user_model
from .models import Alarma
import requests
from django.utils.timezone import make_aware, is_aware

User = get_user_model()

# ==========================================================
# 🔔 LÓGICA PRINCIPAL
# ==========================================================
def _should_fire(alarma, ahora):
    """Devuelve True si la alarma debe dispararse en este minuto."""
    try:
        la_fecha = alarma.fecha or date.today()

        # Si tiene días recurrentes
        if alarma.dias:
            hoy_str = ahora.strftime("%a").lower()[:3]  # lun, mar, etc.
            if hoy_str not in [d.strip().lower()[:3] for d in alarma.dias.split(",")]:
                return False

        # Si la alarma es de otro día
        if alarma.fecha and la_fecha != ahora.date():
            return False

        # Asegurar aware
        base_dt = datetime.combine(la_fecha, alarma.hora)
        if not is_aware(base_dt):
            base_dt = make_aware(base_dt, timezone.get_current_timezone())

        diferencia = abs((base_dt - ahora).total_seconds())
        return diferencia <= 30  # ✅ solo dentro de ±30 s
    except Exception as e:
        print(f"Error en _should_fire: {e}")
        return False


# ==========================================================
# 📩 ENVÍO DE NOTIFICACIONES
# ==========================================================
def _notificar_alarma(a):
    """Envía una notificación al Service Worker."""
    try:
        payload = {
            "type": "SHOW_NOTIFICATION",
            "title": "⏰ EVA",
            "body": a.mensaje or "¡Es hora de tu medicamento!",
            "tag": f"alarma-{a.id}",
            "id": a.id,
        }
        requests.post("http://127.0.0.1:8000/api/notify/", json=payload, timeout=3)
        print(f"📨 Notificación enviada al Service Worker para la alarma #{a.id}")
    except requests.exceptions.RequestException as e:
        print(f"⚠️ No se pudo enviar notificación (Service Worker no activo): {e}")


# ==========================================================
# ♻️ REVISIÓN DE ALARMAS OMITIDAS (REPROGRAMADAS)
# ==========================================================
def _reprogramar_omitidas():
    """Dispara alarmas reprogramadas u omitidas cuando llega su nueva hora."""
    ahora = timezone.localtime()
    qs = Alarma.objects.filter(activa=True, entregada=False)

    for a in qs:
        base_dt = datetime.combine(ahora.date(), a.hora)
        if not is_aware(base_dt):
            base_dt = make_aware(base_dt, timezone.get_current_timezone())

        # ⏱️ Si llegó su nueva hora y aún no se disparó
        if a.disparada_at is None and abs((base_dt - ahora).total_seconds()) <= 30:
            print(f"🔔 Disparando alarma reprogramada #{a.id}: {a.hora}")
            with transaction.atomic():
                a.disparada_at = timezone.now()
                a.save(update_fields=["disparada_at"])
            _notificar_alarma(a)

# ==========================================================
# 🔁 BUCLE PRINCIPAL DEL SCHEDULER (DESACTIVADO TEMPORALMENTE)
# ==========================================================
def _loop():
    print("🕓 Scheduler EVA: iniciado (pero desactivado temporalmente).")
    """
    while True:
        try:
            ahora = timezone.localtime()

            # 1️⃣ Revisar alarmas activas
            qs = Alarma.objects.filter(activa=True, entregada=False)
            for a in qs:
                # ⛔ Si ya sonó hace <90 s, no volver a disparar
                if a.disparada_at and (ahora - a.disparada_at).total_seconds() < 90:
                    continue

                if _should_fire(a, ahora):
                    print(f"🔔 Disparando alarma #{a.id}: {a.hora} - {a.mensaje}")

                    with transaction.atomic():
                        a.disparada_at = timezone.now()
                        a.save(update_fields=["disparada_at"])

                    _notificar_alarma(a)

            # 2️⃣ Revisar reprogramadas
            _reprogramar_omitidas()

            time.sleep(10)

        except Exception as e:
            print("⚠️ Error en scheduler:", e)
            time.sleep(5)
    """


# ==========================================================
# 🚀 INICIO DEL HILO (AppConfig.ready)
# ==========================================================
def start_scheduler():
    """Lanza el hilo en segundo plano cuando inicia Django."""
    t = threading.Thread(target=_loop, daemon=True)
    t.start()
