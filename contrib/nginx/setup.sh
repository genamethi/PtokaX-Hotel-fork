#!/bin/sh
# Interactive setup for NMDCS in front of PtokaX.
#
# Each item stands on its own. Only "nginx config" needs nginx and a certificate
# first. Settings are kept between runs, so backing out of a page loses nothing.
#
# Privileged actions are named before they run and are the only ones using sudo.
set -eu

self=${0##*/}
here=$(cd "$(dirname "$0")" && pwd)

CONF=${PX_NGINX_SETUP_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/ptokax-nginx-setup.conf}

# --- settings, overridden by CONF -------------------------------------------
NGINX_PREFIX=/usr/local/nginx
NGINX_USER=nginx
NGINX_MODE=auto # auto, system, prefix
BUILD_DIR=/usr/local/src/nginx
TLS_PORT=5411
PROXY_ADDR=127.0.0.1:5411
TCP_PORT=411
HUB=
STATE_DIR=
HUB_ADDR=hub.example.com
CERT_METHOD=letsencrypt # letsencrypt, selfsigned, existing
CERT=/etc/ssl/ptokax/hub.crt
KEY=/etc/ssl/ptokax/hub.key
STREAM_DIR=
CONFD_DIR=
USE_SYSTEMD=auto # auto, yes, no

[ -f "$CONF" ] && . "$CONF"

save_conf() {
  mkdir -p "$(dirname "$CONF")"
  {
    echo "# written by $self"
    for v in NGINX_PREFIX NGINX_USER NGINX_MODE BUILD_DIR TLS_PORT PROXY_ADDR TCP_PORT \
      HUB STATE_DIR HUB_ADDR CERT_METHOD CERT KEY STREAM_DIR CONFD_DIR USE_SYSTEMD; do
      eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\""
    done
  } >"$CONF"
}

quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# --- small helpers ----------------------------------------------------------
die() {
  printf '%s: %s\n' "$self" "$1" >&2
  exit 1
}
say() { printf '%s\n' "$1"; }
pause() {
  printf '\n  press enter '
  read -r _dummy || true
}

ask() {
  # ask <prompt> <current>
  printf '  %s [%s]: ' "$1" "$2" >&2
  read -r _a || _a=
  [ -n "$_a" ] && printf '%s' "$_a" || printf '%s' "$2"
}

confirm() {
  printf '  %s [y/N] ' "$1"
  read -r _c || _c=n
  case $_c in y | Y | yes) return 0 ;; *) return 1 ;; esac
}

priv() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    printf '  sudo: %s\n' "$*"
    sudo "$@"
  else
    die "need root for: $*"
  fi
}

# true when the current user can already create or replace this path
can_write() {
  if [ -e "$1" ]; then
    [ -w "$1" ]
  else
    [ -w "$(dirname "$1")" ]
  fi
}

priv_write() {
  # priv_write <dest>, content on stdin. sudo only when the path needs it.
  if can_write "$1"; then
    cat >"$1"
  elif [ "$(id -u)" -eq 0 ]; then
    cat >"$1"
  elif command -v sudo >/dev/null 2>&1; then
    printf '  sudo: write %s\n' "$1"
    sudo tee "$1" >/dev/null
  else
    die "need root to write $1"
  fi
}

priv_cp() {
  if can_write "$2"; then
    cp "$1" "$2"
  else
    priv cp "$1" "$2"
  fi
}

priv_cat() {
  if [ -r "$1" ]; then
    cat "$1"
  else
    priv cat "$1"
  fi
}

priv_mkdir() {
  if can_write "$1"; then
    mkdir -p "$1"
  else
    priv mkdir -p "$1"
  fi
}

have_systemd() {
  case $USE_SYSTEMD in
  yes) return 0 ;;
  no) return 1 ;;
  *) command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] ;;
  esac
}

# --- nginx discovery --------------------------------------------------------
nginx_bin() {
  case $NGINX_MODE in
  prefix) printf '%s/sbin/nginx' "$NGINX_PREFIX" ;;
  system) command -v nginx 2>/dev/null || true ;;
  *)
    if [ -x "$NGINX_PREFIX/sbin/nginx" ]; then
      printf '%s/sbin/nginx' "$NGINX_PREFIX"
    else
      command -v nginx 2>/dev/null || true
    fi
    ;;
  esac
}

nginx_has_stream() {
  b=$(nginx_bin)
  [ -n "$b" ] && [ -x "$b" ] || return 1
  v=$("$b" -V 2>&1) || return 1
  printf '%s' "$v" | grep -q -- '--with-stream' || return 1
  printf '%s' "$v" | grep -q -- '--with-stream_ssl_module'
}

nginx_conf_prefix() {
  b=$(nginx_bin)
  [ -n "$b" ] && [ -x "$b" ] || return 1
  "$b" -V 2>&1 | tr ' ' '\n' | sed -n 's/^--conf-path=//p' | sed 's:/[^/]*$::'
}

# --- status lines -----------------------------------------------------------
st_nginx() {
  b=$(nginx_bin)
  if [ -z "$b" ] || [ ! -x "$b" ]; then
    echo "not found"
  elif nginx_has_stream; then
    echo "ok, $b"
  else
    echo "no stream module, $b"
  fi
}

st_cert() {
  if [ -s "$CERT" ] && [ -s "$KEY" ]; then
    echo "present, $CERT_METHOD"
  else
    echo "not created, $CERT_METHOD"
  fi
}

st_hub() {
  [ -n "$HUB" ] || {
    echo "no hub selected"
    return
  }
  d=$(hub_state_dir 2>/dev/null || true)
  [ -n "$d" ] || {
    echo "$HUB, state dir unknown"
    return
  }
  priv_test_dir "$d" || {
    echo "$HUB, no state tree"
    return
  }
  if grep -q '^TLSEnabled[[:space:]]*=[[:space:]]*1' "$d/cfg/Settings.pxt" 2>/dev/null; then
    echo "$HUB, TLSEnabled=1"
  else
    echo "$HUB, not enabled"
  fi
}

st_conf() {
  [ -n "$STREAM_DIR" ] || {
    echo "not written"
    return
  }
  if [ -f "$STREAM_DIR/ptokax-nmdcs.conf" ]; then
    echo "installed in $STREAM_DIR"
  else
    echo "not written"
  fi
}

st_systemd() {
  have_systemd || {
    echo "not using systemd"
    return
  }
  s=""
  [ -f /etc/systemd/system/nginx-ptokax.service ] && s="nginx unit"
  if [ -n "$HUB" ] && [ -f "/etc/systemd/system/ptokax@$HUB.socket.d/20-proxy.conf" ]; then
    s="${s:+$s, }proxy socket"
  fi
  echo "${s:-nothing installed}"
}

hub_state_dir() {
  if [ -n "$STATE_DIR" ]; then
    printf '%s' "$STATE_DIR"
  elif command -v pxctl >/dev/null 2>&1 && [ -n "$HUB" ]; then
    pxctl get "$HUB" statedir 2>/dev/null
  fi
}

# --- page 1, nginx ----------------------------------------------------------
page_nginx() {
  while :; do
    cat <<EOF

  nginx
  -----
    binary        $(nginx_bin)
    stream        $(nginx_has_stream && echo yes || echo no)

    a  mode              $NGINX_MODE      (auto, system, prefix)
    b  prefix            $NGINX_PREFIX
    c  build source dir  $BUILD_DIR
    u  run as user       $NGINX_USER      $(id -u "$NGINX_USER" >/dev/null 2>&1 && echo exists || echo 'does not exist')

    i  build and install from source
    S  save and back
    B  back

EOF
    printf '  > '
    read -r c || c=B
    case $c in
    a) NGINX_MODE=$(ask "mode" "$NGINX_MODE") ;;
    b) NGINX_PREFIX=$(ask "prefix" "$NGINX_PREFIX") ;;
    c) BUILD_DIR=$(ask "source dir" "$BUILD_DIR") ;;
    u) NGINX_USER=$(ask "user" "$NGINX_USER") ;;
    i)
      do_build_nginx
      pause
      ;;
    S)
      save_conf
      return
      ;;
    B) return ;;
    esac
  done
}

do_build_nginx() {
  command -v git >/dev/null 2>&1 || die "git not found"

  say ""
  say "  nginx is built with:"
  say "    ./configure --prefix=$NGINX_PREFIX --with-stream --with-stream_ssl_module"
  say ""
  confirm "clone and build into $BUILD_DIR?" || return 0

  priv mkdir -p "$(dirname "$BUILD_DIR")"

  if [ -d "$BUILD_DIR/.git" ]; then
    say "  updating $BUILD_DIR"
    priv git -C "$BUILD_DIR" pull --ff-only
  else
    say "  cloning nginx"
    priv git clone --depth 1 https://github.com/nginx/nginx.git "$BUILD_DIR"
  fi

  say "  configuring"
  # paths match RuntimeDirectory, StateDirectory and LogsDirectory in the unit,
  # so an unprivileged nginx can write all of them
  priv sh -c "cd '$BUILD_DIR' && auto/configure --prefix='$NGINX_PREFIX' \
		--with-stream --with-stream_ssl_module --with-http_ssl_module \
		--user='$NGINX_USER' --group='$NGINX_USER' \
		--pid-path=/run/nginx/nginx.pid \
		--error-log-path=/var/log/nginx/error.log \
		--http-log-path=/var/log/nginx/access.log \
		--http-client-body-temp-path=/var/lib/nginx/client_body \
		--http-proxy-temp-path=/var/lib/nginx/proxy"

  say "  building"
  priv sh -c "cd '$BUILD_DIR' && make -j\$(nproc 2>/dev/null || echo 2)"

  confirm "install to $NGINX_PREFIX?" || return 0
  priv sh -c "cd '$BUILD_DIR' && make install"

  NGINX_MODE=prefix
  save_conf
  say "  installed, $(nginx_bin)"
}

# --- page 2, certificate ----------------------------------------------------
page_cert() {
  while :; do
    cat <<EOF

  certificate
  -----------
    ncdc stores the keyprint on first connect and asks the user to /accept when it
    changes. DC++ does not pin: without a CA-signed certificate it connects only if
    the user enabled untrusted hubs, or the address carries ?kp=SHA256/...

    a  method     $CERT_METHOD    (letsencrypt, selfsigned, existing)
    b  domain     $HUB_ADDR
    c  cert       $CERT
    d  key        $KEY

    i  obtain or generate now
    p  print the keyprint of the current certificate
    S  save and back
    B  back

EOF
    printf '  > '
    read -r c || c=B
    case $c in
    a) CERT_METHOD=$(ask "method" "$CERT_METHOD") ;;
    b) HUB_ADDR=$(ask "domain" "$HUB_ADDR") ;;
    c) CERT=$(ask "cert" "$CERT") ;;
    d) KEY=$(ask "key" "$KEY") ;;
    i)
      do_cert
      pause
      ;;
    p)
      show_keyprint
      pause
      ;;
    S)
      save_conf
      return
      ;;
    B) return ;;
    esac
  done
}

do_cert() {
  case $CERT_METHOD in
  letsencrypt)
    command -v certbot >/dev/null 2>&1 || {
      say "  certbot not found"
      return 0
    }
    confirm "run certbot for $HUB_ADDR?" || return 0
    priv certbot certonly --standalone -d "$HUB_ADDR"
    CERT=/etc/letsencrypt/live/$HUB_ADDR/fullchain.pem
    KEY=/etc/letsencrypt/live/$HUB_ADDR/privkey.pem
    save_conf
    say "  renewal keeps the key, so the keyprint does not change"
    ;;
  selfsigned)
    command -v openssl >/dev/null 2>&1 || die "openssl not found"
    confirm "generate a self-signed certificate for $HUB_ADDR?" || return 0
    priv_mkdir "$(dirname "$CERT")"
    priv_mkdir "$(dirname "$KEY")"
    priv openssl req -new -newkey rsa:4096 -x509 -sha256 -days 1800 -nodes \
      -subj "/CN=$HUB_ADDR" -addext "subjectAltName=DNS:$HUB_ADDR" \
      -out "$CERT" -keyout "$KEY"
    priv chmod 600 "$KEY"
    say ""
    say "  DC++ users need untrusted hubs enabled, or this address:"
    say "    nmdcs://$HUB_ADDR:$TLS_PORT?kp=$(keyprint_of)"
    ;;
  existing)
    say "  using $CERT and $KEY as given"
    ;;
  esac
}

keyprint_of() {
  [ -s "$CERT" ] || {
    printf 'SHA256/<no certificate>'
    return
  }
  h=$(openssl x509 -in "$CERT" -outform der 2>/dev/null | openssl dgst -sha256 -binary |
    base32 2>/dev/null | tr -d '=\n') || h=
  [ -n "$h" ] && printf 'SHA256/%s' "$h" || printf 'SHA256/<base32 unavailable>'
}

show_keyprint() {
  say ""
  say "  $(keyprint_of)"
  say ""
  say "  ncdc and DC++ both accept this in the address:"
  say "    nmdcs://$HUB_ADDR:$TLS_PORT?kp=$(keyprint_of)"
}

# --- page 3, hub settings ---------------------------------------------------
# Settings are never edited by hand. Two supported paths, picked by what is enabled:
#
#   hub stopped            write cfg/Settings.pxt at the pxctl state dir
#   hub running + console  SetMan through pxconsole, no downtime
#
# The console socket has Service=ptokax@%i and RemoveOnStop=yes, so it exists only
# while the hub runs, and systemd refuses to enable it while the service is up.
# Enabling it therefore costs one stop, which is only ever done after a prompt.

rung_units() { command -v pxctl >/dev/null 2>&1; }
# pxctl get statedir only formats a path and always exits 0, so the tree itself
# is what says whether the instance exists
rung_instance() {
  _d=$(hub_state_dir 2>/dev/null || true)
  [ -n "$HUB" ] && [ -n "$_d" ] && priv_test_dir "$_d"
}

# the tree is 0700 root under DynamicUser, so an unprivileged test -d says no
priv_test_dir() {
  if [ -d "$1" ]; then
    return 0
  elif [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo -n test -d "$1" 2>/dev/null
  else
    return 1
  fi
}
rung_running() { have_systemd && [ -n "$HUB" ] && systemctl is-active --quiet "ptokax@$HUB" 2>/dev/null; }
rung_console() { [ -n "$HUB" ] && [ -S "/run/ptokax/$HUB-console.sock" ]; }
rung_tooling() { command -v pxconsole >/dev/null 2>&1 || command -v socat >/dev/null 2>&1; }

report_rungs() {
  say ""
  say "  units installed   $(rung_units && echo yes || echo 'no, run make install')"
  say "  instance          $(rung_instance && echo yes || echo 'no, pxctl create <hub>')"
  say "  hub running       $(rung_running && echo yes || echo no)"
  say "  console socket    $(rung_console && echo yes || echo no)"
  say "  socat/pxconsole   $(rung_tooling && echo yes || echo no)"
}

page_hub() {
  while :; do
    d=$(hub_state_dir 2>/dev/null || true)
    cat <<EOF

  hub settings
  ------------
    state dir   ${d:-unknown}
    hub         $(rung_running && echo running || echo stopped)$(rung_console && echo ', console up' || echo '')

    a  hub name         ${HUB:-<none>}
    b  state dir        ${STATE_DIR:-<from pxctl>}
    c  TLSProxyAddress  $PROXY_ADDR
    d  plaintext port   $TCP_PORT
    e  NMDCS port       $TLS_PORT

    l  list hubs known to systemd
    k  what is enabled
    i  apply the settings
    m  print the settings without applying
    S  save and back
    B  back

EOF
    printf '  > '
    read -r c || c=B
    case $c in
    a) HUB=$(ask "hub name" "$HUB") ;;
    b) STATE_DIR=$(ask "state dir" "$STATE_DIR") ;;
    c) PROXY_ADDR=$(ask "TLSProxyAddress" "$PROXY_ADDR") ;;
    d) TCP_PORT=$(ask "plaintext port" "$TCP_PORT") ;;
    e) TLS_PORT=$(ask "NMDCS port" "$TLS_PORT") ;;
    l)
      list_hubs
      pause
      ;;
    k)
      report_rungs
      pause
      ;;
    i)
      apply_hub_settings
      pause
      ;;
    m)
      print_hub_settings
      pause
      ;;
    S)
      save_conf
      return
      ;;
    B) return ;;
    esac
  done
}

list_hubs() {
  say ""
  if rung_units; then
    pxctl list || say "  pxctl list failed"
  else
    say "  pxctl not found. The units are not installed, so there is no hub"
    say "  registry to read. See ADMIN-GUIDE, \"pxctl\"."
  fi
}

hub_setting_lines() {
  cat <<EOF
TLSEnabled	=	1
TLSProxyAddress	=	$PROXY_ADDR
PingerAddresses	=	nmdcs://$HUB_ADDR:$TLS_PORT;dchub://$HUB_ADDR:$TCP_PORT
EOF
}

hub_setting_chunk() {
  cat <<EOF
SetMan.SetBool(SetMan.tBooleans.TLSEnabled, true)
SetMan.SetString(SetMan.tStrings.TLSProxyAddress, "$PROXY_ADDR")
SetMan.SetString(SetMan.tStrings.PingerAddresses, "nmdcs://$HUB_ADDR:$TLS_PORT;dchub://$HUB_ADDR:$TCP_PORT")
SetMan.Save()
EOF
}

print_hub_settings() {
  d=$(hub_state_dir 2>/dev/null || true)
  say ""
  say "  with the hub stopped, in ${d:-<state dir>}/cfg/Settings.pxt:"
  say ""
  hub_setting_lines | sed 's/^/    /'
  say ""
  say "  or against a running hub, through the console socket:"
  say ""
  hub_setting_chunk | sed 's/^/    /'
}

apply_hub_settings() {
  rung_units || {
    say "  pxctl not found, see ADMIN-GUIDE \"pxctl\""
    return 0
  }
  rung_instance || {
    say "  no state dir for ${HUB:-<hub>}; pxctl create <hub> first"
    return 0
  }

  if rung_running; then
    apply_via_console
  else
    apply_via_file
  fi
}

apply_via_file() {
  d=$(hub_state_dir)
  f=$d/cfg/Settings.pxt
  [ -f "$f" ] || {
    say "  no $f"
    return 0
  }

  say ""
  say "  ptokax@$HUB is stopped, so the file is written directly."
  confirm "write $f?" || {
    say "  nothing changed"
    return 0
  }

  priv_cp "$f" "$f.bak-nmdcs"

  tmp=$(mktemp)
  priv_cat "$f" >"$tmp"

  for key in TLSEnabled TLSProxyAddress PingerAddresses; do
    sed -i "/^#\{0,1\}$key[[:space:]]*=/d" "$tmp"
  done
  hub_setting_lines >>"$tmp"

  priv_write "$f" <"$tmp"
  rm -f "$tmp"

  say "  written, previous file kept as Settings.pxt.bak-nmdcs"
  return 0
}

apply_via_console() {
  if ! rung_console; then
    say ""
    say "  ptokax@$HUB is running and the console socket is not up."
    say "  systemd refuses to enable a socket whose service is already running,"
    say "  so this costs one stop and start. Nothing happens if you decline."
    say ""
    confirm "stop ptokax@$HUB, enable the console socket, start it again?" || {
      say "  nothing changed. The other way is to stop the hub and use this"
      say "  page again, which writes Settings.pxt directly."
      return 0
    }

    priv systemctl stop "ptokax@$HUB" || {
      say "  stop failed, nothing else attempted"
      return 0
    }

    if ! priv systemctl enable --now "ptokax-console@$HUB.socket"; then
      say "  enable failed. Starting the hub again and leaving it as it was."
      priv systemctl start "ptokax@$HUB" || true
      return 0
    fi

    priv systemctl start "ptokax@$HUB" || {
      say "  start failed, check journalctl -u ptokax@$HUB"
      return 0
    }

    # the socket is created by the service coming up
    i=0
    while [ $i -lt 10 ] && ! rung_console; do
      sleep 1
      i=$((i + 1))
    done

    rung_console || {
      say "  console socket still not present, giving up"
      return 0
    }
    say "  console socket up. It comes back with sockets.target from now on."
  fi

  rung_tooling || {
    say "  needs socat or pxconsole, see ADMIN-GUIDE \"Lua console\""
    return 0
  }

  say ""
  say "  sending through the console, no restart:"
  hub_setting_chunk | sed 's/^/    /'
  say ""
  confirm "send it?" || {
    say "  nothing changed"
    return 0
  }

  tmp=$(mktemp)
  hub_setting_chunk >"$tmp"

  if command -v socat >/dev/null 2>&1; then
    priv sh -c "socat -t5 - 'UNIX-CONNECT:/run/ptokax/$HUB-console.sock' < '$tmp'" ||
      say "  send failed"
  else
    priv sh -c "pxconsole '$HUB' attach '$tmp'" || say "  send failed"
  fi

  rm -f "$tmp"
  say "  SetMan.Save() writes cfg/ immediately, so this survives a restart."
  say "  journalctl PTOKAX_SUBSYSTEM=console shows the output."
  return 0
}

# --- page 4, nginx config ---------------------------------------------------
page_conf() {
  while :; do
    cat <<EOF

  nginx config
  ------------
    stream {} is a sibling of http {}, so the stream file needs its own include at
    the top level of nginx.conf. The pinger snippet goes in conf.d, inside http {}.

    a  stream dir   ${STREAM_DIR:-<detect>}
    b  conf.d dir   ${CONFD_DIR:-<detect>}

    d  detect from $(nginx_bin) -V
    i  write both files
    t  nginx -t
    S  save and back
    B  back

EOF
    printf '  > '
    read -r c || c=B
    case $c in
    a) STREAM_DIR=$(ask "stream dir" "$STREAM_DIR") ;;
    b) CONFD_DIR=$(ask "conf.d dir" "$CONFD_DIR") ;;
    d)
      detect_conf_dirs
      pause
      ;;
    i)
      write_conf
      pause
      ;;
    t)
      priv "$(nginx_bin)" -t || true
      pause
      ;;
    S)
      save_conf
      return
      ;;
    B) return ;;
    esac
  done
}

detect_conf_dirs() {
  p=$(nginx_conf_prefix 2>/dev/null || true)
  [ -n "$p" ] || {
    say "  could not read --conf-path"
    return 0
  }
  STREAM_DIR=$p/stream.d
  CONFD_DIR=$p/conf.d
  save_conf
  say "  stream dir  $STREAM_DIR"
  say "  conf.d dir  $CONFD_DIR"
}

write_conf() {
  [ -n "$STREAM_DIR" ] || {
    say "  set or detect the stream dir first"
    return 0
  }
  d=$(hub_state_dir 2>/dev/null || true)

  priv_mkdir "$STREAM_DIR"
  sed -e "s|@TLSPORT@|$TLS_PORT|g" \
    -e "s|@TCPPORT@|$TCP_PORT|g" \
    -e "s|@CERT@|$CERT|g" \
    -e "s|@KEY@|$KEY|g" \
    -e "s|@PROXYADDR@|$PROXY_ADDR|g" \
    -e "s|@HUBADDR@|$HUB_ADDR|g" \
    "$here/stream.conf" | priv_write "$STREAM_DIR/ptokax-nmdcs.conf"
  say "  wrote $STREAM_DIR/ptokax-nmdcs.conf"

  if [ -n "$CONFD_DIR" ] && [ -n "$d" ]; then
    priv_mkdir "$CONFD_DIR"
    sed -e "s|@STATEDIR@|$d|g" "$here/hubinfo.conf" |
      priv_write "$CONFD_DIR/ptokax-hubinfo.conf"
    say "  wrote $CONFD_DIR/ptokax-hubinfo.conf"
  else
    say "  pinger snippet skipped, needs conf.d dir and hub state dir"
  fi

  say ""
  say "  nginx.conf needs this at the top level, outside http {}:"
  say ""
  say "    stream {"
  say "        include $STREAM_DIR/*.conf;"
  say "    }"
  save_conf
}

# --- page 5, systemd --------------------------------------------------------
page_systemd() {
  while :; do
    cat <<EOF

  systemd
  -------
    use systemd   $USE_SYSTEMD  (auto, yes, no) -> $(have_systemd && echo yes || echo no)

    a  toggle use systemd
    p  install the proxy socket drop-in for ptokax@${HUB:-<hub>}
    n  install a hardened unit for the source-built nginx
    r  start or restart nginx
    x  start nginx directly, without systemd
    S  save and back
    B  back

EOF
    printf '  > '
    read -r c || c=B
    case $c in
    a) USE_SYSTEMD=$(ask "use systemd" "$USE_SYSTEMD") ;;
    p)
      install_proxy_socket
      pause
      ;;
    n)
      install_nginx_unit
      pause
      ;;
    r)
      restart_nginx
      pause
      ;;
    x)
      start_nginx_direct
      pause
      ;;
    S)
      save_conf
      return
      ;;
    B) return ;;
    esac
  done
}

install_proxy_socket() {
  have_systemd || {
    say "  systemd is off for this run"
    return 0
  }
  [ -n "$HUB" ] || {
    say "  set a hub name first"
    return 0
  }

  if [ ! -f "/etc/systemd/system/ptokax@.socket" ] && [ ! -f "/usr/lib/systemd/system/ptokax@.socket" ]; then
    say "  ptokax@.socket is not installed, so socket activation is not in use."
    say "  PtokaX binds TLSProxyAddress itself in that case and this drop-in is"
    say "  not needed. Install the units with: make install"
    return 0
  fi

  dir=/etc/systemd/system/ptokax@$HUB.socket.d
  priv mkdir -p "$dir"
  printf '[Socket]\nListenStream=%s\nFileDescriptorName=proxy\n' "$PROXY_ADDR" |
    priv_write "$dir/20-proxy.conf"
  say "  wrote $dir/20-proxy.conf"
  priv systemctl daemon-reload
  confirm "restart ptokax@$HUB.socket now?" && priv systemctl restart "ptokax@$HUB.socket"
  return 0
}

install_nginx_unit() {
  have_systemd || {
    say "  systemd is off for this run"
    return 0
  }
  d=$(hub_state_dir 2>/dev/null || true)
  [ -n "$d" ] || {
    say "  state dir unknown, needed for ReadOnlyPaths"
    return 0
  }

  gen=$here/../systemd/unitgen.sh
  [ -x "$gen" ] || {
    say "  unitgen.sh not found at $gen"
    return 0
  }

  v=$(systemctl --version 2>/dev/null | sed -n '1s/^systemd \([0-9]*\).*/\1/p')
  [ -n "$v" ] || v=0

  if ! id -u "$NGINX_USER" >/dev/null 2>&1; then
    say "  user $NGINX_USER does not exist"
    confirm "create it as a system user?" || return 0
    priv useradd --system --no-create-home --shell /usr/sbin/nologin "$NGINX_USER" ||
      {
        say "  useradd failed"
        return 0
      }
  fi

  "$gen" --systemd-version="$v" \
    --define="NGINXBIN=$(nginx_bin)" \
    --define="NGINXUSER=$NGINX_USER" \
    --define="STATEDIR=$d" \
    --define="docdir=/usr/share/doc/ptokax" \
    <"$here/nginx.service.in" | priv_write /etc/systemd/system/nginx-ptokax.service

  say "  wrote /etc/systemd/system/nginx-ptokax.service for systemd $v"
  priv systemctl daemon-reload

  command -v systemd-analyze >/dev/null 2>&1 &&
    systemd-analyze verify /etc/systemd/system/nginx-ptokax.service || true
  return 0
}

restart_nginx() {
  have_systemd || {
    say "  systemd is off, use the direct option"
    return 0
  }
  unit=nginx-ptokax
  [ -f /etc/systemd/system/nginx-ptokax.service ] || unit=nginx
  priv "$(nginx_bin)" -t || {
    say "  config test failed, not restarting"
    return 0
  }
  priv systemctl restart "$unit"
  priv systemctl --no-pager --lines=5 status "$unit" || true
  return 0
}

start_nginx_direct() {
  b=$(nginx_bin)
  [ -n "$b" ] || {
    say "  nginx not found"
    return 0
  }
  priv "$b" -t || {
    say "  config test failed"
    return 0
  }
  if priv "$b" -s reload 2>/dev/null; then
    say "  reloaded"
  else
    priv "$b"
    say "  started"
  fi
  return 0
}

# --- page 6, verify ---------------------------------------------------------
page_verify() {
  say ""
  say "  listening"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -E ":($TLS_PORT|$TCP_PORT|${PROXY_ADDR##*:})\b" || say "    nothing on $TLS_PORT, $TCP_PORT, ${PROXY_ADDR##*:}"
  fi

  say ""
  say "  TLS and ALPN on $HUB_ADDR:$TLS_PORT"
  if command -v openssl >/dev/null 2>&1; then
    printf '' | openssl s_client -alpn nmdc -connect "$HUB_ADDR:$TLS_PORT" 2>/dev/null |
      grep -E "ALPN protocol|subject=|issuer=|Verify return code" || say "    no answer"
  fi

  say ""
  say "  pinger endpoint"
  if command -v curl >/dev/null 2>&1; then
    curl -sS --max-time 5 "http://$HUB_ADDR/api/v0/hubinfo.json" || say "    no answer"
    say ""
  fi

  d=$(hub_state_dir 2>/dev/null || true)
  if [ -n "$d" ] && [ -f "$d/hubinfo.json" ]; then
    say ""
    say "  $d/hubinfo.json exists"
  elif [ -n "$d" ]; then
    say ""
    say "  no $d/hubinfo.json yet; it is written 60s after start when"
    say "  PingerAddresses is set"
  fi
  pause
}

# --- main menu --------------------------------------------------------------
main_menu() {
  while :; do
    cat <<EOF

  PtokaX NMDCS setup
  ==================
    1  nginx           $(st_nginx)
    2  certificate     $(st_cert)
    3  hub settings    $(st_hub)
    4  nginx config    $(st_conf)
    5  systemd         $(st_systemd)
    6  verify

    settings kept in $CONF

    Q  quit

EOF
    printf '  > '
    read -r c || c=Q
    case $c in
    1) page_nginx ;;
    2) page_cert ;;
    3) page_hub ;;
    4) page_conf ;;
    5) page_systemd ;;
    6) page_verify ;;
    Q | q) exit 0 ;;
    esac
  done
}

case ${1:-} in
-h | --help)
  cat <<EOF
Usage: $self

Interactive. Settings are kept in $CONF and reused on the next run.
Override that path with PX_NGINX_SETUP_CONF.
EOF
  exit 0
  ;;
esac

main_menu
