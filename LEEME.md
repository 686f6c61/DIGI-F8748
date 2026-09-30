# DIGI F8748 Admin Recovery

```
 ____ ___ ____ ___
|  _ \_ _/ ___|_ _|
| | | | | |  _ | |
| |_| | | |_| || |
|____/___\____|___|
  ZTE F8748 (Digi) · ADMIN RECOVERY
```

**El recuperador de la contraseña de administrador de tu router DIGI F8748.
Si estás aquí, es que la has perdido.** Guía paso a paso más abajo.

v0.0.4 · macOS (Apple Silicon e Intel) · Linux x64/ARM64 · Windows 10/11

- Descargas: <https://github.com/686f6c61/DIGI-F8748/releases> (el zip de tu sistema)
- Web: <https://686f6c61.github.io/DIGI-F8748/>

---

## ¿Qué hace exactamente? (léelo una vez, es importante)

Tu router guarda la contraseña de administrador dentro de sí mismo, cifrada.
El fabricante dejó en el firmware una **interfaz de diagnóstico de fábrica** que
sabe mostrar esa contraseña: es la que usa el servicio técnico. Esta herramienta
habla con esa interfaz, paso a paso, y te muestra la contraseña que el propio
router tiene guardada.

Tres cosas que esta herramienta **NO** hace:

1. **No instala nada en tu equipo.** Son scripts de texto. Ni apps, ni
   binarios, ni drivers. Los temporales se borran al salir.
2. **No instala nada en el router.** No se toca el firmware ni la
   configuración. El modo de diagnóstico se activa solo mientras se lee la
   contraseña y se desactiva solo al terminar (y puedes comprobarlo: el puerto
   que abre se cierra).
3. **No fuerza nada.** Si el router no responde, la herramienta se para y te
   lo dice. No hay ataques ni reintentos agresivos.

**Solo uso autorizado:** úsala únicamente en tu propio router o en uno cuyo
propietario te dé permiso expreso. El hallazgo fue notificado responsablemente
a ZTE PSIRT por correo el 2026-09-22 (ver `DISCLOSURE.md`). Ante cualquier duda
legal, consulta a un profesional.

---

## Antes de empezar: 3 cosas

1. **Conecta tu ordenador al WiFi del router directamente** (o por cable).
   Si en tu casa hay un repetidor o mesh (Deco, extensor…), conéctate a la red
   WiFi **del router ZTE**, no a la del repetidor: la comprobación de seguridad
   del router compara la dirección MAC que él ve, y a través de un repetidor
   ve la del repetidor, no la tuya.
2. **Ten a mano la pegatina del router** (la de abajo). Si el programa te pide
   la "MAC del router", es la que pone `MAC:` en esa pegatina, con el formato
   `AA-BB-CC-DD-EE-FF`.
3. **Usuario web normal.** Por defecto es `user` / `user` (si lo cambiaste,
   usa el tuyo con `--web-user` y `--web-pass`).

¿Todo listo? Vamos.

---

## Paso 1 · Descarga y abre el programa (2 minutos)

1. Entra en <https://github.com/686f6c61/DIGI-F8748/releases> y descarga el
   zip de tu sistema:
   - **macOS y Linux (recomendado):** `DIGI-F8748-v…-shell-universal.zip`
   - **Windows:** `DIGI-F8748-v…-windows.zip`
2. Descomprime el zip (doble clic). Te quedará una carpeta con 2–3 archivos.
3. Abre una terminal **dentro de esa carpeta**:
   - **macOS:** clic derecho sobre la carpeta → *Servicios* → *Nueva ventana
     de terminal en la carpeta*. (O abre Terminal y arrastra la carpeta encima.)
   - **Linux:** clic derecho → *Abrir en terminal*.
   - **Windows:** en el Explorador, escribe `powershell` en la barra de
     dirección de esa carpeta y pulsa Enter.

> En Windows, si al ejecutar el script aparece una política de ejecución,
> lanza primero: `Set-ExecutionPolicy -Scope Process Bypass`

## Paso 2 · Comprueba las dependencias (1 minuto)

macOS/Linux:

```bash
./start.sh info
```

Windows: `.\digi-f8748.ps1 info`

**Qué verás:** una lista tipo `[+] curl: OK`, `[+] openssl: OK`… y al final
los datos de tu router.

- Si falta algo (`[!] expect: NO está`), el propio programa **te pregunta** si
  puede instalarlo (con tu permiso y con el gestor de paquetes de tu sistema).
  Responde `s`.
- Si dice que no hay terminal interactiva, usa `./start.sh -y info`.

## Paso 3 · Identifica tu router (30 segundos)

En la salida del paso anterior busca estas dos líneas:

```
[*] Router MAC (br0): aa:bb:cc:dd:ee:ff
[*] Client MAC:       aa:bb:cc:dd:ee:01
```

- **Router MAC**: es la de la pegatina del router. Compárala.
- **Client MAC**: la de TU ordenador tal y como la ve el router. Si en macOS
  aparece `(no visible…)`, no pasa nada: se te pedirá más adelante y podrás
  escribirla a mano (Ajustes del sistema → Wi-Fi → Detalles; o la que muestra
  el router en su lista de dispositivos conectados).

## Paso 4 · Recupera tu contraseña (el paso bueno)

macOS/Linux:

```bash
./digi-f8748.sh recover
```

Windows: `.\digi-f8748.ps1 recover`

**Primero te pedirá confirmación:**

```
Vas a ejecutar la recuperación completa (recover) en 192.168.1.1.
Confirma que eres el propietario del router o que tienes autorización…
Escribe SI para continuar:
```

Escribe `SI` (vale también `si` o `Si`) y pulsa Enter. **Sin ese SI no hace
nada.**

**Qué va pasando** (tarda entre 5 y 20 minutos; verás el progreso):

1. `[*] Router MAC … / Client MAC …` — comprueba qué equipo eres. Si no las
   puede deducir, te las pide: la del router, la de la pegatina; la tuya, la
   de tu tarjeta WiFi.
2. `[*] Ciclo factory SSH 1/3…` — enciende el canal de diagnóstico de fábrica.
   Si un ciclo falla, reintenta solo hasta 3 veces.
3. `[+] factory SSH armado — user: XXXX pass: YYYY` — el router ha aceptado
   la comprobación y ha abierto su consola de fábrica **temporal**. Esas
   claves valen solo para esta recuperación.
4. `[*] ventanas de flash en /dev/mtd9…` — lee la memoria del router por
   trozos buscando las piezas cifradas donde vive la contraseña. **Es la
   parte lenta** (varios minutos) y puede saltar entre dispositivos mtd9,
   mtd8… Es normal.
5. `[+] seed encontrada` / `[+] oss encontrado` / `[+] paramtag: N bytes` —
   cada pieza localizada.
6. `[+] factory SSH desarmado` — la consola de fábrica se cierra sola al
   terminar.
7. **El resultado:**

```
== Credenciales del admin web ==
  usuario: admin    (source: paramtag:0x602)
  password: ********  (source: paramtag:0x702)
```

Esa es la contraseña de administrador que buscabas. Entra en
`http://192.168.1.1` con ella, **cámbiala por una que recuerdes** y, de paso,
desactiva el acceso remoto WAN si no lo usas.

---

## ¿Solo quieres mirar, sin recuperar nada?

```bash
./digi-f8748.sh info        # modelo, MACs — solo lectura
./digi-f8748.sh handshake   # comprueba que el canal responde (no envía nada)
./digi-f8748.sh verify -U admin -W 'laclave'   # ¿es esta la clave buena?
```

## Comandos avanzados (opcionales)

| Comando | Qué hace |
|---|---|
| `arm` | Solo abre la consola de fábrica y muestra sus claves temporales |
| `dump --out digi-dump` | Solo vuelca las piezas cifradas a una carpeta |
| `decrypt --dir digi-dump` | Solo descifra un volcado anterior (sin router) |
| `disarm` | Cierra la consola de fábrica si algo quedó abierto |

Opciones útiles: `--host` (IP del router), `--router-mac` / `--client-mac`
(MACs a mano), `-y` (sin preguntas, para automatizar).

---

## Si algo sale mal (síntoma → qué hacer)

| Ves… | Significa | Qué haces |
|---|---|---|
| `webFac no devolvió re_rand` | El canal de fábrica no responde | El router acaba de reiniciarse o está ocupado: espera 2 minutos y prueba UNA vez |
| `FactoryMode no devolvió credenciales` | El router no aceptó la comprobación de MACs | Casi siempre es la MAC del cliente: conéctate al WiFi directo del router (sin repetidores) y asegúrate de dar la MAC de TU equipo |
| `login bloqueado (lockingTime=…)` | Demasiados intentos de login web | Espera esos segundos |
| Va lento en las ventanas de flash | Normal: lee megas por una consola de fábrica | Paciencia: 5–20 min |
| `seed+oss incompletos` en todos los dispositivos | El firmware guarda esas piezas en otra zona | Apaga el router 10 segundos, espera 2 minutos y ejecuta `recover` una vez más |
| macOS dice que "no se puede abrir" | Es un script, no una app | No hay nada que abrir: se ejecuta desde la terminal (pasos 2–4) |
| Se corta a mitad de camino | La consola de fábrica es delicada | Vuelve a ejecutar `recover`; y si algo quedó abierto: `./digi-f8748.sh disarm` |

## Preguntas frecuentes

**¿Puedo romper el router?** No se escribe nada en él: solo se lee. Si un
intento se queda a medias, un reinicio (apagar 10 segundos) lo deja como
estaba.

**¿DIGI puede ver esto?** El proceso ocurre entero dentro de tu red local. No
se envía nada a ningún sitio (el código es abierto: puedes leerlo).

**¿Y la contraseña WiFi?** Esto recupera la de **administrador** (la de la web
del router). La WiFi se ve en la web del router una vez entres como admin.

**¿Funciona con otros ZTE?** Probado con el F8748 de DIGI (XGS-PON). El
protocolo es de la familia ZTE de fibra; no se garantiza en otros modelos.

**¿Es legal?** Recuperar TU contraseña en TU router es uso legítimo. Hacerlo
en routers ajenos no lo es. Ante cualquier duda, consulta a un profesional
legal.

---

## Créditos y transparencia

- Escrito desde cero contra el protocolo documentado del firmware ZTE F8748.
  Las herramientas públicas de la familia `webFac` de ZTE (ZTETelnet,
  zte_modem_tools) sirvieron de referencia para validar el canal.
- Hallazgo notificado a **ZTE PSIRT** el 2026-09-22 (`DISCLOSURE.md`).
- Uso bajo tu responsabilidad, sin garantía alguna.
- Autor: [github.com/686f6c61](https://github.com/686f6c61)
