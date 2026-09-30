# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## v0.0.4 — 2026-09-30

### Corregido
- **Clave del canal webFac**: la clave AES real es el segmento del pool de
  claves **XOR 0xA5 byte a byte** (`KEY_POOL[idx:idx+24] ^ 0xA5`, como hace el
  `httpd` del firmware). Sin este XOR el router no puede descifrir las
  peticiones y cierra la conexión: era la causa de que `arm`/`dump`/`recover`
  fallaran siempre con "FactoryMode no devolvió credenciales" en las tres
  ediciones. Corregido en bash, Python y PowerShell.
- **Desarme**: en este firmware `FactoryMode.gch?mode=0` **no desarma** —
  devuelve credenciales nuevas (re-arma) y el puerto 22 queda abierto. El
  desarme correcto es `FactoryMode.gch?close` (verificado: el puerto 22 se
  cierra). Corregido en las tres ediciones.
- **Shell de fábrica solo acepta comandos simples**: deniega (`/bin/sh:
  Access Denied`) cualquier línea compuesta (`;`) y también `echo`. La edición
  bash ya no usa marcadores `echo`; secciona el log por el eco del propio
  comando y el prompt. Además el `hexdump` remoto emite con saltos de línea
  (`16/1`), porque el `awk` de macOS se atraganta con líneas gigantes.
- **Cripto del paramtag**: el esquema real es **AES-256-CBC** con la clave
  `sha256(material)` completa y **IV = primeros 16 bytes del digest**
  (antes: AES-128 con mitades del digest), y el valor descifrado es un
  *hex-string* que se decodifica a ASCII. Corregido en las tres ediciones.
- **Lectura del paramtag**: está en el fichero montado `/tagparam/paramtag`
  (jffs2 sobre mtd3), no en crudo en los mtd; se lee con reintentos y
  `wc -c` de calentamiento (la primera lectura tras arrancar puede tardar).
- **`verify` en la edición bash** ahora conserva las cookies de sesión entre
  peticiones (antes el login no se confirmaba aunque fuera correcto).
- **Portabilidad macOS**: el `sed` de BSD no soporta `\+` en expresiones
  básicas (la extracción del `vid` fallaba en silencio); patrones reescritos.
  Añadido `LC_ALL=C` para operaciones de bytes seguras.
- `decrypt` tolera la ausencia de `paramtag.bin` (usa entonces las
  credenciales de fábrica del contenedor hardcode).

### Verificado
- Recuperación **completa y confirmada** en un ZTE F8748 real (XGS-PON,
  BusyBox 2024-07-30): prueba de MACs aceptada, shell root (`Uid: 0`),
  volcado de seed/oss/paramtag, desarme con puerto 22 cerrado, descifrado
  offline y **login de administrador confirmado en la web (curRight=1)**.

## v0.0.3 — 2026-09-30

### Corregido
- **Edición bash**: tras `dump`, el desarme del SSH de fábrica se enviaba sin la
  prueba de MACs ni el login, de modo que el router lo ignoraba en silencio y el
  acceso temporal quedaba activo mientras el script decía "desarmado". Ahora el
  desarme usa la secuencia completa.
- **Edición Python**: `arm`, `dump` y `recover` fallaban siempre con
  `NameError: name 'args' is not defined` (una regresión del endurecimiento de
  la v0.0.2); `decrypt` fallaba con `AttributeError: 'Namespace' object has no
  attribute 'host'`. Ambas rutas probadas de principio a fin.
- **Edición PowerShell**: la respuesta de `FactoryMode` se descifraba con AES-CBC
  e IV a cero en lugar de AES-ECB; solo el primer bloque de 16 bytes se
  descifraba bien y las credenciales que cruzaban un límite de bloque salían
  corruptas. Las confirmaciones volvían a exigir "SI" exacto; ahora aceptan
  "si" en cualquier variante, como las otras ediciones.
- `start.sh` y el CLI bash comprueban ahora `python3` como dependencia (se usa
  en `dump`/`decrypt`); antes su ausencia producía un críptico "credenciales
  incompletas".

### Verificado
- Prueba de extremo a extremo en Ubuntu 24.04 real contra un F8748: `start.sh`
  (detección e instalación de dependencias vía apt), `info`, `handshake` (reto
  webFac real, prueba de 22 palabras idéntica en las ediciones bash y Python),
  `decrypt` con volcado sintético y `verify` (rechazo correcto de credenciales
  falsas). El paso `arm` depende del estado del router: si el diagnóstico de
  fábrica no responde, desenchúfalo 10 segundos, espera 2 minutos e inténtalo
  una vez (ver solución de problemas).

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
