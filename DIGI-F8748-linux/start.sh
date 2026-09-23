#!/usr/bin/env bash
# =============================================================================
#  start.sh — comprobador de dependencias + lanzador de digi-f8748.sh
#  El recuperador de la contraseña de administrador del DIGI F8748.
#  Si estás aquí, es que la has perdido.
#  Autor: github.com/686f6c61
#
#  Comprueba curl, openssl, xxd, ssh y expect; si falta algo TE PREGUNTA
#  antes de instalar nada. Con -y / --yes instala sin preguntar.
#
#  Uso:
#    ./start.sh                 # comprobar y lanzar (menú de ayuda si falta)
#    ./start.sh info            # comprobar dependencias y ejecutar 'info'
#    ./start.sh -y recover      # instalar lo que falte sin preguntar + recover
# =============================================================================
set -u
cd "$(dirname "$0")"

AUTO=0
ARGS=()
for a in "$@"; do
  case "$a" in
    -y|--yes) AUTO=1;;
    *) ARGS+=("$a");;
  esac
done

if [ ! -f digi-f8748.sh ]; then
  echo "[x] No encuentro digi-f8748.sh junto a start.sh"; exit 1
fi

# ---------------- deteccion de sistema y gestor de paquetes ------------------
OS="$(uname -s)"
PKG=""; PKG_INSTALL=""; SUDO=""
case "$OS" in
  Darwin)
    PKG="brew"
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && BREW="$p"; done
    ;;
  Linux)
    if   command -v apt-get >/dev/null 2>&1; then PKG="apt"
    elif command -v dnf     >/dev/null 2>&1; then PKG="dnf"
    elif command -v yum     >/dev/null 2>&1; then PKG="yum"
    elif command -v pacman  >/dev/null 2>&1; then PKG="pacman"
    elif command -v zypper  >/dev/null 2>&1; then PKG="zypper"
    elif command -v apk     >/dev/null 2>&1; then PKG="apk"
    fi
    ;;
esac

# nombre del paquete segun el gestor (dep -> paquete)
pkg_name(){
  case "$PKG:$1" in
    apt:ssh)        echo "openssh-client";;
    apt:xxd)        echo "xxd";;
    dnf:ssh)        echo "openssh-clients";;
    dnf:xxd)        echo "vim-common";;
    yum:ssh)        echo "openssh-clients";;
    yum:xxd)        echo "vim-common";;
    pacman:xxd)     echo "xxd";;
    pacman:ssh)     echo "openssh";;
    zypper:xxd)     echo "vim";;
    zypper:ssh)     echo "openssh";;
    apk:ssh)        echo "openssh-client";;
    brew:expect)    echo "expect";;
    brew:xxd)       echo "xxd";;
    *)              echo "$1";;
  esac
}

# ------------------------------ comprobacion ---------------------------------
MISSING=()
for dep in curl openssl xxd ssh expect; do
  if command -v "$dep" >/dev/null 2>&1; then
    echo "[+] $dep: OK"
  else
    echo "[!] $dep: NO está"
    MISSING+=("$dep")
  fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo "[+] Todo listo. Arrancando digi-f8748..."
  exec bash digi-f8748.sh ${ARGS+"${ARGS[@]}"}
fi

# ------------------------------- preguntar -----------------------------------
echo
echo "Faltan dependencias: ${MISSING[*]}"
if [ -z "$PKG" ]; then
  echo "[x] No he detectado un gestor de paquetes automatico."
  echo "    Instalalas a mano e intenta de nuevo. Guia rapida:"
  echo "      Debian/Ubuntu : sudo apt install curl openssl xxd expect openssh-client"
  echo "      Fedora        : sudo dnf install curl openssl vim-common expect openssh-clients"
  echo "      Arch          : sudo pacman -S curl openssl xxd expect openssh"
  echo "      macOS         : brew install expect   (lo demas ya viene de serie)"
  exit 1
fi

echo "Puedo instalarlas con: $PKG"
MANUAL="no"
case "$PKG:$OS" in
  brew:Darwin) MANUAL="no";;
  apt:*|apk:*) [ "$(id -u)" = "0" ] || { command -v sudo >/dev/null 2>&1 && SUDO="sudo"; }; MANUAL="no";;
  dnf:*|yum:*) [ "$(id -u)" = "0" ] || MANUAL="si";;
  pacman:*)    [ "$(id -u)" = "0" ] || MANUAL="si";;
  zypper:*)    [ "$(id -u)" = "0" ] || MANUAL="si";;
esac
if [ "$MANUAL" = "si" ]; then
  echo "[x] Ejecuta esto como root y vuelve a lanzar start.sh:"
  echo "    $PKG install $(for d in "${MISSING[@]}"; do pkg_name "$d"; done | tr '\n' ' ')"
  exit 1
fi

ANS="n"
if [ "$AUTO" = "1" ]; then
  ANS="s"
else
  if [ -t 0 ]; then
    printf "¿Quieres que las instale ahora? [s/N] "
    read -r ANS
  else
    echo "[i] Sin terminal interactivo: usa ./start.sh -y para instalar sin preguntar."
  fi
fi

case "$ANS" in
  s|S|si|SI|Si|y|Y|yes)
    PKGS=()
    for d in "${MISSING[@]}"; do PKGS+=("$(pkg_name "$d")"); done
    echo "[*] Instalando: ${PKGS[*]}"
    case "$PKG" in
      brew)   "$BREW" install "${PKGS[@]}";;
      apt)    $SUDO apt-get update -qq && $SUDO apt-get install -y -q "${PKGS[@]}";;
      dnf)    $SUDO dnf install -y -q "${PKGS[@]}";;
      yum)    $SUDO yum install -y -q "${PKGS[@]}";;
      pacman) $SUDO pacman -Sy --noconfirm "${PKGS[@]}";;
      zypper) $SUDO zypper --non-interactive install "${PKGS[@]}";;
      apk)    $SUDO apk add --no-cache "${PKGS[@]}";;
    esac
    echo "[+] Instalacion terminada. Comprobando de nuevo..."
    OK=1
    for d in "${MISSING[@]}"; do
      command -v "$d" >/dev/null 2>&1 || { echo "[x] $d sigue sin estar"; OK=0; }
    done
    [ "$OK" = "1" ] || exit 1
    echo "[+] Todo listo. Arrancando digi-f8748..."
    exec bash digi-f8748.sh ${ARGS+"${ARGS[@]}"}
    ;;
  *)
    echo "[i] Instalacion cancelada. Puedes instalarlas a mano:"
    echo "    $PKG install $(for d in "${MISSING[@]}"; do pkg_name "$d"; done | tr '\n' ' ')"
    exit 1
    ;;
esac
