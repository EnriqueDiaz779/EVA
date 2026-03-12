from django.apps import AppConfig
import os
import sys


class MiappevaConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'miappeva'

    def ready(self):
        import miappeva.signals  # Importa los signals para crear perfiles automáticamente

class MiappevaConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'miappeva'

    def ready(self):
        """
        Inicia el scheduler de EVA una sola vez,
        evitando el doble arranque del servidor en modo desarrollo.
        """
        # Evita reinicios dobles por autoreload
        if os.environ.get('RUN_MAIN') != 'true' and 'gunicorn' not in " ".join(sys.argv).lower():
            return

        try:
            from .scheduler import start_scheduler
            start_scheduler()
            print("✅ Scheduler EVA iniciado desde AppConfig.ready()")
        except Exception as e:
            print(f"⚠️ Error al iniciar el scheduler EVA: {e}")
