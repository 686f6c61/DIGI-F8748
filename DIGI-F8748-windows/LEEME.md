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

v1.0.0 · macOS (Apple Silicon) · Linux x64/ARM64 · Windows 10/11

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
| **Solo lectura** | Se leen zonas de la flash del router. Nunca se escribe en la configuración. |
| **Se desactiva solo** | El acceso temporal de diagnóstico se cierra automáticamente al final, incluso si algo falla. |
| **Paso a paso** | Cada fase es un comando independiente: puedes ver qué hace antes de hacerlo. |
| **Reversible al 100 %** | Si algo se interrumpe, apagar y encender el router devuelve todo a la normalidad. |

> **Uso responsable:** herramienta pensada para recuperar el acceso a routers
> propios o autorizados explícitamente. Úsala bajo tu propia responsabilidad.

## Descargas

Todo son **scripts**: no hay binarios que firmar, desbloquear ni actualizar.

| Fichero | Para |
|---|---|
| `DIGI-F8748-v1.0.0-shell-universal.zip` | **macOS y Linux — recomendado**: script + start.sh |
| `DIGI-F8748-v1.0.0-macos.zip` | macOS (Silicon e Intel): carpeta lista para usar |
| `DIGI-F8748-v1.0.0-linux.zip` | Linux x64/ARM64 (incl. Raspberry Pi): carpeta lista para usar |
| `DIGI-F8748-v1.0.0-windows.zip` | Windows 10/11: PowerShell nativo o Python |
| `DIGI-F8748-v1.0.0-source.zip` | Código fuente completo |

## Primeros pasos por sistema operativo

### macOS — Apple Silicon (M1/M2/M3/M4) e Intel

1. Descarga `DIGI-F8748-v1.0.0-shell-universal.zip` y descomprímelo.
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

1. Descarga `DIGI-F8748-v1.0.0-shell-universal.zip` y descomprímelo.
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

Descarga `DIGI-F8748-v1.0.0-windows.zip` y descomprímelo. Dos opciones:

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

## Preguntas frecuentes

**¿Se cambia la contraseña del router?**
No. La que se recupera es la que ya tiene almacenada el router de fábrica.
Después puedes cambiarla tú desde el panel.

**¿Se modifica la configuración o se pierde Internet?**
No. El proceso es de solo lectura sobre la configuración. Al terminar no
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

En `DIGI-F8748-v1.0.0-source.zip` tienes el código fuente completo — bash,
PowerShell y Python — para auditar cada línea antes de ejecutar nada. No hay
binarios: todo lo que se ejecuta es lo que lees.

## Aviso legal

Software proporcionado "tal cual", sin garantía de ningún tipo. Los autores
no se hacen responsables de daños, pérdida de configuración o cualquier otro
perjuicio derivado de su uso. Su finalidad es exclusivamente la recuperación
del acceso de administrador en equipos propios o autorizados.
