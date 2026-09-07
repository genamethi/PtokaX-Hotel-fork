#!/bin/sh
# Interactive setup for NMDCS in front of PtokaX.
#
set -u

self=${0##*/}
here=$(cd "$(dirname "$0")" && pwd)

VARS='NGINX_PREFIX NGINX_USER NGINX_MODE BUILD_DIR TLS_PORT PROXY_ADDR TCP_PORT
      HUB STATE_DIR HUB_ADDR CERT_METHOD CERT KEY CERT_CUSTOM STREAM_DIR CONFD_DIR
      ENABLE_CONSOLE CERT_CHALLENGE'

set_defaults() {
  NGINX_PREFIX=${NGINX_PREFIX:-/usr/local/nginx}
  NGINX_USER=${NGINX_USER:-nginx}
  NGINX_MODE=${NGINX_MODE:-auto}
  BUILD_DIR=${BUILD_DIR:-/usr/local/src/nginx}
  TLS_PORT=${TLS_PORT:-5411}
  PROXY_ADDR=${PROXY_ADDR:-127.0.0.1:5412}
  TCP_PORT=${TCP_PORT:-411}
  HUB=${HUB:-}
  STATE_DIR=${STATE_DIR:-}
  HUB_ADDR=${HUB_ADDR:-hub.example.com}
  CERT_METHOD=${CERT_METHOD:-letsencrypt}
  CERT_CHALLENGE=${CERT_CHALLENGE:-http}
  CERT=${CERT:-/etc/letsencrypt/live/hub.example.com/fullchain.pem}
  KEY=${KEY:-/etc/letsencrypt/live/hub.example.com/privkey.pem}
  CERT_CUSTOM=${CERT_CUSTOM:-no}
  STREAM_DIR=${STREAM_DIR:-}
  CONFD_DIR=${CONFD_DIR:-}
  ENABLE_CONSOLE=${ENABLE_CONSOLE:-yes}
}

set_defaults

quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# --- page state -------------------------------------------------------------
SNAP=$(mktemp)
trap 'rm -f "$SNAP"' EXIT INT TERM

snapshot() {
  : >"$SNAP"
  for v in "$@"; do
    eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >>"$SNAP"
  done
}
restore() { . "$SNAP"; }

reset_vars() {
  _keep=$(mktemp)
  _fresh=$(mktemp)
  _wanted=$*
  for v in $VARS; do eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >>"$_keep"; done
  set_defaults
  for v in $VARS; do eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >>"$_fresh"; done
  . "$_keep"
  for v in $_wanted; do eval "$(grep "^$v=" "$_fresh")"; done
  rm -f "$_keep" "$_fresh"
}

# --- output -----------------------------------------------------------------
DIM=$(printf '\033[2m')
OFF=$(printf '\033[0m')

say() { printf '%s\n' "$1"; }
die() {
  printf '%s: %s\n' "$self" "$1" >&2
  exit 1
}
rule() { printf '  %s\n' '----------------------------------------------------------------'; }
head2() {
  printf '\n  %s\n' "$1"
  rule
}
intro() {
  printf '  %s\n' "$1"
  [ -n "${2:-}" ] && printf '  %s\n' "$2"
  printf '\n'
}

row() {
  if [ -n "${4:-}" ]; then
    printf '    %-3s %-16s %-38s %s\n' "$1" "$2" "$3" "$4"
  else printf '    %-3s %-16s %s\n' "$1" "$2" "$3"; fi
}
act() { printf '    %-3s %s\n' "$1" "$2"; }
pause() {
  printf '\n  enter to continue '
  read -r _d || true
}

edit() {
  _var=$1
  _label=$2
  _hint=$3
  shift 3
  eval "_cur=\${$_var}"
  [ -n "$_hint" ] && say "  $_hint"
  [ $# -gt 0 ] && say "  one of: $*"
  printf '  %s [%s]: ' "$_label" "$_cur"
  read -r _new || _new=
  [ -z "$_new" ] && return 0
  if [ $# -gt 0 ]; then
    for _c in "$@"; do [ "$_new" = "$_c" ] && {
      eval "$_var=\$_new"
      return 0
    }; done
    say "  not one of: $*"
    return 0
  fi
  eval "$_var=\$_new"
}

confirm() {
  printf '  %s [y/N] ' "$1"
  read -r _c || _c=n
  case $_c in y | Y | yes) return 0 ;; *) return 1 ;; esac
}
# _key, not KEY: KEY is the certificate key setting and a menu read would clobber it
menu() {
  printf '\n  > '
  read -r _key || _key=q
}

# --- privilege --------------------------------------------------------------
can_write() {
  _cw=$1
  while [ ! -e "$_cw" ]; do
    case $_cw in */*)
      _cw=${_cw%/*}
      [ -n "$_cw" ] || _cw=/
      ;;
    *) _cw=. ;; esac
  done
  [ -w "$_cw" ]
}

priv() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    printf '  root: %s\n' "$*"
    sudo "$@"
  else die "need root for: $*"; fi
}
priv_sh() {
  if [ "$(id -u)" -eq 0 ]; then
    sh -c "$1"
  elif command -v sudo >/dev/null 2>&1; then
    printf '  root: %s\n' "$1"
    sudo sh -c "$1"
  else die "need root for: $1"; fi
}
priv_write() {
  if can_write "$1" || [ "$(id -u)" -eq 0 ]; then
    cat >"$1"
  elif command -v sudo >/dev/null 2>&1; then
    printf '  root: write %s\n' "$1"
    sudo tee "$1" >/dev/null
  else die "need root to write $1"; fi
}
priv_cp() { if can_write "$2"; then cp "$1" "$2"; else priv cp "$1" "$2"; fi; }
priv_cat() { if [ -r "$1" ]; then cat "$1"; else priv cat "$1"; fi; }
priv_mkdir() { if can_write "$1"; then mkdir -p "$1"; else priv mkdir -p "$1"; fi; }
priv_chmod() {
  _pc=$1
  shift
  if [ -O "$1" ] || [ "$(id -u)" -eq 0 ]; then chmod "$_pc" "$@"; else priv chmod "$_pc" "$@"; fi
}

# no read -s in POSIX sh
read_secret() {
  printf '  %s: ' "$1"
  stty -echo 2>/dev/null
  read -r _secret || _secret=
  stty echo 2>/dev/null
  printf '\n'
}
priv_test_dir() {
  if [ -d "$1" ]; then
    return 0
  elif [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo -n test -d "$1" 2>/dev/null
  else return 1; fi
}

install_needs_root() {
  [ -e "$NGINX_PREFIX" ] || { can_write "$(dirname "$NGINX_PREFIX")" && return 1 || return 0; }
  can_write "$NGINX_PREFIX" || return 0
  find "$NGINX_PREFIX" ! -user "$(id -un)" -print 2>/dev/null | head -n1 | grep -q . && return 0
  return 1
}

pkg_cmd() {
  if command -v pacman >/dev/null 2>&1; then
    printf 'pacman -S --needed --noconfirm %s' "$1"
  elif command -v apt-get >/dev/null 2>&1; then
    printf 'apt-get install -y %s' "$1"
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf install -y %s' "$1"
  elif command -v zypper >/dev/null 2>&1; then
    printf 'zypper --non-interactive install %s' "$1"
  elif command -v apk >/dev/null 2>&1; then
    printf 'apk add %s' "$1"
  else
    return 1
  fi
}

ensure_tool() {
  _et_tool=$1
  _et_pkg=${2:-$1}
  command -v "$_et_tool" >/dev/null 2>&1 && return 0
  if ! _et_cmd=$(pkg_cmd "$_et_pkg"); then
    say "  needs $_et_tool, and no package manager this script knows was found"
    say "  install $_et_tool however this system does it, then run the plan again"
    return 1
  fi
  confirm "needs $_et_tool, install it?" || return 1
  priv_sh "$_et_cmd" || {
    say "  install failed"
    return 1
  }
  command -v "$_et_tool" >/dev/null 2>&1 || {
    say "  $_et_tool not on PATH"
    return 1
  }
  return 0
}
tool_note() { command -v "$1" >/dev/null 2>&1 || printf 'needs %s' "$1"; }

# The whole fork assumes systemd, so this is a fact about the host rather than
# something to choose.
have_systemd() { command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; }
user_exists() { id -u "$1" >/dev/null 2>&1; }

# --- nginx ------------------------------------------------------------------
nginx_bin() {
  case $NGINX_MODE in
  prefix) printf '%s/sbin/nginx' "$NGINX_PREFIX" ;;
  system) command -v nginx 2>/dev/null || true ;;
  *) if [ -x "$NGINX_PREFIX/sbin/nginx" ]; then
    printf '%s/sbin/nginx' "$NGINX_PREFIX"
  else command -v nginx 2>/dev/null || true; fi ;;
  esac
}
nginx_has_stream() {
  _nhs_b=$(nginx_bin)
  [ -n "$_nhs_b" ] && [ -x "$_nhs_b" ] || return 1
  _nhs_v=$("$_nhs_b" -V 2>&1) || return 1
  printf '%s' "$_nhs_v" | grep -q -- '--with-stream' &&
    printf '%s' "$_nhs_v" | grep -q -- '--with-stream_ssl_module'
}
# -V reports --conf-path only when it was given at build time.
nginx_conf_prefix() {
  _ncp_b=$(nginx_bin)
  [ -n "$_ncp_b" ] && [ -x "$_ncp_b" ] || return 1
  _ncp_v=$("$_ncp_b" -V 2>&1) || return 1

  _ncp_d=$(printf '%s' "$_ncp_v" | tr ' ' '\n' | sed -n 's/^--conf-path=//p' | sed 's:/[^/]*$::')
  if [ -z "$_ncp_d" ]; then
    _ncp_p=$(printf '%s' "$_ncp_v" | tr ' ' '\n' | sed -n 's/^--prefix=//p')
    [ -n "$_ncp_p" ] && _ncp_d=$_ncp_p/conf
  fi

  [ -n "$_ncp_d" ] || return 1
  printf '%s' "$_ncp_d"
}

hub_names() {
  command -v pxctl >/dev/null 2>&1 || return 1
  pxctl list 2>/dev/null | sed -n 's/^ptokax@\([^.]*\)\.service.*/\1/p'
}

hub_status_of() {
  command -v systemctl >/dev/null 2>&1 || {
    printf unknown
    return
  }
  systemctl is-active "ptokax@$1" 2>/dev/null || true
}

hub_state_dir() {
  if [ -n "$STATE_DIR" ]; then
    printf '%s' "$STATE_DIR"
  elif command -v pxctl >/dev/null 2>&1 && [ -n "$HUB" ]; then
    pxctl get "$HUB" statedir 2>/dev/null
  fi
}
hub_known() { [ -n "$HUB" ] && hub_names 2>/dev/null | grep -qx "$HUB"; }

hub_tree_ok() {
  [ -n "$HUB" ] || return 1
  hub_known && return 0
  _d=$(hub_state_dir 2>/dev/null || true)
  [ -n "$_d" ] && priv_test_dir "$_d"
}
hub_running() { have_systemd && [ -n "$HUB" ] && systemctl is-active --quiet "ptokax@$HUB" 2>/dev/null; }
console_up() { [ -n "$HUB" ] && [ -S "/run/ptokax/$HUB-console.sock" ]; }
console_enabled() { [ -n "$HUB" ] && systemctl is-enabled --quiet "ptokax-console@$HUB.socket" 2>/dev/null; }
console_unit() { [ -f /etc/systemd/system/ptokax-console@.socket ] || [ -f /usr/lib/systemd/system/ptokax-console@.socket ]; }
# /etc/letsencrypt/live is 0700 root. Plain test incorrectly yields missing
priv_test_file() {
  [ -s "$1" ] && return 0
  [ "$(id -u)" -eq 0 ] && return 1
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n test -s "$1" 2>/dev/null
}

cert_present() { priv_test_file "$CERT" && priv_test_file "$KEY"; }

file_note() {
  priv_test_file "$1" && {
    printf present
    return
  }
  [ -r "$(dirname "$1")" ] && {
    printf missing
    return
  }
  printf 'cannot read, needs root'
}

cert_where() {
  _cw_d=$(dirname "$CERT")
  [ "$CERT_CUSTOM" = yes ] && {
    printf 'your files, in %s' "$_cw_d"
    return
  }
  case $CERT_METHOD in
  letsencrypt) printf 'certbot writes and renews into %s' "$_cw_d" ;;
  selfsigned) printf 'written to %s, and DC++ users have to opt in' "$_cw_d" ;;
  *) printf 'point cert and key at files you already have' ;;
  esac
}

sync_cert_paths() {
  [ "$CERT_CUSTOM" = yes ] && return 0
  case $CERT_METHOD in
  letsencrypt)
    CERT=/etc/letsencrypt/live/$HUB_ADDR/fullchain.pem
    KEY=/etc/letsencrypt/live/$HUB_ADDR/privkey.pem
    ;;
  selfsigned)
    CERT=/etc/ssl/ptokax/hub.crt
    KEY=/etc/ssl/ptokax/hub.key
    ;;
  esac
}

STEPS='user nginx cert console hub socket conf unit start'

step_label() {
  case $1 in
  nginx) echo "build nginx with stream" ;;
  cert) echo "obtain the certificate" ;;
  hub) echo "apply the hub settings" ;;
  conf) echo "write the nginx config" ;;
  user) echo "create the nginx account" ;;
  unit) echo "install the nginx unit" ;;
  console) echo "enable the Lua console socket" ;;
  socket) echo "install the proxy socket" ;;
  start) echo "start nginx" ;;
  esac
}

step_state() {
  case $1 in
  nginx)
    nginx_has_stream && {
      echo done
      return
    }
    [ -n "$(nginx_bin)" ] && [ "$NGINX_MODE" = system ] && {
      echo "packaged nginx has no stream module, set mode to prefix on page 1"
      return
    }
    echo ready
    ;;
  cert)
    cert_present && {
      echo done
      return
    }
    [ "$CERT_METHOD" = existing ] && {
      echo "method is existing but $CERT is missing"
      return
    }
    echo ready
    ;;
  console)
    have_systemd || {
      echo "this host is not running systemd"
      return
    }
    [ -n "$HUB" ] || {
      echo "no hub chosen on page 3"
      return
    }
    [ "$ENABLE_CONSOLE" = yes ] || {
      echo "switched off on page 3"
      return
    }
    hub_tree_ok || {
      echo "systemd does not know $HUB"
      return
    }
    console_enabled && {
      echo done
      return
    }
    console_unit || {
      echo "ptokax-console@.socket not installed, run make install"
      return
    }
    echo ready
    ;;
  hub)
    [ -n "$HUB" ] || {
      echo "no hub chosen on page 3"
      return
    }
    command -v pxctl >/dev/null 2>&1 || [ -n "$STATE_DIR" ] || {
      echo "no pxctl, set a state dir on page 3"
      return
    }
    hub_tree_ok || {
      echo "systemd does not know $HUB"
      return
    }
    hub_tls_enabled && {
      echo done
      return
    }
    if hub_running && ! console_up; then
      echo manual
      return
    fi
    echo ready
    ;;
  conf)
    nginx_has_stream || {
      echo "after: build nginx with stream"
      return
    }
    cert_present || {
      echo "after: obtain the certificate"
      return
    }
    [ -n "$STREAM_DIR" ] || STREAM_DIR=$(nginx_conf_prefix 2>/dev/null)/stream.d
    [ "$STREAM_DIR" = "/stream.d" ] && {
      echo "cannot work out the nginx config directory"
      return
    }
    [ -f "$STREAM_DIR/ptokax-nmdcs.conf" ] && {
      echo done
      return
    }
    echo ready
    ;;
  user)
    have_systemd || {
      echo "this host is not running systemd"
      return
    }
    user_exists "$NGINX_USER" && {
      echo done
      return
    }
    echo ready
    ;;
  unit)
    have_systemd || {
      echo "this host is not running systemd"
      return
    }
    [ -f /etc/systemd/system/nginx-ptokax.service ] && {
      echo done
      return
    }
    user_exists "$NGINX_USER" || {
      echo "after: create the nginx account"
      return
    }
    hub_tree_ok || {
      echo "after: choosing a hub on page 3"
      return
    }
    echo ready
    ;;
  socket)
    have_systemd || {
      echo "this host is not running systemd"
      return
    }
    [ -n "$HUB" ] || {
      echo "no hub chosen on page 3"
      return
    }
    [ -f "/etc/systemd/system/ptokax@$HUB.socket.d/20-proxy.conf" ] && {
      echo done
      return
    }
    [ -f /etc/systemd/system/ptokax@.socket ] || [ -f /usr/lib/systemd/system/ptokax@.socket ] ||
      {
        echo "ptokax@.socket not installed, PtokaX binds the address itself"
        return
      }
    echo ready
    ;;
  start)
    [ -n "$STREAM_DIR" ] && [ -f "$STREAM_DIR/ptokax-nmdcs.conf" ] || {
      echo "after: write the nginx config"
      return
    }
    echo ready
    ;;
  esac
}

step_run() {
  case $1 in
  nginx) run_build ;; cert) run_cert ;;
  hub) run_hub ;; conf) run_conf ;;
  console) run_console ;;
  user) run_user ;; unit) run_unit ;;
  socket) run_socket ;; start) run_start ;;
  esac
}

# --- plan -------------------------------------------------------------------
page_plan() {
  while :; do
    head2 "plan"
    intro "Nothing above this point changed the host. This does."
    _n=0
    _ready=0
    for st in $STEPS; do
      _n=$((_n + 1))
      _s=$(step_state "$st")
      case $_s in
      done) printf '    %-3s %-30s %s\n' "$_n" "$(step_label "$st")" "done" ;;
      ready)
        printf '    %-3s %-30s %s\n' "$_n" "$(step_label "$st")" "will run"
        _ready=$((_ready + 1))
        ;;
      *) printf '%s    %-3s %-30s %s%s\n' "$DIM" "$_n" "$(step_label "$st")" "$_s" "$OFF" ;;
      esac
    done
    say ""
    if [ "$_ready" -eq 0 ]; then
      say "  nothing to run"
    else act x "run the $_ready step(s) marked will run"; fi
    act q "back"
    menu
    case $_key in
    x)
      [ "$_ready" -gt 0 ] && run_plan
      pause
      ;;
    q) return ;;
    esac
  done
}

run_plan() {
  for st in $STEPS; do
    [ "$(step_state "$st")" = ready ] || continue
    say ""
    say "  == $(step_label "$st")"
    step_run "$st" || say "  step did not finish"
  done
  say ""
  say "  plan finished"
}

# --- step bodies ------------------------------------------------------------
run_build() {
  ensure_tool git || return 1
  say "  clone     $BUILD_DIR"
  say "  configure --prefix=$NGINX_PREFIX --with-stream --with-stream_ssl_module"
  say "  install   $NGINX_PREFIX"
  install_needs_root && say "  root needed" || say "  no root needed"
  confirm "go ahead?" || return 1

  _par=$(dirname "$BUILD_DIR")
  can_write "$_par" && mkdir -p "$_par" || priv mkdir -p "$_par"

  if [ -d "$BUILD_DIR/.git" ]; then
    can_write "$BUILD_DIR" && git -C "$BUILD_DIR" pull --ff-only || priv git -C "$BUILD_DIR" pull --ff-only
  else
    can_write "$_par" && git clone --depth 1 https://github.com/nginx/nginx.git "$BUILD_DIR" ||
      priv git clone --depth 1 https://github.com/nginx/nginx.git "$BUILD_DIR"
  fi
  [ -d "$BUILD_DIR" ] || {
    say "  clone failed"
    return 1
  }

  _cfg="cd '$BUILD_DIR' && auto/configure --prefix='$NGINX_PREFIX' \
--with-stream --with-stream_ssl_module --with-http_ssl_module \
--user='$NGINX_USER' --group='$NGINX_USER' \
--pid-path=/run/nginx/nginx.pid \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--http-client-body-temp-path=/var/lib/nginx/client_body \
--http-proxy-temp-path=/var/lib/nginx/proxy \
--http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
--http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
--http-scgi-temp-path=/var/lib/nginx/scgi"

  if can_write "$BUILD_DIR"; then sh -c "$_cfg"; else priv_sh "$_cfg"; fi || {
    say "  configure failed"
    return 1
  }

  _mk="cd '$BUILD_DIR' && make -j\$(nproc 2>/dev/null || echo 2)"
  if can_write "$BUILD_DIR"; then sh -c "$_mk"; else priv_sh "$_mk"; fi || {
    say "  build failed"
    return 1
  }

  _in="cd '$BUILD_DIR' && make install"
  if install_needs_root; then
    priv_sh "$_in" || {
      say "  install failed"
      return 1
    }
  elif ! sh -c "$_in"; then
    say "  install failed, prefix holds files owned by someone else"
    confirm "retry as root?" || return 1
    priv_sh "$_in" || {
      say "  install failed"
      return 1
    }
  fi

  [ -x "$NGINX_PREFIX/sbin/nginx" ] || {
    say "  no binary at $NGINX_PREFIX/sbin/nginx"
    return 1
  }
  NGINX_MODE=prefix
  say "  installed $(nginx_bin)"
}

run_cert() {
  case $CERT_METHOD in
  letsencrypt)
    if ! ensure_tool certbot; then
      confirm "use a self-signed certificate instead?" || return 1
      CERT_METHOD=selfsigned
      run_cert
      return $?
    fi
    if [ "$CERT_CHALLENGE" = dns ]; then
      run_certbot_dns
      return $?
    fi
    say "  needs $HUB_ADDR resolving here and inbound 80 from the internet"
    confirm "run certbot?" || return 1
    if ! priv certbot certonly --standalone -d "$HUB_ADDR"; then
      say ""
      say "  certbot could not prove the domain over port 80."
      say "  switching challenge to dns avoids the port entirely."
      confirm "use a self-signed certificate for now instead?" || return 1
      CERT_METHOD=selfsigned
      CERT_CUSTOM=no
      sync_cert_paths
      run_cert
      return $?
    fi
    say "  renewal keeps the key, so the keyprint stays the same"
    ;;
  selfsigned)
    ensure_tool openssl || return 1
    priv_mkdir "$(dirname "$CERT")"
    priv_mkdir "$(dirname "$KEY")"
    if can_write "$CERT" && can_write "$KEY"; then
      openssl req -new -newkey rsa:4096 -x509 -sha256 -days 1800 -nodes \
        -subj "/CN=$HUB_ADDR" -addext "subjectAltName=DNS:$HUB_ADDR" \
        -out "$CERT" -keyout "$KEY" 2>/dev/null && chmod 600 "$KEY"
    else
      priv openssl req -new -newkey rsa:4096 -x509 -sha256 -days 1800 -nodes \
        -subj "/CN=$HUB_ADDR" -addext "subjectAltName=DNS:$HUB_ADDR" \
        -out "$CERT" -keyout "$KEY" 2>/dev/null && priv chmod 600 "$KEY"
    fi
    cert_present || {
      say "  generation failed"
      return 1
    }
    show_keyprint
    ;;
  existing) say "  using $CERT and $KEY unchanged" ;;
  esac
}

run_certbot_dns() {
  case $HUB_ADDR in
  *.duckdns.org)
    ensure_tool curl || return 1
    read_secret "duckdns token"
    _dd_token=$_secret
    _secret=
    [ -n "$_dd_token" ] || {
      say "  no token"
      return 1
    }

    _dd_sub=${HUB_ADDR%%.duckdns.org}

    # duckdns answers OK or KO and nothing else
    say "  checking the token against duckdns"
    _dd_probe=$(curl -sS "https://www.duckdns.org/update?domains=$_dd_sub&token=$_dd_token&txt=setup-probe&verbose=true" 2>&1)
    case $_dd_probe in
    OK*) curl -sS "https://www.duckdns.org/update?domains=$_dd_sub&token=$_dd_token&clear=true" >/dev/null 2>&1 ;;
    *)
      say "  duckdns rejected it: $_dd_probe"
      say "  the token is the one on duckdns.org, and $_dd_sub must be yours"
      return 1
      ;;
    esac

    _dd_hooks=/etc/letsencrypt/duckdns
    priv_mkdir "$_dd_hooks"
    {
      printf '#!/bin/sh\n'
      printf 'r=$(curl -sS "https://www.duckdns.org/update?domains=${CERTBOT_DOMAIN%%%%.duckdns.org}&token=%s&txt=$CERTBOT_VALIDATION&verbose=true")\n' "$_dd_token"
      printf 'printf %%s "$r"\n'
      printf 'case $r in OK*) ;; *) exit 1 ;; esac\n'
      printf '# let the record spread before the CA looks for it\n'
      printf 'sleep 45\n'
    } | priv_write "$_dd_hooks/auth.sh"
    {
      printf '#!/bin/sh\n'
      printf 'exec curl -sS "https://www.duckdns.org/update?domains=${CERTBOT_DOMAIN%%%%.duckdns.org}&token=%s&clear=true"\n' "$_dd_token"
    } | priv_write "$_dd_hooks/cleanup.sh"
    priv_chmod 700 "$_dd_hooks/auth.sh" "$_dd_hooks/cleanup.sh"

    confirm "run certbot with the duckdns TXT hook?" || return 1
    priv certbot certonly --manual --preferred-challenges dns \
      --manual-auth-hook "$_dd_hooks/auth.sh" \
      --manual-cleanup-hook "$_dd_hooks/cleanup.sh" \
      -d "$HUB_ADDR" || return 1
    ;;
  *)
    say "  certbot will print a TXT record to add for _acme-challenge.$HUB_ADDR"
    say "  and wait. Renewal needs the same by hand unless you add a hook."
    confirm "run certbot?" || return 1
    priv certbot certonly --manual --preferred-challenges dns -d "$HUB_ADDR" || return 1
    ;;
  esac
  say "  renewal keeps the key, so the keyprint stays the same"
}

keyprint_of() {
  [ -s "$CERT" ] || {
    printf '<none>'
    return
  }
  _kp_h=$(openssl x509 -in "$CERT" -outform der 2>/dev/null | openssl dgst -sha256 -binary |
    base32 2>/dev/null | tr -d '=\n') || _kp_h=
  [ -n "$_kp_h" ] && printf 'SHA256/%s' "$_kp_h" || printf '<base32 unavailable>'
}
show_keyprint() {
  say "  nmdcs://$HUB_ADDR:$TLS_PORT?kp=$(keyprint_of)"
}

hub_setting_lines() {
  printf 'TLSEnabled\t=\t1\n'
  printf 'TLSProxyAddress\t=\t%s\n' "$PROXY_ADDR"
  printf 'PingerAddresses\t=\tnmdcs://%s:%s;dchub://%s:%s\n' "$HUB_ADDR" "$TLS_PORT" "$HUB_ADDR" "$TCP_PORT"
}
hub_setting_chunk() {
  printf 'SetMan.SetBool(SetMan.tBooleans.TLSEnabled, true)\n'
  printf 'SetMan.SetString(SetMan.tStrings.TLSProxyAddress, "%s")\n' "$PROXY_ADDR"
  printf 'SetMan.SetString(SetMan.tStrings.PingerAddresses, "nmdcs://%s:%s;dchub://%s:%s")\n' \
    "$HUB_ADDR" "$TLS_PORT" "$HUB_ADDR" "$TCP_PORT"
  printf 'SetMan.Save()\n'
}

run_console() {
  if hub_running; then
    say "  systemd will not enable a socket whose service is already up,"
    say "  so this costs one stop and start of ptokax@$HUB"
    confirm "stop it, enable the socket, start it again?" || return 1
    priv systemctl stop "ptokax@$HUB" || return 1
    if ! priv systemctl enable --now "ptokax-console@$HUB.socket"; then
      priv systemctl start "ptokax@$HUB"
      return 1
    fi
    priv systemctl start "ptokax@$HUB" || return 1
    _i=0
    while [ $_i -lt 10 ] && ! console_up; do
      sleep 1
      _i=$((_i + 1))
    done
  else
    priv systemctl enable "ptokax-console@$HUB.socket" || return 1
    say "  enabled, it comes up with the hub"
  fi
  say "  socat - UNIX-CONNECT:/run/ptokax/$HUB-console.sock"
}

run_hub() {
  if hub_running; then run_hub_console; else run_hub_file; fi
}

manual_hub_settings() {
  say "  In order to proceed you must set the following in the hub settings:"
  say ""
  hub_setting_lines | sed 's/^/      /'
}

hub_tls_enabled() {
  _d=$(hub_state_dir 2>/dev/null || true)
  [ -n "$_d" ] || return 1
  priv_cat "$_d/cfg/Settings.pxt" 2>/dev/null |
    grep -q '^TLSEnabled[[:space:]]*=[[:space:]]*1'
}

run_hub_file() {
  _d=$(hub_state_dir)
  _f=$_d/cfg/Settings.pxt
  if [ ! -f "$_f" ]; then
    say "  no $_f"
    say "  the instance exists but its config has not been created:"
    say "      sudo pxctl create $HUB"
    say "      sudo pxctl import $HUB <configdir>"
    return 1
  fi
  hub_setting_lines | sed 's/^/    /'
  confirm "write into $_f?" || return 1
  priv_cp "$_f" "$_f.bak-nmdcs"
  _tmpf=$(mktemp)
  priv_cat "$_f" >"$_tmpf"
  for k in TLSEnabled TLSProxyAddress PingerAddresses; do
    sed -i "/^#\{0,1\}$k[[:space:]]*=/d" "$_tmpf"
  done
  hub_setting_lines >>"$_tmpf"
  priv_write "$_f" <"$_tmpf"
  rm -f "$_tmpf"
  say "  written, old file kept as Settings.pxt.bak-nmdcs"
}

run_hub_console() {
  console_up || {
    manual_hub_settings
    return 1
  }
  ensure_tool socat || return 1
  hub_setting_chunk | sed 's/^/    /'
  confirm "send this over the console?" || return 1
  _tmpc=$(mktemp)
  hub_setting_chunk >"$_tmpc"
  priv_sh "socat -t5 - 'UNIX-CONNECT:/run/ptokax/$HUB-console.sock' < '$_tmpc'" || {
    rm -f "$_tmpc"
    return 1
  }
  rm -f "$_tmpc"

  sleep 1
  if hub_tls_enabled; then
    say "  applied"
    return 0
  fi
  say "  the chunk did not take. If the journal shows"
  say "      bad argument #1 to 'SetBool' (number expected, got nil)"
  say "  then ptokax@$HUB is an older build without TLSEnabled and needs"
  say "  the new binary installed before this can work."
  say "  journalctl PTOKAX_SUBSYSTEM=console for the actual error"
  return 1
}

run_conf() {
  [ -n "$STREAM_DIR" ] || {
    _cp=$(nginx_conf_prefix)
    [ -n "$_cp" ] || {
      say "  cannot work out the nginx config directory from nginx -V"
      return 1
    }
    STREAM_DIR=$_cp/stream.d
    CONFD_DIR=$_cp/conf.d
  }
  _d=$(hub_state_dir 2>/dev/null || true)
  priv_mkdir "$STREAM_DIR"
  sed -e "s|@TLSPORT@|$TLS_PORT|g" -e "s|@TCPPORT@|$TCP_PORT|g" \
    -e "s|@CERT@|$CERT|g" -e "s|@KEY@|$KEY|g" \
    -e "s|@PROXYADDR@|$PROXY_ADDR|g" -e "s|@HUBADDR@|$HUB_ADDR|g" \
    "$here/stream.conf" | priv_write "$STREAM_DIR/ptokax-nmdcs.conf"
  say "  wrote $STREAM_DIR/ptokax-nmdcs.conf"
  if [ -n "$CONFD_DIR" ] && [ -n "$_d" ]; then
    priv_mkdir "$CONFD_DIR"
    sed -e "s|@STATEDIR@|$_d|g" "$here/hubinfo.conf" | priv_write "$CONFD_DIR/ptokax-hubinfo.conf"
    say "  wrote $CONFD_DIR/ptokax-hubinfo.conf"
  fi
  say "  nginx.conf needs, outside http {}:"
  say "      stream { include $STREAM_DIR/*.conf; }"
}

run_user() {
  confirm "create system user $NGINX_USER?" || return 1
  priv useradd --system --no-create-home --shell /usr/sbin/nologin "$NGINX_USER"
}

run_unit() {
  _gen=$here/../systemd/unitgen.sh
  [ -x "$_gen" ] || {
    say "  unitgen.sh not found at $_gen"
    return 1
  }
  _d=$(hub_state_dir)
  _v=$(systemctl --version 2>/dev/null | sed -n '1s/^systemd \([0-9]*\).*/\1/p')
  [ -n "$_v" ] || _v=0
  "$_gen" --systemd-version="$_v" \
    --define="NGINXBIN=$(nginx_bin)" --define="NGINXUSER=$NGINX_USER" \
    --define="STATEDIR=$_d" --define="docdir=/usr/share/doc/ptokax" \
    <"$here/nginx.service.in" | priv_write /etc/systemd/system/nginx-ptokax.service || return 1
  say "  wrote nginx-ptokax.service for systemd $_v"
  priv systemctl daemon-reload
}

run_socket() {
  _dir=/etc/systemd/system/ptokax@$HUB.socket.d
  priv_mkdir "$_dir"
  printf '[Socket]\nListenStream=%s\nFileDescriptorName=proxy\n' "$PROXY_ADDR" |
    priv_write "$_dir/20-proxy.conf" || return 1
  say "  wrote $_dir/20-proxy.conf"
  priv systemctl daemon-reload
  hub_running && say "  takes effect when ptokax@$HUB next restarts"
  return 0
}

nginx_do() {
  "$(nginx_bin)" "$@" && return 0
  priv "$(nginx_bin)" "$@"
}

run_start() {
  [ -n "$(nginx_bin)" ] || {
    say "  no nginx binary"
    return 1
  }
  nginx_do -t || {
    say "  config test failed"
    return 1
  }
  if have_systemd && [ -f /etc/systemd/system/nginx-ptokax.service ]; then
    priv systemctl restart nginx-ptokax &&
      priv systemctl --no-pager --lines=3 status nginx-ptokax
  elif nginx_do -s reload; then
    say "  reloaded"
  else nginx_do && say "  started"; fi
}

# ============================================================================
# pages
# ============================================================================
page_nginx() {
  _own='NGINX_MODE NGINX_PREFIX BUILD_DIR NGINX_USER'
  snapshot $_own
  while :; do
    head2 "1  nginx"
    _pn_b=$(nginx_bin)
    row a "mode" "$NGINX_MODE" "auto, system or prefix"
    row b "prefix" "$NGINX_PREFIX" "a source build goes here"
    row c "source dir" "$BUILD_DIR" "git clone kept here"
    row d "runs as" "$NGINX_USER" "$(user_exists "$NGINX_USER" && echo exists || echo 'not created')"
    say ""
    row "" "binary" "${_pn_b:-none found}"
    row "" "stream" "$(nginx_has_stream && echo yes || echo no)" "required, off by default"
    say ""

    # --- Dynamic Run Action ---
    _st_nginx=$(step_state "nginx")
    case $_st_nginx in
    done) act x "run nginx step (already done)" ;;
    ready) act x "run nginx step now" ;;
    *) printf '%s    %-3s %s%s\n' "$DIM" "x" "run nginx step now ($_st_nginx)" "$OFF" ;;
    esac
    # --------------------------

    act r "reset this page"
    act s "return, keeping changes"
    act q "return, discarding them"
    menu
    case $_key in
    a) edit NGINX_MODE "mode" "auto prefers the prefix build, then PATH" auto system prefix ;;
    b) edit NGINX_PREFIX "prefix" "" ;;
    c) edit BUILD_DIR "source dir" "" ;;
    d) edit NGINX_USER "runs as" "User= and Group= on the unit, so nginx is never root" ;;
    x)
      if [ "$_st_nginx" = "ready" ] || [ "$_st_nginx" = "done" ]; then
        say ""
        say "== Running nginx step"
        run_build
        pause
      else
        say "  Step cannot be run yet: $_st_nginx"
        sleep 1
      fi
      ;;
    r) reset_vars $_own ;;
    s) return ;;
    q)
      restore
      return
      ;;
    *) say "  no such choice" ;;
    esac
  done
}

page_cert() {
  _own='CERT_METHOD HUB_ADDR CERT KEY CERT_CUSTOM CERT_CHALLENGE'
  snapshot $_own
  while :; do
    head2 "2  certificate"
    intro "$(cert_where)"
    row a "method" "$CERT_METHOD" "$([ "$CERT_METHOD" = letsencrypt ] && tool_note certbot)"
    row b "domain" "$HUB_ADDR" "name clients connect to"
    if [ "$(dirname "$CERT")" = "$(dirname "$KEY")" ]; then
      row c "cert" "$(basename "$CERT")" "$(file_note "$CERT")"
      row d "key" "$(basename "$KEY")" "$(file_note "$KEY")"
    else
      row c "cert" "$CERT" "$(file_note "$CERT")"
      row d "key" "$KEY" "$(file_note "$KEY")"
    fi
    [ "$CERT_METHOD" = letsencrypt ] &&
      row e "challenge" "$CERT_CHALLENGE" "$([ "$CERT_CHALLENGE" = http ] && echo 'needs inbound 80' || echo 'no inbound port')"
    say ""

    # --- Dynamic Run Action ---
    _st_cert=$(step_state "cert")
    case $_st_cert in
    done) act x "run cert step (already done)" ;;
    ready) act x "run cert step now" ;;
    *) printf '%s    %-3s %s%s\n' "$DIM" "x" "run cert step now ($_st_cert)" "$OFF" ;;
    esac
    # --------------------------

    act p "show the keyprint"
    act r "reset this page"
    act s "return, keeping changes"
    act q "return, discarding them"
    menu
    case $_key in
    a)
      edit CERT_METHOD "method" "selfsigned needs no network, DC++ users must opt in" letsencrypt selfsigned existing
      sync_cert_paths
      ;;
    b)
      edit HUB_ADDR "domain" ""
      sync_cert_paths
      ;;
    c)
      _cn=$(basename "$CERT")
      edit _cn "cert" "a name, or a whole path"
      case $_cn in
      /*)
        _old=$(dirname "$CERT")
        CERT=$_cn
        [ "$(dirname "$KEY")" = "$_old" ] && KEY=$(dirname "$CERT")/$(basename "$KEY")
        ;;
      *) CERT=$(dirname "$CERT")/$_cn ;;
      esac
      CERT_CUSTOM=yes
      ;;
    e) edit CERT_CHALLENGE "challenge" "http needs inbound port 80, dns proves it with a TXT record" http dns ;;
    d)
      _kn=$(basename "$KEY")
      edit _kn "key" "a name, or a whole path"
      case $_kn in /*) KEY=$_kn ;; *) KEY=$(dirname "$KEY")/$_kn ;; esac
      CERT_CUSTOM=yes
      ;;
    x)
      if [ "$_st_cert" = "ready" ] || [ "$_st_cert" = "done" ]; then
        say ""
        say "== Running cert step"
        run_cert
        pause
      else
        say "  Step cannot be run yet: $_st_cert"
        sleep 1
      fi
      ;;
    p)
      say ""
      show_keyprint
      pause
      ;;
    r)
      reset_vars $_own
      CERT_CUSTOM=no
      sync_cert_paths
      ;;
    s) return ;;
    q)
      restore
      return
      ;;
    *) say "  no such choice" ;;
    esac
  done
}

page_hub() {
  _own='HUB STATE_DIR TCP_PORT TLS_PORT ENABLE_CONSOLE'
  snapshot $_own
  while :; do
    head2 "3  Hub settings"
    if ! command -v pxctl >/dev/null 2>&1; then
      intro "pxctl is not installed, so there are no instances to choose from." \
        "Install the units first: make install, from the PtokaX source."
    elif [ -z "$HUB" ]; then
      intro "Which hub this is for. Press a to pick one, n to make one."
    fi
    row a "hub" "${HUB:-<none>}" "$([ -n "$HUB" ] && hub_status_of "$HUB")"
    row b "NMDCS port" "$TLS_PORT" "clients connect here"
    row c "plaintext port" "$TCP_PORT" "first entry in TCPPorts"
    row d "Lua console" "$ENABLE_CONSOLE" "$(console_enabled && echo 'socket enabled' || echo 'socket not enabled')"
    say ""
    _sd=$(hub_state_dir 2>/dev/null || true)
    row "" "state dir" "${_sd:-<none>}"
    row "" "proxy listener" "$PROXY_ADDR" "loopback, PtokaX reads the header here"
    say ""

    # --- Dynamic Run Action ---
    _st_hub=$(step_state "hub")
    case $_st_hub in
    done) act x "run hub settings step (already done)" ;;
    ready) act x "run hub settings step now" ;;
    *) printf '%s    %-3s %s%s\n' "$DIM" "x" "run hub settings step now ($_st_hub)" "$OFF" ;;
    esac
    # --------------------------

    act n "create a new hub with pxctl"
    act r "reset this page"
    act s "return, keeping changes"
    act q "return, discarding them"
    menu
    case $_key in
    a)
      choose_hub
      pause
      ;;
    b) edit TLS_PORT "NMDCS port" "above 1024 needs no capability" ;;
    c) edit TCP_PORT "plaintext port" "" ;;
    d) edit ENABLE_CONSOLE "Lua console" "a socket for pxconsole and socat, see ADMIN-GUIDE" yes no ;;
    x)
      if [ "$_st_hub" = "ready" ] || [ "$_st_hub" = "done" ]; then
        say ""
        say "== Running hub settings step"
        run_hub
        pause
      else
        say "  Step cannot be run yet: $_st_hub"
        sleep 1
      fi
      ;;
    n)
      create_hub
      pause
      ;;
    r) reset_vars $_own ;;
    s) return ;;
    q)
      restore
      return
      ;;
    *) say "  no such choice" ;;
    esac
  done
}

choose_hub() {
  _names=$(hub_names) || {
    say "  pxctl not found, so type the name"
    edit HUB "hub" ""
    return 0
  }
  [ -n "$_names" ] || {
    say "  systemd knows no ptokax instances, use n to make one"
    return 1
  }
  say ""
  _i=0
  for _h in $_names; do
    _i=$((_i + 1))
    printf '    %-3s %-16s %s\n' "$_i" "$_h" "$(hub_status_of "$_h")"
  done
  printf '\n  number, or enter to leave it as %s: ' "${HUB:-none}"
  read -r _pick || return 1
  [ -n "$_pick" ] || return 0
  _i=0
  for _h in $_names; do
    _i=$((_i + 1))
    if [ "$_i" = "$_pick" ]; then
      HUB=$_h
      STATE_DIR=
      say "  hub is $HUB"
      return 0
    fi
  done
  say "  no such number"
}

create_hub() {
  command -v pxctl >/dev/null 2>&1 || {
    say "  pxctl not found"
    return 1
  }
  printf '  name for the new hub: '
  read -r _new || return 1
  [ -n "$_new" ] || return 0
  priv pxctl create "$_new" || {
    say "  pxctl create failed"
    return 1
  }
  HUB=$_new
  STATE_DIR=
  say "  created $HUB"
}

page_verify() {
  head2 "verify"
  say "  listening"
  command -v ss >/dev/null 2>&1 &&
    { ss -ltn 2>/dev/null | grep -E ":($TLS_PORT|$TCP_PORT|${PROXY_ADDR##*:})\b" ||
      say "    nothing on $TLS_PORT, $TCP_PORT or ${PROXY_ADDR##*:}"; }
  say ""
  say "  TLS and ALPN on $HUB_ADDR:$TLS_PORT"
  command -v openssl >/dev/null 2>&1 &&
    { printf '' | openssl s_client -alpn nmdc -connect "$HUB_ADDR:$TLS_PORT" 2>/dev/null |
      grep -E "ALPN protocol|subject=|Verify return code" || say "    no answer"; }
  say ""
  say "  pinger endpoint"
  command -v curl >/dev/null 2>&1 &&
    {
      curl -sSk --http1.1 --max-time 5 "https://$HUB_ADDR:$TLS_PORT/api/v0/hubinfo.json" || say "    no answer"
      say ""
    }
  pause
}

# --- main -------------------------------------------------------------------
plan_summary() {
  _r=0
  _b=0
  for st in $STEPS; do
    case $(step_state "$st") in
    done) ;;
    ready) _r=$((_r + 1)) ;;
    *) _b=$((_b + 1)) ;;
    esac
  done
  if [ $_r -eq 0 ] && [ $_b -eq 0 ]; then
    printf 'everything done'
  elif [ $_b -eq 0 ]; then
    printf '%d to run' "$_r"
  else printf '%d to run, %d blocked' "$_r" "$_b"; fi
}

main_menu() {
  while :; do
    head2 "PtokaX NMDCS setup"
    intro "Pages record choices. Nothing changes until you run the plan."
    row 1 "nginx" "$NGINX_MODE, $NGINX_PREFIX, runs as $NGINX_USER"
    row 2 "certificate" "$CERT_METHOD, $HUB_ADDR"
    row 3 "hub settings" "${HUB:-<none>}, NMDCS on $TLS_PORT"
    say ""
    act p "plan and run          $(plan_summary)"
    act v "verify a running setup"
    act R "reset everything"
    act q "quit"
    menu
    case $_key in
    1) page_nginx ;; 2) page_cert ;; 3) page_hub ;;
    p) page_plan ;; v) page_verify ;;
    R) confirm "reset every setting?" && set_defaults ;;
    q | Q) exit 0 ;;
    esac
  done
}

case ${1:-} in
-h | --help)
  printf 'Usage: %s [step]\n\nInteractive by default, or run a single step directly.\nSteps: %s\n' "$self" "$STEPS"
  exit 0
  ;;
*)
  if [ -n "${1:-}" ]; then
    for st in $STEPS; do
      if [ "$st" = "$1" ]; then
        say "== Running single step: $1 ($(step_label "$1"))"
        step_run "$1"
        exit $?
      fi
    done
    die "unknown step '$1'. Available steps: $STEPS"
  fi
  ;;
esac

main_menu
