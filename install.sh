#!/usr/bin/env bash
# Instalador NeVPN & Proxy Manager
# Objetivo: instalación reproducible, soportada en bash y zsh, sin acoplarse al shell.
# Autor: NeTenebrae (estilo), comentarios en español, sin emojis.

set -Eeuo pipefail
IFS=$'\n\t'

# --- Configuración base ---
REPO_URL="https://github.com/NeTenebraes/nevpn.git"
INSTALL_DIR="${HOME}/.nevpn"
BIN_DIR="${HOME}/.local/bin"
WRAPPER_PATH="${BIN_DIR}/nevpn"

# Marcadores para insertar líneas en rc de shell de forma idempotente
MARK_START="# >>> nevpn (auto) >>>"
MARK_END="# <<< nevpn (auto) <<<"

# Colores básicos (si el terminal lo soporta)
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  RED=$'\033[0;31m'
  NC=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; NC=""
fi

# --- Utilidades de log ---
info() { printf "%s[INFO]%s %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$*" >&2; }

# --- Manejo de errores global ---
on_error() {
  local exit_code=$?
  err "Fallo inesperado (exit=${exit_code}). Revisa los mensajes anteriores."
  exit "$exit_code"
}
trap on_error ERR

# --- Comprobaciones de entorno ---
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

require_cmd() {
  if ! need_cmd "$1"; then
    err "Dependencia requerida no encontrada: $1"
    return 1
  fi
}

# --- Auto-detección del gestor de paquetes ---
detect_pm() {
  if need_cmd apt-get; then echo "apt"; return 0; fi
  if need_cmd pacman; then echo "pacman"; return 0; fi
  if need_cmd dnf; then echo "dnf"; return 0; fi
  if need_cmd zypper; then echo "zypper"; return 0; fi
  echo ""
}

sudo_wrap() {
  # Usa sudo si no somos root
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif need_cmd sudo; then
    sudo "$@"
  else
    err "Se requieren privilegios de administrador para instalar dependencias, pero 'sudo' no está disponible."
    return 1
  fi
}

# --- Instalación de dependencias ---
install_deps() {
  local pm="$1"
  local -a cmds=(git curl openvpn wg)
  local -a missing=()

  for c in "${cmds[@]}"; do
    if ! need_cmd "$c"; then
      missing+=("$c")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    info "Dependencias presentes: ${cmds[*]}"
    return 0
  fi

  info "Faltan dependencias: ${missing[*]}"

  # Mapeo de comandos→paquetes
  local -a pkgs=()
  for dep in "${missing[@]}"; do
    case "$dep" in
      wg) pkgs+=("wireguard-tools") ;;
      *)  pkgs+=("$dep") ;;
    esac
  done

  case "$pm" in
    apt)
      sudo_wrap apt-get update
      sudo_wrap apt-get install -y "${pkgs[@]}"
      ;;
    pacman)
      sudo_wrap pacman -Syu --noconfirm "${pkgs[@]}"
      ;;
    dnf)
      sudo_wrap dnf install -y "${pkgs[@]}"
      ;;
    zypper)
      sudo_wrap zypper --non-interactive install "${pkgs[@]}"
      ;;
    *)
      err "Gestor de paquetes no soportado o no detectado. Instala manualmente: ${pkgs[*]}"
      return 1
      ;;
  esac

  # Verificación post-instalación
  for c in "${missing[@]}"; do
    if ! need_cmd "$c"; then
      err "La dependencia '$c' no se pudo instalar automáticamente."
      return 1
    fi
  done
  info "Dependencias instaladas correctamente."
}

# --- Clonado/actualización del repositorio ---
sync_repo() {
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    info "Actualizando repositorio en ${INSTALL_DIR}"
    git -C "${INSTALL_DIR}" fetch --all --prune
    git -C "${INSTALL_DIR}" reset --hard origin/main
  else
    info "Clonando repositorio en ${INSTALL_DIR}"
    git clone --depth=1 "${REPO_URL}" "${INSTALL_DIR}"
  fi

  # Validación de archivos esperados
  if [[ ! -f "${INSTALL_DIR}/nevpn.sh" ]]; then
    err "Archivo principal no encontrado: ${INSTALL_DIR}/nevpn.sh"
    return 1
  fi

  mkdir -p "${INSTALL_DIR}/flags" \
           "${INSTALL_DIR}/openvpn_configs" \
           "${INSTALL_DIR}/wireguard_configs"
  info "Estructura validada."
}

# --- Wrapper ejecutable ~/.local/bin/nevpn ---
write_wrapper() {
  mkdir -p "${BIN_DIR}"

  cat > "${WRAPPER_PATH}" <<'WRAP'
#!/usr/bin/env bash
set -Eeuo pipefail
LIB="${HOME}/.nevpn/nevpn.sh"

if [[ -f "${LIB}" ]]; then
  # shellcheck source=/dev/null
  source "${LIB}"
  nevpn_handler "$@"
else
  printf "Error: no se encuentra %s\n" "${LIB}" >&2
  exit 1
fi
WRAP

  chmod +x "${WRAPPER_PATH}"
  info "Wrapper instalado en ${WRAPPER_PATH}"
}

# --- Asegurar PATH para ~/.local/bin ---
ensure_path_rc_block() {
  local rc="$1"
  [[ -f "$rc" ]] || touch "$rc"

  # Elimina bloque previo (idempotente)
  sed -i.bak "/${MARK_START}/,/${MARK_END}/d" "$rc"

  cat >> "$rc" <<EOF

${MARK_START}
# Añadir ~/.local/bin al PATH si no está
if [ -d "\$HOME/.local/bin" ] && ! printf '%s' ":\$PATH:" | grep -q ":\$HOME/.local/bin:"; then
  export PATH="\$HOME/.local/bin:\$PATH"
fi
${MARK_END}
EOF
  info "PATH asegurado en ${rc}"
}

ensure_shell_path() {
  # Asegura PATH en bash y zsh para sesiones interactivas.
  ensure_path_rc_block "${HOME}/.bashrc"
  ensure_path_rc_block "${HOME}/.zshrc"

  # Si existe .bash_profile pero no carga .bashrc, lo añadimos
  if [[ -f "${HOME}/.bash_profile" ]] && ! grep -q "source ~/.bashrc" "${HOME}/.bash_profile"; then
    {
      echo ""
      echo "${MARK_START}"
      echo "# Cargar .bashrc en sesiones de login"
      echo "if [ -f ~/.bashrc ]; then"
      echo "  source ~/.bashrc"
      echo "fi"
      echo "${MARK_END}"
    } >> "${HOME}/.bash_profile"
    info "Fuente de .bashrc añadida a ~/.bash_profile"
  fi
}

# --- Desinstalación ---
uninstall() {
  warn "Desinstalando NeVPN"
  rm -f "${WRAPPER_PATH}" || true
  rm -rf "${INSTALL_DIR}" || true

  for rc in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.bash_profile"; do
    [[ -f "$rc" ]] || continue
    sed -i.bak "/${MARK_START}/,/${MARK_END}/d" "$rc" || true
    info "Limpieza aplicada a ${rc}"
  done

  # Limpieza de enlaces WireGuard que apunten al repo del usuario
  if need_cmd find; then
    sudo_wrap find /etc/wireguard -type l -lname "${INSTALL_DIR}/wireguard_configs/*" -exec rm -f {} \; 2>/dev/null || true
    info "Enlaces simbólicos de WireGuard limpiados si existían"
  fi

  info "Desinstalación completada"
}

# --- Recarga del entorno del shell ---
reload_shell_env() {
  # Caso 1: el instalador fue 'sourceado' en el shell actual (afecta entorno del padre)
  local sourced=0
  # Bash: si BASH_SOURCE[0] != $0, estamos en un contexto 'source'
  if [[ -n "${BASH_SOURCE:-}" && "${BASH_SOURCE[0]}" != "$0" ]]; then
    sourced=1
  fi
  # Zsh: ZSH_EVAL_CONTEXT contiene ':file' cuando se hace 'source'
  if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == *:file* ]]; then
    sourced=1
  fi

  if (( sourced == 1 )); then
    # Recarga rc en el shell actual
    # Idempotente y tolerante a ausencia de archivos
    [[ -f "${HOME}/.bashrc" ]] && source "${HOME}/.bashrc" || true
    [[ -f "${HOME}/.zshrc"  ]] && source "${HOME}/.zshrc"  || true
    return 0
  fi

  # Caso 2: el instalador fue ejecutado como proceso separado
  # No puede modificar el entorno del shell padre; forzamos un login shell
  local sh="${SHELL##*/}"
  case "$sh" in
    bash) exec bash -l ;;
    zsh)  exec zsh  -l ;;
    *)
      # Si el shell no es bash/zsh, intentar bash como fallback
      if command -v bash >/dev/null 2>&1; then
        exec bash -l
      fi
      # Si no hay bash, no hacer nada; el usuario ya tiene el PATH asegurado en futuras sesiones
      return 0
      ;;
  esac
}


# --- Uso ---
usage() {
  cat <<EOF
Uso:
  $0 [--yes] [--pm apt|pacman|dnf|zypper] [--no-deps]
  $0 --uninstall

Opciones:
  --yes         Ejecuta instalación sin confirmaciones.
  --pm <pm>     Fuerza gestor de paquetes (auto si no se indica).
  --no-deps     Omite instalación de dependencias.
  --uninstall   Elimina wrapper, rc y directorio ${INSTALL_DIR}.
EOF
}

# --- Entrada principal ---
main() {
  local PM=""
  local YES=0
  local NO_DEPS=0

  while (( $# > 0 )); do
    case "${1:-}" in
      --uninstall) uninstall; return 0 ;;
      --yes) YES=1 ;;
      --pm) shift; PM="${1:-}";;
      --no-deps) NO_DEPS=1 ;;
      -h|--help) usage; return 0 ;;
      *) err "Opción no reconocida: $1"; usage; return 1 ;;
    esac
    shift || true
  done

  info "Instalando NeVPN & Proxy Manager"

  if [[ -z "$PM" ]]; then
    PM="$(detect_pm)"
  fi

  if (( NO_DEPS == 0 )); then
    if [[ -z "$PM" ]]; then
      err "No se detectó gestor de paquetes; instala manualmente: git curl openvpn wireguard-tools"
      return 1
    fi
    install_deps "$PM"
  else
    info "Instalación de dependencias omitida por bandera --no-deps"
  fi

  require_cmd git
  require_cmd curl

  sync_repo
  write_wrapper
  ensure_shell_path

info "Instalación finalizada. Recargando entorno..."
  reload_shell_env
  info "Comando disponible: nevpn -h"
}

main "$@"
