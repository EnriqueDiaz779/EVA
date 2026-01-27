import os
import json
from openai import OpenAI
from dotenv import load_dotenv

# Cargar variables del entorno (.env)
load_dotenv()

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

def preguntar_openai(texto: str) -> dict:
    """
    Envía la orden de voz del usuario a OpenAI y obtiene una respuesta estructurada.
    Si detecta una orden de alarma, devuelve meta.hora y meta.mensaje.
    """
    try:
        prompt = f"""
        Eres un asistente de voz llamado EVA que ayuda a adultos mayores.
        Tu tarea es interpretar órdenes de voz y devolver respuestas en formato JSON ESTRICTO.
        Responde SIEMPRE en español claro, cálido y breve (máximo 2 oraciones).

        Analiza esta frase del usuario:
        "{texto}"

        Determina si el usuario quiere crear una alarma. Ejemplos:
        - "pon una alarma a las 8:30"
        - "activa alarma a las nueve y media con mensaje tomar medicina"
        - "despiértame a las 7:15"
        - "recuerdame a las diez con mensaje tomar agua"

        Si detectas una alarma:
        - extrae la hora en formato 24h HH:MM (por ejemplo "08:30")
        - extrae el mensaje si lo dice, o usa un texto por defecto como "¡Es hora de tu alarma!"
        - devuelve intent = "alarma"
        - incluye en "meta" los campos "hora" y "mensaje"

        Si NO es una alarma, intenta clasificar la intención general y da una respuesta amable.
        Usa este formato JSON EXACTO (sin texto fuera del JSON):

        {{
          "intent": "alarma" o "desconocido" o "otro_tipo",
          "respuesta": "texto breve y amable que diría EVA",
          "confidence": 0.9,
          "meta": {{
              "hora": "HH:MM" o "",
              "mensaje": "texto del mensaje o vacío"
          }}
        }}
        """

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "Eres EVA, un asistente de voz cálido y paciente para adultos mayores."},
                {"role": "user", "content": prompt}
            ],
            temperature=0.5
        )

        raw = response.choices[0].message.content.strip()

        # Intentar convertir a JSON limpio
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            # Si no es JSON válido, crear estructura base
            data = {
                "intent": "desconocido",
                "respuesta": raw,
                "confidence": 0.7,
                "meta": {}
            }

        # Retornar formato consistente para Django
        return {
            "intent": data.get("intent", "desconocido"),
            "respuesta": data.get("respuesta", raw),
            "confidence": data.get("confidence", 0.7),
            "meta": data.get("meta", {}),
            "error": None
        }

    except Exception as e:
        print("❌ Error al conectar con OpenAI:", e)
        return {
            "intent": "error",
            "respuesta": "Ocurrió un problema al generar la respuesta. Inténtalo más tarde.",
            "confidence": 0.0,
            "meta": {},
            "error": str(e)
        }
