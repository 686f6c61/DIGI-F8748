# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## v0.0.2 — 2026-09-23

### Corregido
- La confirmación de autorización ahora acepta "si", "Si" o "SI" (antes solo
  se aceptaba "SI" exacto y los usuarios que escribían en minúsculas veían
  "cancelado").
- `.gitignore` endurecido en el repositorio: nunca se subirán volcados del
  router (`digi-dump/`, `*.seed`, `oss.bin`, `paramtag.bin`,
  `boardtype.txt`), credenciales ni ficheros temporales del proceso.
- Los comandos `dump` y `recover` avisan y exigen confirmación aparte si la
  carpeta de salida está dentro de un repositorio git.

### Añadido
- Sección "Solución de problemas" en la documentación, con los casos reales
  observados (diagnóstico atascado, bloqueo del login web, SSH residual,
  ficheros que se revierten en `~/Downloads`) y sus soluciones.
- Página del proyecto lista para GitHub Pages (`index.html`).
- `CHANGELOG.md` (este fichero).

### Documentado
- Divulgación responsable: el hallazgo fue notificado por correo al equipo
  **ZTE PSIRT** el 2026-09-22 (`DISCLOSURE.md`), incluyendo descripción,
  pasos de reproducción y referencia al repositorio.
- Aviso sobre la propiedad del equipo por parte del operador y la
  recomendación de consultar con un profesional legal en caso de duda.

## v0.0.1 — 2026-09-22

### Añadido
- Primera versión pública: ediciones bash (macOS/Linux), PowerShell y Python
  (Windows), flujo completo `info → handshake → arm → dump → decrypt →
  verify → disarm`, confirmación de autorización obligatoria y
  auto-desactivación del acceso temporal al terminar.
