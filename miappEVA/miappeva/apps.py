from django.apps import AppConfig
import os
import sys


class MiappevaConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "miappeva"

    def ready(self):
        import miappeva.signals

        run_scheduler = os.getenv("EVA_ENABLE_SCHEDULER", "").strip().lower() in {
            "1",
            "true",
            "yes",
            "on",
        }
        if not run_scheduler:
            return

        command_line = " ".join(sys.argv).lower()
        if os.environ.get("RUN_MAIN") != "true" and "gunicorn" not in command_line:
            return

        try:
            from .scheduler import start_scheduler

            start_scheduler()
            print("Scheduler EVA iniciado desde AppConfig.ready()")
        except Exception as exc:
            print(f"Error al iniciar el scheduler EVA: {exc}")
