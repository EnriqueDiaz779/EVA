import os
import json
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


def preguntar_openai(texto: str) -> dict:
    """
    Interpreta órdenes de voz del usuario y devuelve JSON estructurado.
    Ahora soporta:
    - hora
    - mensaje
    - fecha específica
    - fecha relativa (hoy / mañana)
    - días de la semana
    """
    try:
        prompt = f"""
Eres un asistente de voz llamado EVA que ayuda a adultos mayores.
Tu tarea es interpretar órdenes de voz y devolver respuestas en formato JSON ESTRICTO.
Responde SIEMPRE en español claro, cálido y breve.

Analiza esta frase del usuario:
"{texto}"

Debes detectar si el usuario quiere crear una alarma.

Ejemplos:
- "pon una alarma a las 8:30"
- "despiértame a las 7:15"
- "recuérdame tomar agua a las 10"
- "pon una alarma mañana a las 9 para mi medicina"
- "pon una alarma el lunes a las 8"
- "pon una alarma los lunes y miércoles a las 7 para la pastilla"
- "recuérdame los martes y jueves a las 20:00 tomar mi medicamento"

Reglas:
1. Si detectas una alarma, devuelve intent = "alarma".
2. Extrae la hora en formato 24 horas HH:MM.
3. Extrae el mensaje si existe. Si no existe, usa "¡Es hora de tu alarma!".
4. Si el usuario dice una fecha exacta, llena "fecha" con formato YYYY-MM-DD si se puede inferir claramente. Si no se puede inferir el año, deja vacío.
5. Si el usuario dice "hoy" o "mañana", llena "fecha_relativa" con "hoy" o "mañana".
6. Si el usuario menciona días de repetición, llena "dias_semana" con números:
   - 1 = lunes
   - 2 = martes
   - 3 = miércoles
   - 4 = jueves
   - 5 = viernes
   - 6 = sábado
   - 7 = domingo
7. Si no menciona días, devuelve lista vacía.
8. Si no es una alarma, clasifica la intención general y responde amable.
9. Devuelve SOLO JSON válido, sin texto fuera del JSON.

Formato JSON EXACTO:

{{
  "intent": "alarma" o "desconocido" o "otro_tipo",
  "respuesta": "texto breve y amable que diría EVA",
  "confidence": 0.9,
  "meta": {{
    "hora": "HH:MM" o "",
    "mensaje": "texto del mensaje o vacío",
    "fecha": "YYYY-MM-DD" o "",
    "fecha_relativa": "hoy" o "mañana" o "",
    "dias_semana": [1,2,3] o []
  }}
}}
"""

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Eres EVA, un asistente de voz cálido y paciente para adultos mayores. "
                        "Debes responder únicamente JSON válido."
                    ),
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.3,
        )

        raw = (response.choices[0].message.content or "").strip()

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            data = {
                "intent": "desconocido",
                "respuesta": raw if raw else "No entendí la instrucción.",
                "confidence": 0.7,
                "meta": {
                    "hora": "",
                    "mensaje": "",
                    "fecha": "",
                    "fecha_relativa": "",
                    "dias_semana": [],
                },
            }

        meta = data.get("meta", {})
        if not isinstance(meta, dict):
            meta = {}

        hora = str(meta.get("hora") or "").strip()
        mensaje = str(meta.get("mensaje") or "").strip()
        fecha = str(meta.get("fecha") or "").strip()
        fecha_relativa = str(meta.get("fecha_relativa") or "").strip().lower()
        dias_semana = meta.get("dias_semana") or []

        if not isinstance(dias_semana, list):
            dias_semana = []

        dias_limpios = []
        for d in dias_semana:
            try:
                n = int(d)
                if 1 <= n <= 7 and n not in dias_limpios:
                    dias_limpios.append(n)
            except Exception:
                pass

        return {
            "intent": data.get("intent", "desconocido"),
            "respuesta": data.get("respuesta", raw),
            "confidence": data.get("confidence", 0.7),
            "meta": {
                "hora": hora,
                "mensaje": mensaje,
                "fecha": fecha,
                "fecha_relativa": fecha_relativa if fecha_relativa in ("hoy", "mañana", "manana") else "",
                "dias_semana": dias_limpios,
            },
            "error": None,
        }

    except Exception as e:
        print("❌ Error al conectar con OpenAI:", e)
        return {
            "intent": "error",
            "respuesta": "Ocurrió un problema al generar la respuesta. Inténtalo más tarde.",
            "confidence": 0.0,
            "meta": {
                "hora": "",
                "mensaje": "",
                "fecha": "",
                "fecha_relativa": "",
                "dias_semana": [],
            },
            "error": str(e),
        }