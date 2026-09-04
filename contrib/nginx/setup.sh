#!/bin/sh
# Interactive setup for NMDCS in front of PtokaX.
#
# Pages 1 to 5 only record choices. Nothing on the host changes until the plan
# is run from the main menu, which is the single point where anything happens.
#
# -e is deliberately absent: a failed step reports and returns to the menu
# rather than dropping the admin to a shell partway through.
set -u

self=${0##*/}
here=$(cd "$(dirname "$0")" && pwd)

CONF=${PX_NGINX_SETUP_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/ptokax-nginx-setup.conf}

VARS='NGINX_PREFIX NGINX_USER NGINX_MODE BUILD_DIR TLS_PORT PROXY_ADDR TCP_PORT
      HUB STATE_DIR HUB_ADDR CERT_METHOD CERT KEY STREAM_DIR CONFD_DIR USE_SYSTEMD'

set_defaults() {
	NGINX_PREFIX=/usr/local/nginx
	NGINX_USER=nginx
	NGINX_MODE=auto
	BUILD_DIR=/usr/local/src/nginx
	TLS_PORT=5411
	PROXY_ADDR=127.0.0.1:5411
	TCP_PORT=411
	HUB=
	STATE_DIR=
	HUB_ADDR=hub.example.com
	CERT_METHOD=selfsigned
	CERT=/etc/ssl/ptokax/hub.crt
	KEY=/etc/ssl/ptokax/hub.key
	STREAM_DIR=
	CONFD_DIR=
	USE_SYSTEMD=auto
}

set_defaults
[ -f "$CONF" ] && . "$CONF"

quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

save_conf() {
	mkdir -p "$(dirname "$CONF")"
	{
		printf '# written by %s\n' "$self"
		for v in $VARS; do
			eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\""
		done
	} > "$CONF"
}

# --- page state -------------------------------------------------------------
SNAP=$(mktemp)
trap 'rm -f "$SNAP"' EXIT INT TERM

snapshot() {
	: > "$SNAP"
	for v in "$@"; do
		eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >> "$SNAP"
	done
}
restore() { . "$SNAP"; }

reset_vars() {
	_keep=$(mktemp); _fresh=$(mktemp); _wanted=$*
	for v in $VARS; do eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >> "$_keep"; done
	set_defaults
	for v in $VARS; do eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >> "$_fresh"; done
	. "$_keep"
	for v in $_wanted; do eval "$(grep "^$v=" "$_fresh")"; done
	rm -f "$_keep" "$_fresh"
}

# --- output -----------------------------------------------------------------
DIM=$(printf '\033[2m'); OFF=$(printf '\033[0m')

say()   { printf '%s\n' "$1"; }
die()   { printf '%s: %s\n' "$self" "$1" >&2; exit 1; }
rule()  { printf '  %s\n' '----------------------------------------------------------------'; }
head2() { printf '\n  %s\n' "$1"; rule; }
intro() { printf '  %s\n' "$1"; [ -n "${2:-}" ] && printf '  %s\n' "$2"; printf '\n'; }

row() {
	if [ -n "${4:-}" ]; then printf '    %-2s  %-16s %-24s %s\n' "$1" "$2" "$3" "$4"
	else printf '    %-2s  %-16s %s\n' "$1" "$2" "$3"; fi
}
act() { printf '    %-2s  %s\n' "$1" "$2"; }
pause() { printf '\n  enter to continue '; read -r _d || true; }

edit() {
	_var=$1; _label=$2; _hint=$3; shift 3
	eval "_cur=\${$_var}"
	[ -n "$_hint" ] && say "  $_hint"
	[ $# -gt 0 ] && say "  one of: $*"
	printf '  %s [%s]: ' "$_label" "$_cur"
	read -r _new || _new=
	[ -z "$_new" ] && return 0
	if [ $# -gt 0 ]; then
		for _c in "$@"; do [ "$_new" = "$_c" ] && { eval "$_var=\$_new"; return 0; }; done
		say "  not one of: $*"; return 0
	fi
	eval "$_var=\$_new"
}

confirm() {
	printf '  %s [y/N] ' "$1"
	read -r _c || _c=n
	case $_c in y|Y|yes) return 0 ;; *) return 1 ;; esac
}
# _key, not KEY: KEY is the certificate key setting and a menu read would clobber it
menu() { printf '\n  > '; read -r _key || _key=q; }

# --- privilege --------------------------------------------------------------
can_write() { if [ -e "$1" ]; then [ -w "$1" ]; else [ -w "$(dirname "$1")" ]; fi; }

priv() {
	if [ "$(id -u)" -eq 0 ]; then "$@"
	elif command -v sudo >/dev/null 2>&1; then printf '  root: %s\n' "$*"; sudo "$@"
	else die "need root for: $*"; fi
}
priv_sh() {
	if [ "$(id -u)" -eq 0 ]; then sh -c "$1"
	elif command -v sudo >/dev/null 2>&1; then printf '  root: %s\n' "$1"; sudo sh -c "$1"
	else die "need root for: $1"; fi
}
priv_write() {
	if can_write "$1" || [ "$(id -u)" -eq 0 ]; then cat > "$1"
	elif command -v sudo >/dev/null 2>&1; then printf '  root: write %s\n' "$1"; sudo tee "$1" >/dev/null
	else die "need root to write $1"; fi
}
priv_cp()    { if can_write "$2"; then cp "$1" "$2"; else priv cp "$1" "$2"; fi; }
priv_cat()   { if [ -r "$1" ]; then cat "$1"; else priv cat "$1"; fi; }
priv_mkdir() { if can_write "$1"; then mkdir -p "$1"; else priv mkdir -p "$1"; fi; }
priv_test_dir() {
	if [ -d "$1" ]; then return 0
	elif [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then sudo -n test -d "$1" 2>/dev/null
	else return 1; fi
}

# make install replaces files under the prefix, so a writable directory holding
# root-owned content from an earlier install is still not enough
install_needs_root() {
	[ -e "$NGINX_PREFIX" ] || { can_write "$(dirname "$NGINX_PREFIX")" && return 1 || return 0; }
	can_write "$NGINX_PREFIX" || return 0
	find "$NGINX_PREFIX" ! -user "$(id -un)" -print 2>/dev/null | head -n1 | grep -q . && return 0
	return 1
}

pkg_cmd() {
	if   command -v pacman  >/dev/null 2>&1; then printf 'pacman -S --needed --noconfirm %s' "$1"
	elif command -v apt-get >/dev/null 2>&1; then printf 'apt-get install -y %s' "$1"
	elif command -v dnf     >/dev/null 2>&1; then printf 'dnf install -y %s' "$1"
	elif command -v zypper  >/dev/null 2>&1; then printf 'zypper --non-interactive install %s' "$1"
	elif command -v apk     >/dev/null 2>&1; then printf 'apk add %s' "$1"
	else return 1
	fi
}

ensure_tool() {
	_et_tool=$1; _et_pkg=${2:-$1}
	command -v "$_et_tool" >/dev/null 2>&1 && return 0
	if ! _et_cmd=$(pkg_cmd "$_et_pkg"); then
		say "  needs $_et_tool, and no package manager this script knows was found"
		say "  install $_et_tool however this system does it, then run the plan again"
		return 1
	fi
	confirm "needs $_et_tool, install it?" || return 1
	priv_sh "$_et_cmd" || { say "  install failed"; return 1; }
	command -v "$_et_tool" >/dev/null 2>&1 || { say "  $_et_tool not on PATH"; return 1; }
	return 0
}
tool_note() { command -v "$1" >/dev/null 2>&1 || printf 'needs %s' "$1"; }

have_systemd() {
	case $USE_SYSTEMD in
		yes) return 0 ;; no) return 1 ;;
		*) command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] ;;
	esac
}
user_exists() { id -u "$1" >/dev/null 2>&1; }

# --- nginx ------------------------------------------------------------------
nginx_bin() {
	case $NGINX_MODE in
		prefix) printf '%s/sbin/nginx' "$NGINX_PREFIX" ;;
		system) command -v nginx 2>/dev/null || true ;;
		*) if [ -x "$NGINX_PREFIX/sbin/nginx" ]; then printf '%s/sbin/nginx' "$NGINX_PREFIX"
		   else command -v nginx 2>/dev/null || true; fi ;;
	esac
}
nginx_has_stream() {
	_nhs_b=$(nginx_bin); [ -n "$_nhs_b" ] && [ -x "$_nhs_b" ] || return 1
	_nhs_v=$("$_nhs_b" -V 2>&1) || return 1
	printf '%s' "$_nhs_v" | grep -q -- '--with-stream' &&
	printf '%s' "$_nhs_v" | grep -q -- '--with-stream_ssl_module'
}
nginx_conf_prefix() {
	_ncp_b=$(nginx_bin); [ -n "$_ncp_b" ] && [ -x "$_ncp_b" ] || return 1
	"$_ncp_b" -V 2>&1 | tr ' ' '\n' | sed -n 's/^--conf-path=//p' | sed 's:/[^/]*$::'
}

hub_state_dir() {
	if [ -n "$STATE_DIR" ]; then printf '%s' "$STATE_DIR"
	elif command -v pxctl >/dev/null 2>&1 && [ -n "$HUB" ]; then pxctl get "$HUB" statedir 2>/dev/null
	fi
}
hub_tree_ok()  { _d=$(hub_state_dir 2>/dev/null || true); [ -n "$HUB" ] && [ -n "$_d" ] && priv_test_dir "$_d"; }
hub_running()  { have_systemd && [ -n "$HUB" ] && systemctl is-active --quiet "ptokax@$HUB" 2>/dev/null; }
console_up()   { [ -n "$HUB" ] && [ -S "/run/ptokax/$HUB-console.sock" ]; }
cert_present() { [ -s "$CERT" ] && [ -s "$KEY" ]; }

# ============================================================================
# steps. state prints one of: done | ready | <reason it cannot run>
# ============================================================================
STEPS='nginx cert hub conf user unit socket start'

step_label() {
	case $1 in
		nginx)  echo "build nginx with stream" ;;
		cert)   echo "obtain the certificate" ;;
		hub)    echo "apply the hub settings" ;;
		conf)   echo "write the nginx config" ;;
		user)   echo "create the nginx account" ;;
		unit)   echo "install the nginx unit" ;;
		socket) echo "install the proxy socket" ;;
		start)  echo "start nginx" ;;
	esac
}

step_state() {
	case $1 in
	nginx)
		nginx_has_stream && { echo done; return; }
		[ -n "$(nginx_bin)" ] && [ "$NGINX_MODE" = system ] && { echo "packaged nginx has no stream module, set mode to prefix on page 1"; return; }
		echo ready ;;
	cert)
		cert_present && { echo done; return; }
		[ "$CERT_METHOD" = existing ] && { echo "method is existing but $CERT is missing"; return; }
		echo ready ;;
	hub)
		[ -n "$HUB" ] || { echo "no hub named on page 3"; return; }
		command -v pxctl >/dev/null 2>&1 || [ -n "$STATE_DIR" ] || { echo "no pxctl, set a state dir on page 3"; return; }
		hub_tree_ok || { echo "no state tree for $HUB"; return; }
		_d=$(hub_state_dir)
		grep -q '^TLSEnabled[[:space:]]*=[[:space:]]*1' "$_d/cfg/Settings.pxt" 2>/dev/null && { echo done; return; }
		echo ready ;;
	conf)
		nginx_has_stream || { echo "after: build nginx with stream"; return; }
		cert_present     || { echo "after: obtain the certificate"; return; }
		[ -n "$STREAM_DIR" ] || nginx_conf_prefix >/dev/null 2>&1 || { echo "cannot find the config directory, set it on page 4"; return; }
		[ -n "$STREAM_DIR" ] && [ -f "$STREAM_DIR/ptokax-nmdcs.conf" ] && { echo done; return; }
		echo ready ;;
	user)
		have_systemd || { echo "systemd is off on page 5"; return; }
		user_exists "$NGINX_USER" && { echo done; return; }
		echo ready ;;
	unit)
		have_systemd || { echo "systemd is off on page 5"; return; }
		[ -f /etc/systemd/system/nginx-ptokax.service ] && { echo done; return; }
		user_exists "$NGINX_USER" || { echo "after: create the nginx account"; return; }
		hub_tree_ok || { echo "needs the hub state dir for ReadOnlyPaths"; return; }
		echo ready ;;
	socket)
		have_systemd || { echo "systemd is off on page 5"; return; }
		[ -n "$HUB" ] || { echo "no hub named on page 3"; return; }
		[ -f "/etc/systemd/system/ptokax@$HUB.socket.d/20-proxy.conf" ] && { echo done; return; }
		[ -f /etc/systemd/system/ptokax@.socket ] || [ -f /usr/lib/systemd/system/ptokax@.socket ] ||
			{ echo "ptokax@.socket not installed, PtokaX binds the address itself"; return; }
		echo ready ;;
	start)
		[ -n "$STREAM_DIR" ] && [ -f "$STREAM_DIR/ptokax-nmdcs.conf" ] || { echo "after: write the nginx config"; return; }
		echo ready ;;
	esac
}

step_run() {
	case $1 in
		nginx)  run_build ;;   cert)   run_cert ;;
		hub)    run_hub ;;     conf)   run_conf ;;
		user)   run_user ;;    unit)   run_unit ;;
		socket) run_socket ;;  start)  run_start ;;
	esac
}

# --- plan -------------------------------------------------------------------
page_plan() {
	while :; do
		head2 "plan"
		intro "Nothing above this point changed the host. This does."
		_n=0; _ready=0
		for st in $STEPS; do
			_n=$((_n + 1))
			_s=$(step_state "$st")
			case $_s in
				done)  printf '    %-2s  %-28s %s\n' "$_n" "$(step_label "$st")" "done" ;;
				ready) printf '    %-2s  %-28s %s\n' "$_n" "$(step_label "$st")" "will run"; _ready=$((_ready + 1)) ;;
				*)     printf '%s    %-2s  %-28s %s%s\n' "$DIM" "$_n" "$(step_label "$st")" "$_s" "$OFF" ;;
			esac
		done
		say ""
		if [ "$_ready" -eq 0 ]; then say "  nothing to run"
		else act x "run the $_ready step(s) marked will run"; fi
		act q "back"
		menu
		case $_key in
			x) [ "$_ready" -gt 0 ] && run_plan; pause ;;
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
	[ -d "$BUILD_DIR" ] || { say "  clone failed"; return 1; }

	# the git tree ships auto/configure only. Paths match RuntimeDirectory,
	# StateDirectory and LogsDirectory in nginx.service.in.
	_cfg="cd '$BUILD_DIR' && auto/configure --prefix='$NGINX_PREFIX' \
--with-stream --with-stream_ssl_module --with-http_ssl_module \
--user='$NGINX_USER' --group='$NGINX_USER' \
--pid-path=/run/nginx/nginx.pid \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--http-client-body-temp-path=/var/lib/nginx/client_body \
--http-proxy-temp-path=/var/lib/nginx/proxy"

	if can_write "$BUILD_DIR"; then sh -c "$_cfg"; else priv_sh "$_cfg"; fi || { say "  configure failed"; return 1; }

	_mk="cd '$BUILD_DIR' && make -j\$(nproc 2>/dev/null || echo 2)"
	if can_write "$BUILD_DIR"; then sh -c "$_mk"; else priv_sh "$_mk"; fi || { say "  build failed"; return 1; }

	_in="cd '$BUILD_DIR' && make install"
	if install_needs_root; then
		priv_sh "$_in" || { say "  install failed"; return 1; }
	elif ! sh -c "$_in"; then
		say "  install failed, prefix holds files owned by someone else"
		confirm "retry as root?" || return 1
		priv_sh "$_in" || { say "  install failed"; return 1; }
	fi

	[ -x "$NGINX_PREFIX/sbin/nginx" ] || { say "  no binary at $NGINX_PREFIX/sbin/nginx"; return 1; }
	NGINX_MODE=prefix
	say "  installed $(nginx_bin)"
}

run_cert() {
	case $CERT_METHOD in
	letsencrypt)
		if ! ensure_tool certbot; then
			confirm "use a self-signed certificate instead?" || return 1
			CERT_METHOD=selfsigned; run_cert; return $?
		fi
		say "  $HUB_ADDR must resolve here, port 80 must be free"
		confirm "run certbot?" || return 1
		priv certbot certonly --standalone -d "$HUB_ADDR" || return 1
		CERT=/etc/letsencrypt/live/$HUB_ADDR/fullchain.pem
		KEY=/etc/letsencrypt/live/$HUB_ADDR/privkey.pem
		say "  renewal keeps the key, so the keyprint stays the same"
		;;
	selfsigned)
		ensure_tool openssl || return 1
		priv_mkdir "$(dirname "$CERT")"; priv_mkdir "$(dirname "$KEY")"
		if can_write "$CERT" && can_write "$KEY"; then
			openssl req -new -newkey rsa:4096 -x509 -sha256 -days 1800 -nodes \
				-subj "/CN=$HUB_ADDR" -addext "subjectAltName=DNS:$HUB_ADDR" \
				-out "$CERT" -keyout "$KEY" 2>/dev/null && chmod 600 "$KEY"
		else
			priv openssl req -new -newkey rsa:4096 -x509 -sha256 -days 1800 -nodes \
				-subj "/CN=$HUB_ADDR" -addext "subjectAltName=DNS:$HUB_ADDR" \
				-out "$CERT" -keyout "$KEY" 2>/dev/null && priv chmod 600 "$KEY"
		fi
		cert_present || { say "  generation failed"; return 1; }
		show_keyprint
		;;
	existing) say "  using $CERT and $KEY unchanged" ;;
	esac
}

keyprint_of() {
	[ -s "$CERT" ] || { printf '<none>'; return; }
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

# Settings are never hand edited while the hub runs: it rewrites cfg/ from
# memory on shutdown. Stopped, the file is written. Running, SetMan goes over
# the console socket.
run_hub() {
	if hub_running; then run_hub_console; else run_hub_file; fi
}

run_hub_file() {
	_d=$(hub_state_dir); _f=$_d/cfg/Settings.pxt
	[ -f "$_f" ] || { say "  no $_f"; return 1; }
	hub_setting_lines | sed 's/^/    /'
	confirm "write into $_f?" || return 1
	priv_cp "$_f" "$_f.bak-nmdcs"
	_tmpf=$(mktemp); priv_cat "$_f" > "$_tmpf"
	for k in TLSEnabled TLSProxyAddress PingerAddresses; do
		sed -i "/^#\{0,1\}$k[[:space:]]*=/d" "$_tmpf"
	done
	hub_setting_lines >> "$_tmpf"
	priv_write "$_f" < "$_tmpf"; rm -f "$_tmpf"
	say "  written, old file kept as Settings.pxt.bak-nmdcs"
}

run_hub_console() {
	if ! console_up; then
		say "  hub running, console socket down"
		say "  enabling it needs one stop and start"
		confirm "stop ptokax@$HUB, enable the socket, start it?" || {
			say "  unchanged, or stop the hub and run the plan again"; return 1; }
		priv systemctl stop "ptokax@$HUB" || return 1
		if ! priv systemctl enable --now "ptokax-console@$HUB.socket"; then
			priv systemctl start "ptokax@$HUB"; return 1
		fi
		priv systemctl start "ptokax@$HUB" || return 1
		_i=0; while [ $_i -lt 10 ] && ! console_up; do sleep 1; _i=$((_i + 1)); done
		console_up || { say "  console socket still down"; return 1; }
	fi
	ensure_tool socat || return 1
	hub_setting_chunk | sed 's/^/    /'
	confirm "send this over the console?" || return 1
	_tmpc=$(mktemp); hub_setting_chunk > "$_tmpc"
	priv_sh "socat -t5 - 'UNIX-CONNECT:/run/ptokax/$HUB-console.sock' < '$_tmpc'" || { rm -f "$_tmpc"; return 1; }
	rm -f "$_tmpc"
	say "  saved. journalctl PTOKAX_SUBSYSTEM=console for output"
}

run_conf() {
	[ -n "$STREAM_DIR" ] || {
		_cp=$(nginx_conf_prefix) || { say "  cannot read --conf-path"; return 1; }
		STREAM_DIR=$_cp/stream.d; CONFD_DIR=$_cp/conf.d
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
	[ -x "$_gen" ] || { say "  unitgen.sh not found at $_gen"; return 1; }
	_d=$(hub_state_dir)
	_v=$(systemctl --version 2>/dev/null | sed -n '1s/^systemd \([0-9]*\).*/\1/p'); [ -n "$_v" ] || _v=0
	"$_gen" --systemd-version="$_v" \
		--define="NGINXBIN=$(nginx_bin)" --define="NGINXUSER=$NGINX_USER" \
		--define="STATEDIR=$_d" --define="docdir=/usr/share/doc/ptokax" \
		< "$here/nginx.service.in" | priv_write /etc/systemd/system/nginx-ptokax.service || return 1
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
	confirm "restart ptokax@$HUB.socket?" && priv systemctl restart "ptokax@$HUB.socket"
	return 0
}

run_start() {
	_b=$(nginx_bin); [ -n "$_b" ] || { say "  no nginx binary"; return 1; }
	priv "$_b" -t || { say "  config test failed"; return 1; }
	if have_systemd && [ -f /etc/systemd/system/nginx-ptokax.service ]; then
		priv systemctl restart nginx-ptokax &&
		priv systemctl --no-pager --lines=3 status nginx-ptokax
	elif priv "$_b" -s reload 2>/dev/null; then say "  reloaded"
	else priv "$_b" && say "  started"; fi
}

# ============================================================================
# pages. these only record choices.
# ============================================================================
page_nginx() {
	_own='NGINX_MODE NGINX_PREFIX BUILD_DIR'
	snapshot $_own
	while :; do
		head2 "1  nginx"
		_pn_b=$(nginx_bin)
		row a "mode"       "$NGINX_MODE"   "auto, system or prefix"
		row b "prefix"     "$NGINX_PREFIX" "a source build installs here"
		row c "source dir" "$BUILD_DIR"    "the git clone is kept here"
		say ""
		row "" "binary" "${_pn_b:-none found}"
		row "" "stream" "$(nginx_has_stream && echo yes || echo no)" "required, off by default"
		say ""
		act r "reset this page"; act s "return, keeping changes"; act q "return, discarding them"
		menu
		case $_key in
			a) edit NGINX_MODE "mode" "auto prefers the prefix build, then PATH" auto system prefix ;;
			b) edit NGINX_PREFIX "prefix" "" ;;
			c) edit BUILD_DIR "source dir" "" ;;
			r) reset_vars $_own ;;
			s) return ;;
			q) restore; return ;;
			*) say "  no such choice" ;;
		esac
	done
}

page_cert() {
	_own='CERT_METHOD HUB_ADDR CERT KEY'
	snapshot $_own
	while :; do
		head2 "2  certificate"
		row a "method" "$CERT_METHOD" "$([ "$CERT_METHOD" = letsencrypt ] && tool_note certbot)"
		row b "domain" "$HUB_ADDR"    "name clients connect to"
		row c "cert"   "$CERT"        "$(cert_present && echo present || echo missing)"
		row d "key"    "$KEY"
		say ""
		act p "show the keyprint"; act r "reset this page"
		act s "return, keeping changes"; act q "return, discarding them"
		menu
		case $_key in
			a) edit CERT_METHOD "method" "selfsigned needs no network, DC++ users must opt in" letsencrypt selfsigned existing ;;
			b) edit HUB_ADDR "domain" "" ;;
			c) edit CERT "cert" "" ;;
			d) edit KEY "key" "" ;;
			p) say ""; show_keyprint; pause ;;
			r) reset_vars $_own ;;
			s) return ;;
			q) restore; return ;;
			*) say "  no such choice" ;;
		esac
	done
}

page_hub() {
	_own='HUB STATE_DIR PROXY_ADDR TCP_PORT TLS_PORT'
	snapshot $_own
	while :; do
		head2 "3  hub"
		_d=$(hub_state_dir 2>/dev/null || true)
		row a "hub name"        "${HUB:-<none>}"        "systemd instance ptokax@<name>"
		row b "state dir"       "${STATE_DIR:-<pxctl>}" "${_d:-unknown}"
		row c "TLSProxyAddress" "$PROXY_ADDR"           "loopback listener the terminator feeds"
		row d "plaintext port"  "$TCP_PORT"             "first entry in TCPPorts"
		row e "NMDCS port"      "$TLS_PORT"             "external port nginx listens on"
		say ""
		row "" "hub"     "$(hub_running && echo running || echo stopped)"
		row "" "console" "$(console_up && echo up || echo down)"
		say ""
		act l "list hubs known to systemd"; act r "reset this page"
		act s "return, keeping changes"; act q "return, discarding them"
		menu
		case $_key in
			a) edit HUB "hub name" "" ;;
			b) edit STATE_DIR "state dir" "empty means ask pxctl" ;;
			c) edit PROXY_ADDR "TLSProxyAddress" "" ;;
			d) edit TCP_PORT "plaintext port" "" ;;
			e) edit TLS_PORT "NMDCS port" "above 1024 needs no capability" ;;
			l) say ""; command -v pxctl >/dev/null 2>&1 && pxctl list || say "  no pxctl"; pause ;;
			r) reset_vars $_own ;;
			s) return ;;
			q) restore; return ;;
			*) say "  no such choice" ;;
		esac
	done
}

page_conf() {
	_own='STREAM_DIR CONFD_DIR'
	snapshot $_own
	while :; do
		head2 "4  nginx config"
		row a "stream dir" "${STREAM_DIR:-<from nginx -V>}" "stream {} is a sibling of http {}"
		row b "conf.d dir" "${CONFD_DIR:-<from nginx -V>}"  "pinger snippet, inside http {}"
		say ""
		act r "reset this page"; act s "return, keeping changes"; act q "return, discarding them"
		menu
		case $_key in
			a) edit STREAM_DIR "stream dir" "included from a stream {} block, not conf.d" ;;
			b) edit CONFD_DIR "conf.d dir" "" ;;
			r) reset_vars $_own ;;
			s) return ;;
			q) restore; return ;;
			*) say "  no such choice" ;;
		esac
	done
}

page_systemd() {
	_own='USE_SYSTEMD NGINX_USER'
	snapshot $_own
	while :; do
		head2 "5  systemd"
		row a "use systemd"   "$USE_SYSTEMD" "in effect: $(have_systemd && echo yes || echo no)"
		row b "nginx runs as" "$NGINX_USER"  "$(user_exists "$NGINX_USER" && echo exists || echo 'not created')"
		say ""
		act r "reset this page"; act s "return, keeping changes"; act q "return, discarding them"
		menu
		case $_key in
			a) edit USE_SYSTEMD "use systemd" "" auto yes no ;;
			b) edit NGINX_USER "nginx runs as" "User= and Group= on the unit, so nginx is never root" ;;
			r) reset_vars $_own ;;
			s) return ;;
			q) restore; return ;;
			*) say "  no such choice" ;;
		esac
	done
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
		{ curl -sS --max-time 5 "http://$HUB_ADDR/api/v0/hubinfo.json" || say "    no answer"; say ""; }
	pause
}

# --- main -------------------------------------------------------------------
plan_summary() {
	_r=0; _b=0
	for st in $STEPS; do
		case $(step_state "$st") in
			done) ;;
			ready) _r=$((_r + 1)) ;;
			*) _b=$((_b + 1)) ;;
		esac
	done
	if [ $_r -eq 0 ] && [ $_b -eq 0 ]; then printf 'everything done'
	elif [ $_b -eq 0 ]; then printf '%d to run' "$_r"
	else printf '%d to run, %d blocked' "$_r" "$_b"; fi
}

main_menu() {
	while :; do
		head2 "PtokaX NMDCS setup"
		intro "Pages record choices. Nothing changes until you run the plan."
		row 1 "nginx"       "$NGINX_MODE, $NGINX_PREFIX"
		row 2 "certificate" "$CERT_METHOD, $HUB_ADDR"
		row 3 "hub"         "${HUB:-<none>}, $PROXY_ADDR"
		row 4 "nginx config" "${STREAM_DIR:-<from nginx -V>}"
		row 5 "systemd"     "$(have_systemd && echo yes || echo no), user $NGINX_USER"
		say ""
		act p "plan and run          $(plan_summary)"
		act v "verify a running setup"
		act w "write these choices to $CONF"
		act R "reset everything"
		act q "quit"
		menu
		case $_key in
			1) page_nginx ;; 2) page_cert ;; 3) page_hub ;;
			4) page_conf ;;  5) page_systemd ;;
			p) page_plan ;;  v) page_verify ;;
			w) save_conf; say "  written to $CONF" ;;
			R) confirm "reset every setting?" && set_defaults ;;
			q|Q) exit 0 ;;
		esac
	done
}

case ${1:-} in
	-h|--help)
		printf 'Usage: %s\n\nInteractive. Choices kept in %s.\nOverride with PX_NGINX_SETUP_CONF.\n' "$self" "$CONF"
		exit 0 ;;
esac

main_menu
