# DIGI F8748 Admin Recovery

```
 ____ ___ ____ ___
|  _ \_ _/ ___|_ _|
| | | | | |  _ | |
| |_| | | |_| || |
|____/___\____|___|
  ZTE F8748 (Digi) · ADMIN RECOVERY
```

**El recuperador de la contraseña de administrador de tu router DIGI
F8748. Si estás aquí, es que la has perdido. La recuperamos en unos
minutos — sin instalar nada y sin tocar tu configuración.**

v0.0.2 · macOS (Apple Silicon) · Linux x64/ARM64 · Windows 10/11

---

## El problema que resuelve

Tu operador te instala un router DIGI con router ZTE F8748 y la contraseña
de administrador **se ha perdido**: no la apuntaste, venía en una pegatina
gastada, te dieron la de usuario o directamente nadie te la dijo. Sin ella
no puedes abrir puertos, cambiar la VLAN de la TV, ajustar el Wi-Fi a fondo,
revisar dispositivos conectados o gestionar tu propia red.

**Si estás aquí, es que la has perdido. Este producto la recupera de forma
segura, directamente desde el router.**

## Cómo funciona (en 30 segundos)

El F8748 guarda las credenciales de administrador **dentro de su propia
memoria flash** y trae de serie una interfaz de diagnóstico de fábrica.
DIGI F8748 Admin Recovery utiliza esa interfaz, paso a paso, para que **el
propio router muestre** el usuario y la contraseña que ya tiene almacenados.
Nada se adivina, nada se fuerza: se lee.

## Por qué es seguro

| ✔ | Garantía |
|---|---|
| **Cero instalación en el router** | No se toca el firmware, ni el software, ni la configuración. No se cambia ninguna contraseña. |
| **Cero instalación en tu equipo** | La edición script no deja nada persistente. Los ficheros temporales se borran solos al terminar. |
| **Sin cambios de configuración** | No se altera ningún ajuste, cuenta ni firmware. El proceso activa temporalmente el diagnóstico de fábrica ya presente (cambio de estado reversible) y **lee** zonas protegidas de la flash. |
| **Se desactiva solo** | El acceso temporal de diagnóstico se cierra automáticamente al final, incluso si algo falla. |
| **Paso a paso** | Cada fase es un comando independiente: puedes ver qué hace antes de hacerlo. |
| **Reversible al 100 %** | Si algo se interrumpe, apagar y encender el router devuelve todo a la normalidad. |

> **Uso responsable:** herramienta pensada para recuperar el acceso a routers
> propios o autorizados explícitamente. Úsala bajo tu propia responsabilidad.

## Descargas

Todo son **scripts**: no hay binarios que firmar, desbloquear ni actualizar.

| Fichero | Para |
|---|---|
| `DIGI-F8748-v0.0.1-shell-universal.zip` | **macOS y Linux — recomendado**: script + start.sh |
| `DIGI-F8748-v0.0.1-macos.zip` | macOS (Silicon e Intel): carpeta lista para usar |
| `DIGI-F8748-v0.0.1-linux.zip` | Linux x64/ARM64 (incl. Raspberry Pi): carpeta lista para usar |
| `DIGI-F8748-v0.0.1-windows.zip` | Windows 10/11: PowerShell nativo o Python |
| `DIGI-F8748-v0.0.1-source.zip` | Código fuente completo |

## Primeros pasos por sistema operativo

### macOS — Apple Silicon (M1/M2/M3/M4) e Intel

1. Descarga `DIGI-F8748-v0.0.1-shell-universal.zip` y descomprímelo.
2. En Terminal, dentro de la carpeta:

```bash
./start.sh info        # comprueba tu router, firmware y MACs
./start.sh handshake   # prueba de comunicación (no toca nada)
./start.sh recover     # recuperación completa de credenciales
```

`start.sh` comprueba las dependencias (curl, openssl, xxd, ssh, expect —
todas vienen de serie en macOS) y te pregunta si faltara alguna.
Funciona igual en Apple Silicon y en Intel.

### Linux (x64 y ARM64, incl. Raspberry Pi)

1. Descarga `DIGI-F8748-v0.0.1-shell-universal.zip` y descomprímelo.
2. En Terminal, dentro de la carpeta:

```bash
./start.sh info
./start.sh recover
```

Si falta alguna dependencia (curl, openssl, xxd, expect), `start.sh` te
dirá cuál y **te pedirá confirmación** para instalarla con el gestor de tu
distro (apt, dnf, pacman, zypper o apk). Necesitará tu contraseña de
administrador solo en ese caso.

### Windows 10/11

Descarga `DIGI-F8748-v0.0.1-windows.zip` y descomprímelo. Dos opciones:

- **PowerShell (recomendada, sin Python):** doble clic en
  `digi-f8748-ps1.bat`, o desde consola:
  `digi-f8748-ps1.bat info`, `digi-f8748-ps1.bat recover`...
  Para el volcado usa el módulo gratuito Posh-SSH; si no lo tienes, el
  script **te pregunta** antes de instalarlo.
- **Python:** instala Python 3.10+ desde python.org marcando
  *"Add python.exe to PATH"*, y haz doble clic en `digi-f8748.bat`
  (la primera vez prepara las dependencias él solo).

Si SmartScreen muestra un aviso la primera vez: **Más información →
Ejecutar de todas formas**.

### Cualquier sistema con Python 3.10+

Con el paquete fuente (`source.zip`):

```bash
pip install -r requirements.txt
python digi-f8748.py recover
```

También funciona el script `.sh` dentro de WSL (Ubuntu en Windows).

## Comandos

| Comando | Qué hace | Toca el router |
|---|---|---|
| `info` | Modelo, firmware y direcciones MAC de tu red | No |
| `handshake` | Comprueba la comunicación con el router | No |
| `arm` | Habilita el acceso de diagnóstico temporal | Sí (lo cierra al acabar) |
| `dump` | Extrae los datos cifrados de la flash del router | Sí (ídem) |
| `decrypt` | Descifra en local y muestra el usuario/contraseña | No |
| `verify` | Comprueba que el login de administrador funciona | No |
| `disarm` | Cierra el acceso de diagnóstico | Sí (lo cierra) |
| `recover` | Todo el proceso completo, de principio a fin | Sí (ídem) |

Opciones: `--host` (IP del router), `--web-user` / `--web-pass` (tu login
normal), `--router-mac` / `--client-mac`, `--out` (carpeta de salida),
`--keep-ssh` (no recomendado).

## Qué obtienes

Al terminar, el asistente muestra el **usuario y la contraseña del panel de
administración web** de tu router — los mismos que el fabricante almacena de
fábrica. Con ellos puedes:

- Abrir y redirigir puertos a tu gusto.
- Ajustar el Wi-Fi (canales, potencia, redes de invitados).
- Gestionar la VLAN de televisión/telefonía.
- Ver y controlar los dispositivos de tu red.
- Cambiar la contraseña de administrador por una tuya.

## Requisitos

- Estar conectado a la red del router (Wi-Fi o cable).
- El login web normal del router (habitualmente `user` / `user`).
- Varios minutos sin interrumpir el proceso.

## Solución de problemas

Todo lo siguiente son casos reales observados y documentados durante el
desarrollo y las pruebas de esta herramienta.

### El diagnóstico "no devuelve credenciales" (el más común)

**Síntoma:** `handshake` funciona (el router responde al reto), pero `arm` o
`recover` terminan con *"FactoryMode no devolvió credenciales"*.

**Causa:** el diagnóstico de fábrica del router se queda en un estado interno
atascado, normalmente tras varios intentos seguidos o pruebas repetidas.
No es un problema del equipo ni de la herramienta: ocurre igual con
implementaciones independientes del mismo protocolo.

**Solución (la que el propio fabricante documenta):**

1. Apaga y enciende el router (desenchúfalo 10 segundos).
2. Espera **2 minutos**.
3. Lanza **una sola pasada**: `./start.sh recover`

No encadenes intentos: cada ronda de reintentos empeora el atasco.

### Diagnóstico rápido del estado del router

```bash
# ¿El login web está bloqueado por intentos fallidos?
curl -s "http://192.168.1.1/?_type=loginData&_tag=login_entry"
#   → "lockingTime":0 = sin bloqueo; un número > 0 = espera o reinicia

# ¿Quedó un SSH de fábrica abierto de una ejecución interrumpida?
nc -z 192.168.1.1 22 && echo "ABIERTO — ejecuta disarm o reinicia" || echo "cerrado"

# ¿El router responde al reto del diagnóstico? (no toca nada)
./start.sh handshake
```

Si el puerto 22 quedó abierto y `disarm` no responde, reinicia el router:
el acceso temporal desaparece con el reinicio.

### Si tras un reinicio limpio sigue fallando

Apagaste el router, esperaste los 2 minutos e `arm` sigue rechazando la
prueba. Entonces hay dos posibilidades:

1. **El firmware cambió** (los operadores auto-actualizan de noche). Si ZTE
   o el operador han parcheado el comportamiento que esta herramienta usa,
   la vía de recuperación puede haber desaparecido — y en ese caso la
   divulgación ya ha cumplido su función. Compara tu versión de firmware
   (`./start.sh info`) con la de cuando funcionó.
2. **Las MACs no coinciden**: si tu equipo rotó su dirección Wi-Fi privada
   (macOS lo hace periódicamente) o cambiaste de red, la prueba de MACs no
   coincidirá. Verifica la MAC que el router muestra en su lista de
   dispositivos y pásala con `--client-mac aa:bb:cc:dd:ee:ff`.

En cualquiera de los casos, abre un issue en el repositorio con la salida de
`./start.sh info` y de `./start.sh handshake` (sin datos sensibles): el
hallazgo ya está notificado a ZTE PSIRT y esta información ayuda a
documentar qué versiones están afectadas.

**Importante:** si ya recuperaste tus credenciales con una versión anterior,
guárdalas — no dependen de que esta herramienta siga funcionando.

### La confirmación de autorización

Los comandos `arm`, `dump` y `recover` piden escribir **SI** (acepta
mayúsculas, minúsculas o mezcla). Esa confirmación es obligatoria: es la
garantía de que el equipo es tuyo o estás autorizado. Para entornos
automatizados existe el flag `-y`, que la omite bajo tu responsabilidad.

### Si los ficheros "se revierten solos" (macOS: carpeta Descargas)

Si mantienes el proyecto en `~/Downloads`, macOS y las copias de seguridad
(Time Machine) pueden **restaurar versiones antiguas encima de las nuevas** —
detectamos este caso real: scripts revertidos a versiones de horas atrás sin
motivo aparente. Recomendaciones:

- Mueve el proyecto a una carpeta estable (p. ej. `~/Proyectos/`).
- Antes de ejecutar, verifica que tu copia es la buena:
  `grep -c require_auth digi-f8748.sh` debe devolver **2** (edición shell).

### Consideraciones legales

En España el router suele ser **propiedad del operador** y la investigación
sobre productos de terceros puede tener implicaciones según tu contrato y
las circunstancias. La herramienta exige confirmar que eres el propietario o
que tienes autorización expresa. Si tienes dudas sobre tu caso concreto,
consulta con un profesional legal especializado.

## Preguntas frecuentes

**¿Se cambia la contraseña del router?**
No. La que se recupera es la que ya tiene almacenada el router de fábrica.
Después puedes cambiarla tú desde el panel.

**¿Se modifica la configuración o se pierde Internet?**
No. El proceso no modifica la configuración: se limita a activar temporalmente
el diagnóstico de fábrica ya presente y a leer datos del equipo. Al terminar no
queda ningún acceso abierto.

**¿Sirve para cualquier router?**
Está específica para la familia ZTE F8748 de DIGI España.

**¿Deja huella o acceso permanente?**
No. No se instala nada en el router ni en el equipo, y el acceso de
diagnóstico se cierra solo al terminar.

**¿Y si se corta a mitad de proceso?**
Apaga y enciende el router, espera un par de minutos y vuelve a intentarlo
una vez. Todo vuelve a la normalidad por sí solo.

## Para desarrolladores

En `DIGI-F8748-v0.0.1-source.zip` tienes el código fuente completo — bash,
PowerShell y Python — para auditar cada línea antes de ejecutar nada. No hay
binarios: todo lo que se ejecuta es lo que lees.

## Divulgación responsable

Este hallazgo ha sido **puesto en conocimiento del equipo de seguridad de ZTE
(ZTE PSIRT) por correo electrónico** el 22 de septiembre de 2026, incluyendo
la descripción del comportamiento, los pasos de reproducción y una referencia
a este repositorio, con la intención de ayudar a mejorar la seguridad del
producto. El texto completo del reporte está en
[DISCLOSURE.md](DISCLOSURE.md). A la espera de acuse de recibo y número de
seguimiento del caso.

## Divulgación responsable

Este hallazgo ha sido **puesto en conocimiento del equipo de seguridad de ZTE
(ZTE PSIRT) por correo electrónico** el 22 de septiembre de 2026, incluyendo
la descripción del comportamiento, los pasos de reproducción y una referencia
a este repositorio, con la intención de ayudar a mejorar la seguridad del
producto. El texto completo del reporte enviado está en
[DISCLOSURE.md](DISCLOSURE.md), a la espera de acuse de recibo y número de
seguimiento del caso.

## Uso autorizado y consideraciones legales

Los comandos que activan el diagnóstico de fábrica **exigen una confirmación
explícita** (escribir `SI`) de que eres el propietario del router o que tienes
autorización expresa para gestionarlo. Sin esa confirmación — o sin el flag
`-y`, para entornos automatizados — la herramienta no continúa.

Ten en cuenta que en España el router suele ser **propiedad del operador** y
que la investigación sobre productos de terceros puede tener implicaciones
legales según tu contrato y las circunstancias. Si tienes dudas sobre tu caso
concreto, **consulta con un profesional legal** especializado antes de
utilizar la herramienta.

## Aviso legal

Software proporcionado "tal cual", sin garantía de ningún tipo. Los autores
no se hacen responsables de daños, pérdida de configuración o cualquier otro
perjuicio derivado de su uso. Su finalidad es exclusivamente la recuperación
del acceso de administrador en equipos propios o autorizados.

---

**Autor:** [686f6c61](https://github.com/686f6c61) ·
**Repo:** [github.com/686f6c61/DIGI-F8748](https://github.com/686f6c61/DIGI-F8748)
