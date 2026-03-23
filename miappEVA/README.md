# miappEVA

Configuracion base para desplegar EVA en Render usando una base de datos ya alojada en Railway.

## Backend Django en Render

El proyecto ya quedo preparado para:

- leer `SECRET_KEY`, hosts, CSRF y tokens desde variables de entorno
- conectarse a Railway usando `DATABASE_URL` o variables `DB_*`
- servir archivos estaticos con `WhiteNoise`
- arrancar con `gunicorn` en el puerto que Render asigna

Archivos agregados para despliegue:

- `render.yaml`
- `build.sh`
- `.env.example`

Variables importantes en Render:

- `DJANGO_DEBUG=false`
- `DJANGO_ALLOWED_HOSTS=tu-servicio.onrender.com`
- `DJANGO_CSRF_TRUSTED_ORIGINS=https://tu-servicio.onrender.com`
- `DATABASE_URL=<url de Railway>`
- `OPENAI_API_KEY=<si usas OpenAI>`
- `MAPBOX_TOKEN_PUBLIC=<si usas mapa>`
- `VAPID_PUBLIC_KEY=<si usas push web>`
- `VAPID_PRIVATE_KEY=<si usas push web>`

## Despliegue sugerido

1. Sube este repositorio a GitHub.
2. En Render crea un `Web Service` desde el repo.
3. Si Render detecta `render.yaml`, acepta esa configuracion.
4. En variables de entorno pega la URL de Railway y completa las llaves faltantes.
5. Despliega y revisa que el login cargue y que `python manage.py migrate` termine bien en el arranque.

## App movil y app web Flutter

La app Flutter ya no apunta a una IP local fija. Ahora usa `--dart-define=API_BASE_URL=...`.

Ejemplos:

```bash
flutter run --dart-define=API_BASE_URL=https://tu-servicio.onrender.com
flutter build apk --dart-define=API_BASE_URL=https://tu-servicio.onrender.com
flutter build web --dart-define=API_BASE_URL=https://tu-servicio.onrender.com
```

La configuracion compartida esta en `eva_mobile/lib/config/app_config.dart`.

## Nota importante sobre media

Render no guarda de forma persistente los archivos subidos al filesystem del contenedor. Las imagenes en `media/` pueden perderse despues de reinicios o nuevos deploys. Si las capturas o recetas deben conservarse, conviene mover `MEDIA_ROOT` a un disco persistente o a almacenamiento externo tipo S3 o Cloudinary.
