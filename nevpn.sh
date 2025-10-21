#!/usr/bin/env bash
# NeVPN unificado con consola interactiva, edición transaccional y verificación de dependencias.
# Comentado en español y estructurado para facilitar mantenimiento.
# Autor: NeTenebrae

set -Eeuo pipefail
IFS=$'\n\t'

# =========================
# Configuración y constantes
# =========================
REPO_URL="https://github.com/NeTenebraes/nevpn.git"
CONFIG_DIR="${HOME}/.nevpn"
CONFIG_FILE="${CONFIG_DIR}/proxy_config.conf"
OPENVPN_DIR="${CONFIG_DIR}/openvpn_configs"
WIREGUARD_DIR="${CONFIG_DIR}/wireguard_configs"
BIN_DIR="${HOME}/.local/bin"
WRAPPER_PATH="${BIN_DIR}/nevpn"

MARK_START="# >>> nevpn (auto) >>>"
MARK_END="# <<< nevpn (auto) <<<"

# Colores sobrios
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; NC=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; NC=""
fi

# =========================
# Utilidades y logging
# =========================
info() { printf "%s[INFO]%s %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$*" >&2; }

on_error() {
  local ec=$?
  err "Fallo inesperado (exit=${ec})."
  exit "$ec"
}
trap on_error ERR

need_cmd() { command -v "$1" >/dev/null 2>&1; }

sudo_wrap() {
  if [[ $EUID -eq 0 ]]; then "$@"
  elif need_cmd sudo; then sudo "$@"
  else err "Se requiere 'sudo' para esta operación"; return 1
  fi
}

ensure_dirs() {
  mkdir -p "${CONFIG_DIR}" "${OPENVPN_DIR}" "${WIREGUARD_DIR}"
}

save_kv() {
  local k="$1" v="$2"
  grep -q "^${k}=" "$CONFIG_FILE" 2>/dev/null && \
    sed -i.bak "s|^${k}=.*|${k}=${v}|g" "$CONFIG_FILE" || \
    printf "%s=%s\n" "$k" "$v" >> "$CONFIG_FILE"
}

read_kv() {
  [[ -f "$CONFIG_FILE" ]] || return 1
  grep -E "^$1=" "$CONFIG_FILE" | head -n1 | cut -d'=' -f2-
}

# =========================
# Transacción de archivos
# =========================
TX_DIR=""
TX_ACTIVE=0
TX_MANIFEST=""

tx_init() {
  TX_DIR="$(mktemp -d -t nevpn-tx.XXXXXX)"
  TX_MANIFEST="${TX_DIR}/manifest"
  : > "${TX_MANIFEST}"
  TX_ACTIVE=1
  trap tx_rollback INT TERM HUP
  # IMPORTANTE: rollback en salida normal de la consola
  :
}

tx_backup_once() {
  # tx_backup_once RUTA
  local f="$1"
  [[ -e "$f" ]] || { warn "No existe: $f"; return 0; }
  grep -Fq "|${f}|" "${TX_MANIFEST}" 2>/dev/null && return 0
  local key
  key="$(printf "%s" "$f" | sed 's#/#_#g')"
  local b="${TX_DIR}/${key}.bak"
  if [[ -d "$f" ]]; then
    err "No se soportan backups de directorios: $f"
    return 1
  fi
  sudo_wrap cp -a "$f" "$b"
  printf "file|%s|%s\n" "$f" "$b" >> "${TX_MANIFEST}"
}

tx_restore_file() {
  # tx_restore_file RUTA
  local f="$1"
  local line
  line="$(grep -F "file|${f}|" "${TX_MANIFEST}" || true)"
  [[ -z "$line" ]] && return 0
  local b
  b="$(printf "%s" "$line" | awk -F'|' '{print $3}')"
  [[ -f "$b" ]] && sudo_wrap cp -a "$b" "$f"
}

tx_rollback() {
  (( TX_ACTIVE == 1 )) || return 0
  if [[ -f "${TX_MANIFEST}" ]]; then
    tac "${TX_MANIFEST}" | while IFS='|' read -r tag path backup; do
      [[ "$tag" == "file" ]] || continue
      [[ -f "$backup" ]] && sudo_wrap cp -a "$backup" "$path" || true
    done
  fi
  TX_ACTIVE=0
  rm -rf "${TX_DIR}" || true
}

tx_commit() {
  (( TX_ACTIVE == 1 )) || return 0
  TX_ACTIVE=0
  rm -rf "${TX_DIR}" || true
}

# =========================
# PATH, wrapper e instalación
# =========================
ensure_path_rc_block() {
  local rc="$1"
  [[ -f "$rc" ]] || touch "$rc"
  sed -i.bak "/${MARK_START}/,/${MARK_END}/d" "$rc"
  cat >> "$rc" <<'EOF'

# >>> nevpn (auto) >>>
# Añadir ~/.local/bin al PATH si no está
if [ -d "$HOME/.local/bin" ] && ! printf '%s' ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
  export PATH="$HOME/.local/bin:$PATH"
fi
# <<< nevpn (auto) <<<
EOF
  info "PATH asegurado en ${rc}"
}

ensure_shell_path() {
  ensure_path_rc_block "${HOME}/.bashrc"
  ensure_path_rc_block "${HOME}/.zshrc"
  if [[ -f "${HOME}/.bash_profile" ]] && ! grep -q "source ~/.bashrc" "${HOME}/.bash_profile"; then
    {
      echo ""; echo "${MARK_START}"
      echo "# Cargar .bashrc en sesiones de login"
      echo "if [ -f ~/.bashrc ]; then source ~/.bashrc; fi"
      echo "${MARK_END}"
    } >> "${HOME}/.bash_profile"
    info "Fuente de .bashrc añadida a ~/.bash_profile"
  fi
}

write_wrapper() {
  mkdir -p "${BIN_DIR}"
  cat > "${WRAPPER_PATH}" <<'WRAP'
#!/usr/bin/env bash
set -Eeuo pipefail
exec bash "$HOME/.nevpn/nevpn.sh" "$@"
WRAP
  chmod +x "${WRAPPER_PATH}"
  info "Wrapper instalado en ${WRAPPER_PATH}"
}

reload_shell_env() {
  local sourced=0
  if [[ -n "${BASH_SOURCE:-}" && "${BASH_SOURCE[0]}" != "$0" ]]; then sourced=1; fi
  if [[ -n "${ZSH_EVAL_CONTEXT:-}" && "$ZSH_EVAL_CONTEXT" == *:file* ]]; then sourced=1; fi
  if (( sourced == 1 )); then
    [[ -f "${HOME}/.bashrc" ]] && source "${HOME}/.bashrc" || true
    [[ -f "${HOME}/.zshrc"  ]] && source "${HOME}/.zshrc"  || true
    return 0
  fi
  case "${SHELL##*/}" in
    bash) exec bash -l ;;
    zsh)  exec zsh -l ;;
    *)    need_cmd bash && exec bash -l || true ;;
  esac
}

install_self() {
  ensure_dirs
  cp -f "$0" "${CONFIG_DIR}/nevpn.sh"
  chmod +x "${CONFIG_DIR}/nevpn.sh"
  write_wrapper
  ensure_shell_path
  info "Instalación completada. Recargando entorno..."
  reload_shell_env
}

# =========================
# Verificación de dependencias
# =========================
ensure_deps() {
  local -a required=(git curl openvpn wg wg-quick)
  local -a missing=()
  for c in "${required[@]}"; do need_cmd "$c" || missing+=("$c"); done

  if (( ${#missing[@]} == 0 )); then
    info "Dependencias presentes: ${required[*]}"
    return 0
  fi

  warn "Faltan dependencias: ${missing[*]}"
  if [[ -x "./install.sh" && -z "${NEVPN_BOOTSTRAP:-}" ]]; then
    info "Ejecutando ./install.sh --yes"
    NEVPN_BOOTSTRAP=1 bash ./install.sh --yes || true
  else
    info "Clonando instalador desde el repositorio en tmp"
    local tmp; tmp="$(mktemp -d -t nevpn-bootstrap.XXXXXX)"
    git clone --depth=1 "${REPO_URL}" "${tmp}/nevpn"
    NEVPN_BOOTSTRAP=1 bash "${tmp}/nevpn/install.sh" --yes || true
    rm -rf "${tmp}" || true
  fi

  # Revalidar
  local -a still=()
  for c in "${missing[@]}"; do need_cmd "$c" || still+=("$c"); done
  if (( ${#still[@]} > 0 )); then
    err "Persisten dependencias faltantes: ${still[*]}"
    return 1
  fi
  info "Dependencias instaladas correctamente"
}

# =========================
# Proxy: entorno y perfiles
# =========================
proxy_set() {
  local ip="${1:-}"; local port="${2:-}"
  if [[ -z "$ip" || -z "$port" ]]; then
    ip="$(read_kv LAST_IP || true)"; port="$(read_kv LAST_PORT || true)"
    [[ -z "$ip" || -z "$port" ]] && { err "Faltan IP/PUERTO y no hay valores previos"; return 1; }
  fi
  save_kv LAST_IP "$ip"; save_kv LAST_PORT "$port"
  info "Proxy establecido: ${ip}:${port}"
}

proxy_on() {
  local ip port
  ip="$(read_kv LAST_IP || true)"; port="$(read_kv LAST_PORT || true)"
  [[ -z "$ip" || -z "$port" ]] && { err "No hay proxy guardado; usa: proxy set <IP> <PUERTO>"; return 1; }
  local url="http://${ip}:${port}"
  export http_proxy="$url" https_proxy="$url" ftp_proxy="$url" no_proxy="localhost,127.0.0.1"
  export HTTP_PROXY="$url" HTTPS_PROXY="$url" FTP_PROXY="$url" NO_PROXY="localhost,127.0.0.1"
  info "Proxy activado en entorno: ${url}"
}

proxy_off() {
  unset http_proxy https_proxy ftp_proxy no_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY
  info "Proxy desactivado en entorno"
}

run_proxy() {
  local ip port
  ip="$(read_kv LAST_IP || true)"; port="$(read_kv LAST_PORT || true)"
  [[ -z "$ip" || -z "$port" ]] && { err "No hay proxy guardado; usa: proxy set <IP> <PUERTO>"; return 1; }
  local url="http://${ip}:${port}"
  info "Ejecutando bajo proxy: $*"
  env http_proxy="$url" https_proxy="$url" ftp_proxy="$url" HTTP_PROXY="$url" HTTPS_PROXY="$url" FTP_PROXY="$url" "$@"
}

# =========================
# PACMAN/WGET bajo proxy (transaccional)
# =========================
pacman_proxy_on() {
  local ip port
  ip="$(read_kv LAST_IP || true)"; port="$(read_kv LAST_PORT || true)"
  [[ -z "$ip" || -z "$port" ]] && { err "No hay proxy guardado; usa: proxy set <IP> <PUERTO>"; return 1; }
  local url="http://${ip}:${port}"

  local wgetrc="/etc/wgetrc"
  local pc="/etc/pacman.conf"

  tx_backup_once "$wgetrc"
  tx_backup_once "$pc"

  sudo_wrap cp -n "$wgetrc" "${wgetrc}.pre-nevpn.bak" || true
  sudo_wrap sed -i \
    -e "s|^[#[:space:]]*use_proxy *=.*|use_proxy = on|g" \
    -e "s|^[#[:space:]]*http_proxy *=.*|http_proxy = ${url}|g" \
    -e "s|^[#[:space:]]*https_proxy *=.*|https_proxy = ${url}|g" \
    "$wgetrc" || true
  grep -q "^use_proxy" "$wgetrc" || echo "use_proxy = on" | sudo_wrap tee -a "$wgetrc" >/dev/null
  grep -q "^http_proxy" "$wgetrc" || echo "http_proxy = ${url}" | sudo_wrap tee -a "$wgetrc" >/dev/null
  grep -q "^https_proxy" "$wgetrc" || echo "https_proxy = ${url}" | sudo_wrap tee -a "$wgetrc" >/dev/null

  sudo_wrap cp -n "$pc" "${pc}.pre-nevpn.bak" || true
  if grep -q "^[#[:space:]]*XferCommand" "$pc"; then
    sudo_wrap sed -i "s|^[#[:space:]]*XferCommand.*|XferCommand = /usr/bin/wget --passive-ftp -c -O %o %u|g" "$pc"
  else
    echo "XferCommand = /usr/bin/wget --passive-ftp -c -O %o %u" | sudo_wrap tee -a "$pc" >/dev/null
  fi

  info "PACMAN/WGET configurados para usar ${url}"
  info "Actualiza con: sudo -E pacman -Syu"
}

pacman_proxy_off() {
  local wgetrc="/etc/wgetrc"
  local pc="/etc/pacman.conf"
  tx_restore_file "$wgetrc"
  tx_restore_file "$pc"
  info "PACMAN/WGET restaurados desde backup de sesión"
}

pacman_show() {
  echo "wgetrc proxy:"; grep -E "^(use_proxy|http_proxy|https_proxy)" /etc/wgetrc 2>/dev/null || true
  echo "pacman.conf XferCommand:"; grep -E "^[#[:space:]]*XferCommand" /etc/pacman.conf 2>/dev/null || true
}

pacman_update() {
  need_cmd pacman || { err "pacman no disponible en este sistema"; return 1; }
  info "Ejecutando: sudo -E pacman -Syu"
  sudo -E pacman -Syu
}

# =========================
# Git y SSH bajo proxy (transaccional para SSH)
# =========================
git_proxy_on() {
  local ip port
  ip="$(read_kv LAST_IP || true)"; port="$(read_kv LAST_PORT || true)"
  [[ -z "$ip" || -z "$port" ]] && { err "No hay proxy guardado; usa: proxy set <IP> <PUERTO>"; return 1; }
  local url="http://${ip}:${port}"
  git config --global http.proxy  "$url"
  git config --global https.proxy "$url"
  info "git configurado con proxy ${url}"
}

git_proxy_off() {
  git config --global --unset http.proxy  || true
  git config --global --unset https.proxy || true
  info "git proxy deshabilitado"
}

git_proxy_show() {
  git config --global --get http.proxy  || true
  git config --global --get https.proxy || true
}

ssh_proxy_set() {
  local ip port
  ip="$(read_kv LAST_IP || true)"; port="$(read_kv LAST_PORT || true)"
  [[ -z "$ip" || -z "$port" ]] && { err "No hay proxy guardado"; return 1; }

  mkdir -p "${HOME}/.ssh"
  local cfg="${HOME}/.ssh/config"
  tx_backup_once "$cfg"

  local nc_bin=""
  if need_cmd nc; then nc_bin="nc"
  elif need_cmd ncat; then nc_bin="ncat"
  else warn "No se encontró nc/ncat; instala openbsd-netcat o nmap-ncat"
  fi

  sed -i.bak '/# >>> nevpn ssh >>>/,/# <<< nevpn ssh <<</d' "$cfg" 2>/dev/null || true
  {
    echo "# >>> nevpn ssh >>>"
    echo "Host github.com"
    echo "    Hostname github.com"
    echo "    Port 22"
    if [[ -n "$nc_bin" ]]; then
      echo "    ProxyCommand ${nc_bin} -X connect -x ${ip}:${port} %h %p"
    else
      echo "    # Instala nc/ncat para ProxyCommand y añade manualmente:"
      echo "    # ProxyCommand nc -X connect -x ${ip}:${port} %h %p"
    fi
    echo "# <<< nevpn ssh <<<"
  } >> "$cfg"
  chmod 600 "$cfg"
  info "SSH configurado temporalmente para github.com vía ${ip}:${port}"
}

ssh_proxy_clear() {
  local cfg="${HOME}/.ssh/config"
  tx_restore_file "$cfg"
  info "SSH restaurado desde backup de sesión"
}

# =========================
# VPN (WireGuard / OpenVPN)
# =========================
vpn_on() {
  if pgrep -x openvpn >/dev/null || [[ -n "$(sudo_wrap wg show interfaces 2>/dev/null || true)" ]]; then
    warn "VPN activa detectada; usa 'vpn off' antes"
    return 1
  fi

  echo "Selecciona tipo de VPN:"
  select vpn_type in "WireGuard" "OpenVPN" "Cancelar"; do
    case "$vpn_type" in
      WireGuard)
        local files=("${WIREGUARD_DIR}"/*.conf)
        if [[ ! -e "${files[0]}" ]]; then err "Sin .conf en ${WIREGUARD_DIR}"; return 1; fi
        echo "Selecciona configuración WireGuard:"
        select wg_config in "${files[@]}"; do
          [[ -n "$wg_config" ]] || { echo "Selección inválida"; continue; }
          local base ifname link
          base="$(basename "$wg_config" .conf)"
          ifname="$(echo "$base" | sed -e 's/[^a-zA-Z0-9_-]/-/g' | cut -c1-15)"
          link="/etc/wireguard/${ifname}.conf"
          info "Preparando interfaz ${ifname}"
          sudo_wrap ln -sf "$wg_config" "$link"
          info "Conectando con $wg_config"
          if sudo_wrap wg-quick up "$ifname"; then
            info "WireGuard arriba como ${ifname}"
          else
            warn "Fallo de conexión; limpiando"
            sudo_wrap rm -f "$link"
          fi
          break
        done
        break
        ;;
      OpenVPN)
        local files=("${OPENVPN_DIR}"/*.ovpn)
        if [[ ! -e "${files[0]}" ]]; then err "Sin .ovpn en ${OPENVPN_DIR}"; return 1; fi
        echo "Selecciona configuración OpenVPN:"
        select ovpn in "${files[@]}"; do
          [[ -n "$ovpn" ]] || { echo "Selección inválida"; continue; }
          info "Conectando con $ovpn en segundo plano"
          sudo_wrap openvpn --config "$ovpn" --daemon
          sleep 2
          info "OpenVPN arriba"
          break
        done
        break
        ;;
      Cancelar) info "Cancelado"; break ;;
      *) echo "Opción inválida" ;;
    esac
  done
}

vpn_off() {
  info "Desconectando VPNs"
  if pgrep -x openvpn >/dev/null; then
    sudo_wrap killall openvpn || true
    info "OpenVPN detenido"
  fi
  local ifaces
  ifaces="$(sudo_wrap wg show interfaces 2>/dev/null || true)"
  if [[ -n "$ifaces" ]]; then
    for iface in $ifaces; do
      info "Derribando $iface"
      local link="/etc/wireguard/${iface}.conf"
      if sudo_wrap wg-quick down "$iface"; then
        info "Interfaz $iface abajo"
      else
        warn "Fallo 'wg-quick down'; eliminando enlace"
        sudo_wrap ip link delete dev "$iface" || true
      fi
      [[ -L "$link" ]] && sudo_wrap rm -f "$link"
    done
    info "WireGuard detenido"
  fi
}

# =========================
# Estado
# =========================
status_show() {
  echo ""
  echo "--- Estado actual ---"
  echo "VPN:"
  local any=false
  local pids; pids="$(pgrep openvpn || true)"
  if [[ -n "$pids" ]]; then
    any=true
    echo " - CONNECTED (OpenVPN)"
    for pid in $pids; do
      local cfg; cfg="$(ps -p "$pid" -o cmd= | grep -oP -- '--config \K[^\s]+')" || true
      echo "   └─ Config: $cfg"
    done
  fi
  local ifaces; ifaces="$(sudo_wrap wg show interfaces 2>/dev/null || true)"
  if [[ -n "$ifaces" ]]; then
    any=true
    for i in $ifaces; do
      local link="/etc/wireguard/${i}.conf"
      local orig=""; [[ -L "$link" ]] && orig="$(readlink -f "$link")"
      echo " - CONNECTED (WireGuard)"
      echo "   ├─ Interface: $i"
      echo "   └─ Config: $orig"
    done
  fi
  if [[ "$any" == false ]]; then echo " - DISCONNECTED"; fi

  echo ""
  echo "Proxy:"
  if [[ -n "${http_proxy:-}" ]]; then
    local ip;   ip="$(echo "$http_proxy" | sed -E 's_.*//([^:]+):.*_\1_')"
    local port; port="$(echo "$http_proxy" | sed -E 's_.*:([0-9]+).*_\1_')"
    echo " - ACTIVE"
    echo "   ├─ IP: $ip"
    echo "   └─ Port: $port"
  else
    echo " - INACTIVE"
  fi

  echo ""
  echo "IP pública:"
  if need_cmd curl; then curl -s ipinfo.io || true; fi
}

# =========================
# Consola interactiva (con rollback al salir)
# =========================
console() {
  tx_init
  echo "Consola interactiva. 'help' para ver comandos. 'exit' para salir."
  while true; do
    read -rp "nevpn> " line || break
    set +e
    case "$line" in
      "" ) ;;
      "help" )
        cat <<EOT
Comandos:
  status                      -> estado de VPN/Proxy
  proxy set <IP> <PUERTO>     -> guarda IP/PUERTO
  proxy on|off                -> activa/desactiva entorno actual
  run-proxy <cmd...>          -> ejecuta un comando bajo proxy guardado
  pacman-proxy on|off|show    -> configura/restore /etc/wgetrc y /etc/pacman.conf
  pacman-update               -> sudo -E pacman -Syu
  git-proxy on|off|show       -> configura git global
  ssh-proxy set|clear         -> configura/restore Host github.com con ProxyCommand
  vpn on|off                  -> conecta/desconecta (WireGuard/OpenVPN)
  install-self                -> instala wrapper ~/.local/bin/nevpn y recarga shell
  deps-check                  -> verifica e instala dependencias
  exit                        -> salir (restaura cambios de sesión)
EOT
        ;;
      status ) status_show ;;
      proxy\ set* ) proxy_set ${line#proxy set } ;;
      "proxy on" ) proxy_on ;;
      "proxy off" ) proxy_off ;;
      run-proxy* ) run_proxy ${line#run-proxy } ;;
      "pacman-proxy on" ) pacman_proxy_on ;;
      "pacman-proxy off" ) pacman_proxy_off ;;
      "pacman-proxy show" ) pacman_show ;;
      "pacman-update" ) pacman_update ;;
      "git-proxy on" ) git_proxy_on ;;
      "git-proxy off" ) git_proxy_off ;;
      "git-proxy show" ) git_proxy_show ;;
      "ssh-proxy set" ) ssh_proxy_set ;;
      "ssh-proxy clear" ) ssh_proxy_clear ;;
      "vpn on" ) vpn_on ;;
      "vpn off" ) vpn_off ;;
      "install-self" ) install_self ;;
      "deps-check" ) ensure_deps ;;
      exit ) break ;;
      * ) echo "Comando no reconocido";;
    esac
    set -e
  done
  tx_rollback
}

# =========================
# Flags compatibles y main
# =========================
usage() {
  cat <<'EOF'
Uso:
  nevpn                 -> consola interactiva (rollback automático al salir)
  nevpn -S              -> estado
  nevpn -Pon|-Poff      -> proxy on/off
  nevpn -Von|-Voff      -> vpn on/off
  nevpn -Up             -> comprobación de actualizaciones (reserva)
  nevpn --install       -> instala wrapper y recarga shell
  nevpn --help          -> esta ayuda
EOF
}

check_for_updates_stub() { info "Comprobación de actualizaciones deshabilitada en versión monolítica"; }

main() {
  ensure_dirs
  ensure_deps
  case "${1:-}" in
    "" ) console ;;
    -S ) status_show ;;
    -Pon ) proxy_on ;;
    -Poff ) proxy_off ;;
    -Von ) vpn_on ;;
    -Voff ) vpn_off ;;
    -Up ) check_for_updates_stub ;;
    --install ) install_self ;;
    --help|-h ) usage ;;
    * ) err "Argumento inválido: $1"; usage; exit 1 ;;
  esac
}

main "$@"
