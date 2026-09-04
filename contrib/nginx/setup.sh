#!/bin/sh
# Interactive setup for NMDCS in front of PtokaX.
#
# Each item stands on its own. Only "nginx config" needs a working nginx and a
# certificate first. Choices are kept between runs.
#
# Root is used for exactly three things, each named before it runs: installing
# nginx into its prefix, writing files under /etc, and talking to systemd.
# -e is deliberately absent: a failed action reports and returns to the menu
# rather than dropping the admin back to a shell mid-setup
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
	CERT_METHOD=letsencrypt
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
# A page snapshots the variables it owns on entry. "discard" puts them back, so
# backing out of a page really does undo what was typed in it.
SNAP=$(mktemp)
trap 'rm -f "$SNAP"' EXIT INT TERM

snapshot() {
	: > "$SNAP"
	for v in "$@"; do
		eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >> "$SNAP"
	done
}

restore() { . "$SNAP"; }

# reset only the named variables to their documented defaults
reset_vars() {
	_keep=$(mktemp)
	for v in $VARS; do
		eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >> "$_keep"
	done
	_wanted=$*
	set_defaults
	_fresh=$(mktemp)
	for v in $VARS; do
		eval "printf '%s=%s\n' \"\$v\" \"\$(quote \"\${$v}\")\"" >> "$_fresh"
	done
	. "$_keep"
	for v in $_wanted; do
		eval "$(grep "^$v=" "$_fresh")"
	done
	rm -f "$_keep" "$_fresh"
}

# --- output -----------------------------------------------------------------
say()  { printf '%s\n' "$1"; }
die()  { printf '%s: %s\n' "$self" "$1" >&2; exit 1; }
rule() { printf '  %s\n' '----------------------------------------------------------------'; }
head2() { printf '\n  %s\n' "$1"; rule; }
# one or two lines saying what the page achieves, before any field
intro() { printf '  %s\n' "$1"; [ -n "${2:-}" ] && printf '  %s\n' "$2"; printf '\n'; }

# the command that would install a missing tool on this system
pkg_hint() {
	if   command -v pacman >/dev/null 2>&1; then printf 'sudo pacman -S %s' "$1"
	elif command -v apt    >/dev/null 2>&1; then printf 'sudo apt install %s' "$1"
	elif command -v dnf    >/dev/null 2>&1; then printf 'sudo dnf install %s' "$1"
	elif command -v zypper >/dev/null 2>&1; then printf 'sudo zypper install %s' "$1"
	elif command -v apk    >/dev/null 2>&1; then printf 'sudo apk add %s' "$1"
	else printf 'install %s with your package manager' "$1"
	fi
}

# key, label, value, note
row() {
	if [ -n "${4:-}" ]; then
		printf '    %-2s  %-16s %-24s %s\n' "$1" "$2" "$3" "$4"
	else
		printf '    %-2s  %-16s %s\n' "$1" "$2" "$3"
	fi
}
act() { printf '    %-2s  %s\n' "$1" "$2"; }

pause() { printf '\n  enter to continue '; read -r _d || true; }

# edit <var> <label> <help> [choice ...]
edit() {
	_var=$1; _label=$2; _help=$3; shift 3
	eval "_cur=\${$_var}"
	say ""
	say "  $_help"
	[ $# -gt 0 ] && say "  one of: $*"
	printf '  %s [%s]: ' "$_label" "$_cur"
	read -r _new || _new=
	[ -z "$_new" ] && return 0
	if [ $# -gt 0 ]; then
		for _c in "$@"; do
			[ "$_new" = "$_c" ] && { eval "$_var=\$_new"; return 0; }
		done
		say "  not one of: $*"
		return 0
	fi
	eval "$_var=\$_new"
}

confirm() {
	printf '  %s [y/N] ' "$1"
	read -r _c || _c=n
	case $_c in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

menu() { printf '\n  > '; read -r REPLY_KEY || REPLY_KEY=b; }

# --- privilege --------------------------------------------------------------
can_write() {
	if [ -e "$1" ]; then [ -w "$1" ]; else [ -w "$(dirname "$1")" ]; fi
}

priv() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif command -v sudo >/dev/null 2>&1; then
		printf '  root needed: %s\n' "$*"
		sudo "$@"
	else
		die "need root for: $*"
	fi
}

priv_sh() {
	if [ "$(id -u)" -eq 0 ]; then
		sh -c "$1"
	elif command -v sudo >/dev/null 2>&1; then
		printf '  root needed: %s\n' "$1"
		sudo sh -c "$1"
	else
		die "need root for: $1"
	fi
}

priv_write() {
	if can_write "$1" || [ "$(id -u)" -eq 0 ]; then
		cat > "$1"
	elif command -v sudo >/dev/null 2>&1; then
		printf '  root needed: write %s\n' "$1"
		sudo tee "$1" >/dev/null
	else
		die "need root to write $1"
	fi
}

# make install replaces files already under the prefix, so a writable directory
# holding root-owned content from an earlier install is still not enough
install_needs_root() {
	if [ ! -e "$NGINX_PREFIX" ]; then
		can_write "$(dirname "$NGINX_PREFIX")" && return 1 || return 0
	fi
	can_write "$NGINX_PREFIX" || return 0
	if find "$NGINX_PREFIX" ! -user "$(id -un)" -print 2>/dev/null | head -n1 | grep -q .; then
		return 0
	fi
	return 1
}

priv_cp()    { if can_write "$2"; then cp "$1" "$2"; else priv cp "$1" "$2"; fi; }
priv_cat()   { if [ -r "$1" ]; then cat "$1"; else priv cat "$1"; fi; }
priv_mkdir() { if can_write "$1"; then mkdir -p "$1"; else priv mkdir -p "$1"; fi; }

priv_test_dir() {
	if [ -d "$1" ]; then
		return 0
	elif [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
		sudo -n test -d "$1" 2>/dev/null
	else
		return 1
	fi
}

have_systemd() {
	case $USE_SYSTEMD in
		yes) return 0 ;;
		no)  return 1 ;;
		*)   command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] ;;
	esac
}

# --- nginx discovery --------------------------------------------------------
nginx_bin() {
	case $NGINX_MODE in
		prefix) printf '%s/sbin/nginx' "$NGINX_PREFIX" ;;
		system) command -v nginx 2>/dev/null || true ;;
		*)      if [ -x "$NGINX_PREFIX/sbin/nginx" ]; then printf '%s/sbin/nginx' "$NGINX_PREFIX"
		        else command -v nginx 2>/dev/null || true; fi ;;
	esac
}

nginx_has_stream() {
	b=$(nginx_bin); [ -n "$b" ] && [ -x "$b" ] || return 1
	v=$("$b" -V 2>&1) || return 1
	printf '%s' "$v" | grep -q -- '--with-stream' &&
	printf '%s' "$v" | grep -q -- '--with-stream_ssl_module'
}

nginx_conf_prefix() {
	b=$(nginx_bin); [ -n "$b" ] && [ -x "$b" ] || return 1
	"$b" -V 2>&1 | tr ' ' '\n' | sed -n 's/^--conf-path=//p' | sed 's:/[^/]*$::'
}

user_exists() { id -u "$1" >/dev/null 2>&1; }

# --- rungs ------------------------------------------------------------------
rung_units()    { command -v pxctl >/dev/null 2>&1; }
rung_instance() { _d=$(hub_state_dir 2>/dev/null || true); [ -n "$HUB" ] && [ -n "$_d" ] && priv_test_dir "$_d"; }
rung_running()  { have_systemd && [ -n "$HUB" ] && systemctl is-active --quiet "ptokax@$HUB" 2>/dev/null; }
rung_console()  { [ -n "$HUB" ] && [ -S "/run/ptokax/$HUB-console.sock" ]; }
rung_tooling()  { command -v pxconsole >/dev/null 2>&1 || command -v socat >/dev/null 2>&1; }

hub_state_dir() {
	if [ -n "$STATE_DIR" ]; then printf '%s' "$STATE_DIR"
	elif rung_units && [ -n "$HUB" ]; then pxctl get "$HUB" statedir 2>/dev/null
	fi
}

# --- statuses ---------------------------------------------------------------
st_nginx() {
	b=$(nginx_bin)
	if [ -z "$b" ] || [ ! -x "$b" ]; then echo "not found"
	elif nginx_has_stream; then echo "ready"
	else echo "no stream module"; fi
}
st_cert()    { if [ -s "$CERT" ] && [ -s "$KEY" ]; then echo "present"; else echo "not created"; fi; }
st_hub()     {
	[ -n "$HUB" ] || { echo "no hub chosen"; return; }
	rung_instance || { echo "$HUB, no state tree"; return; }
	d=$(hub_state_dir)
	if grep -q '^TLSEnabled[[:space:]]*=[[:space:]]*1' "$d/cfg/Settings.pxt" 2>/dev/null
	then echo "$HUB, enabled"; else echo "$HUB, not enabled"; fi
}
st_conf() {
	if [ -n "$STREAM_DIR" ] && [ -f "$STREAM_DIR/ptokax-nmdcs.conf" ]; then echo "written"; else echo "not written"; fi
}

# the only real ordering in the menu: the config names a binary and a certificate
conf_blocked_by() {
	_b=
	nginx_has_stream || _b="nginx"
	{ [ -s "$CERT" ] && [ -s "$KEY" ]; } || _b="${_b:+$_b and }a certificate"
	[ -n "$_b" ] && printf 'needs %s first' "$_b"
}
st_systemd() {
	have_systemd || { echo "not in use"; return; }
	s=
	[ -f /etc/systemd/system/nginx-ptokax.service ] && s="nginx unit"
	[ -n "$HUB" ] && [ -f "/etc/systemd/system/ptokax@$HUB.socket.d/20-proxy.conf" ] && s="${s:+$s, }proxy socket"
	echo "${s:-nothing installed}"
}

# --- page 1, nginx ----------------------------------------------------------
page_nginx() {
	_own='NGINX_MODE NGINX_PREFIX BUILD_DIR'
	snapshot $_own
	while :; do
		head2 "1  nginx"
		b=$(nginx_bin)
		if [ -z "$b" ]; then
			intro "No nginx found. Build one below, or point mode at a packaged" \
			      "one that already has the stream module."
		elif nginx_has_stream; then
			intro "This nginx has the stream module, so nothing more is needed here."
		else
			intro "This nginx has no stream module and cannot terminate NMDCS." \
			      "Build one below. It installs beside the packaged nginx."
		fi
		row a "mode"        "$NGINX_MODE"    "auto, system or prefix"
		row b "prefix"      "$NGINX_PREFIX"  "where a source build installs"
		row c "source dir"  "$BUILD_DIR"     "clone lands here"
		say ""
		row "" "binary"     "${b:-none found}"
		row "" "stream"     "$(nginx_has_stream && echo yes || echo no)" "required, off by default"
		say ""
		act i "build and install from source"
		act r "reset this page to defaults"
		act s "save and return"
		act q "discard changes and return"
		menu
		case $REPLY_KEY in
			a) edit NGINX_MODE "mode" \
			     "auto prefers a build under the prefix, then whatever is on PATH" \
			     auto system prefix ;;
			b) edit NGINX_PREFIX "prefix" "a source build installs here" ;;
			c) edit BUILD_DIR "source dir" "the git clone is kept here, so a rebuild is a pull" ;;
			i) do_build_nginx; pause ;;
			r) reset_vars $_own; say "  page reset" ;;
			s) save_conf; return ;;
			q) restore; return ;;
		esac
	done
}

do_build_nginx() {
	command -v git >/dev/null 2>&1 || { say "  git not found"; return 0; }

	say ""
	say "  clone     $BUILD_DIR"
	say "  configure --prefix=$NGINX_PREFIX --with-stream --with-stream_ssl_module"
	say "  install   $NGINX_PREFIX"
	say ""
	if can_write "$BUILD_DIR" && can_write "$NGINX_PREFIX"; then
		say "  both paths are writable by you, so no root is needed"
	else
		say "  root is needed to write those paths"
	fi
	confirm "go ahead?" || { say "  nothing done"; return 0; }

	if can_write "$(dirname "$BUILD_DIR")"; then mkdir -p "$(dirname "$BUILD_DIR")"
	else priv mkdir -p "$(dirname "$BUILD_DIR")"; fi

	if [ -d "$BUILD_DIR/.git" ]; then
		say "  updating clone"
		if can_write "$BUILD_DIR"; then git -C "$BUILD_DIR" pull --ff-only
		else priv git -C "$BUILD_DIR" pull --ff-only; fi
	else
		say "  cloning"
		if can_write "$(dirname "$BUILD_DIR")"; then git clone --depth 1 https://github.com/nginx/nginx.git "$BUILD_DIR"
		else priv git clone --depth 1 https://github.com/nginx/nginx.git "$BUILD_DIR"; fi
	fi

	# the git tree has auto/configure only; the top level one is generated for
	# release tarballs. Paths match RuntimeDirectory, StateDirectory and
	# LogsDirectory in nginx.service.in so an unprivileged nginx can write them.
	_cfg="cd '$BUILD_DIR' && auto/configure --prefix='$NGINX_PREFIX' \
--with-stream --with-stream_ssl_module --with-http_ssl_module \
--user='$NGINX_USER' --group='$NGINX_USER' \
--pid-path=/run/nginx/nginx.pid \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--http-client-body-temp-path=/var/lib/nginx/client_body \
--http-proxy-temp-path=/var/lib/nginx/proxy"

	say "  configuring"
	if can_write "$BUILD_DIR"; then sh -c "$_cfg"; else priv_sh "$_cfg"; fi
	[ $? -eq 0 ] || { say "  configure failed"; return 0; }

	say "  building"
	_mk="cd '$BUILD_DIR' && make -j\$(nproc 2>/dev/null || echo 2)"
	if can_write "$BUILD_DIR"; then sh -c "$_mk"; else priv_sh "$_mk"; fi
	[ $? -eq 0 ] || { say "  build failed"; return 0; }

	confirm "install to $NGINX_PREFIX?" || { say "  built, not installed"; return 0; }
	_in="cd '$BUILD_DIR' && make install"

	if install_needs_root; then
		priv_sh "$_in" || { say "  install failed"; return 0; }
	elif ! sh -c "$_in"; then
		say "  install failed without root, which usually means the prefix holds"
		say "  files from an earlier install owned by someone else"
		confirm "retry as root?" || { say "  not installed"; return 0; }
		priv_sh "$_in" || { say "  install failed"; return 0; }
	fi

	[ -x "$NGINX_PREFIX/sbin/nginx" ] || { say "  no binary at $NGINX_PREFIX/sbin/nginx"; return 0; }

	NGINX_MODE=prefix
	save_conf
	say "  installed: $(nginx_bin)"
}

# --- page 2, certificate ----------------------------------------------------
page_cert() {
	_own='CERT_METHOD HUB_ADDR CERT KEY'
	snapshot $_own
	while :; do
		head2 "2  certificate"
		if [ -s "$CERT" ] && [ -s "$KEY" ]; then
			intro "A certificate is in place. nginx will present this to clients."
		else
			intro "nginx needs a certificate to terminate TLS." \
			      "A CA-signed one just works. Self-signed makes DC++ users opt in."
		fi
		_cb=$(command -v certbot >/dev/null 2>&1 && echo "" || echo "certbot not installed")
		row a "method" "$CERT_METHOD" "$([ "$CERT_METHOD" = letsencrypt ] && printf '%s' "$_cb")"
		row b "domain" "$HUB_ADDR"    "name clients connect to"
		row c "cert"   "$CERT"        "$([ -s "$CERT" ] && echo present || echo missing)"
		row d "key"    "$KEY"         "$([ -s "$KEY" ] && echo present || echo missing)"
		say ""
		act i "obtain or generate now"
		act p "show the keyprint and the ?kp= address"
		act r "reset this page to defaults"
		act s "save and return"
		act q "discard changes and return"
		menu
		case $REPLY_KEY in
			a) edit CERT_METHOD "method" \
			     "letsencrypt runs certbot, selfsigned needs no network, existing uses the paths below unchanged" \
			     letsencrypt selfsigned existing ;;
			b) edit HUB_ADDR "domain" "goes on the certificate and in the client address" ;;
			c) edit CERT "cert" "nginx reads this as ssl_certificate" ;;
			d) edit KEY  "key"  "nginx reads this as ssl_certificate_key" ;;
			i) do_cert; pause ;;
			p) show_keyprint; pause ;;
			r) reset_vars $_own; say "  page reset" ;;
			s) save_conf; return ;;
			q) restore; return ;;
		esac
	done
}

do_cert() {
	case $CERT_METHOD in
		letsencrypt)
			if ! command -v certbot >/dev/null 2>&1; then
				say ""
				say "  Let's Encrypt needs certbot, which is not installed."
				say ""
				say "      $(pkg_hint certbot)"
				say ""
				say "  It also needs $HUB_ADDR to resolve to this host and port 80"
				say "  free while it runs."
				say ""
				confirm "switch to a self-signed certificate instead?" || return 0
				CERT_METHOD=selfsigned
				save_conf
				do_cert
				return 0
			fi
			say ""
			say "  certbot needs $HUB_ADDR to resolve to this host and port 80 free."
			confirm "run certbot for $HUB_ADDR?" || return 0
			priv certbot certonly --standalone -d "$HUB_ADDR" || return 0
			CERT=/etc/letsencrypt/live/$HUB_ADDR/fullchain.pem
			KEY=/etc/letsencrypt/live/$HUB_ADDR/privkey.pem
			save_conf
			say "  renewal keeps the key, so the keyprint does not change"
			;;
		selfsigned)
			command -v openssl >/dev/null 2>&1 || { say "  openssl not found"; return 0; }
			confirm "generate a self-signed certificate for $HUB_ADDR?" || return 0
			priv_mkdir "$(dirname "$CERT")"; priv_mkdir "$(dirname "$KEY")"
			if can_write "$CERT" && can_write "$KEY"; then
				openssl req -new -newkey rsa:4096 -x509 -sha256 -days 1800 -nodes \
					-subj "/CN=$HUB_ADDR" -addext "subjectAltName=DNS:$HUB_ADDR" \
					-out "$CERT" -keyout "$KEY" && chmod 600 "$KEY"
			else
				priv openssl req -new -newkey rsa:4096 -x509 -sha256 -days 1800 -nodes \
					-subj "/CN=$HUB_ADDR" -addext "subjectAltName=DNS:$HUB_ADDR" \
					-out "$CERT" -keyout "$KEY" && priv chmod 600 "$KEY"
			fi
			show_keyprint
			;;
		existing)
			say "  using $CERT and $KEY unchanged"
			;;
	esac
}

keyprint_of() {
	[ -s "$CERT" ] || { printf '<no certificate at %s>' "$CERT"; return; }
	h=$(openssl x509 -in "$CERT" -outform der 2>/dev/null | openssl dgst -sha256 -binary \
		| base32 2>/dev/null | tr -d '=\n') || h=
	[ -n "$h" ] && printf 'SHA256/%s' "$h" || printf '<base32 not available>'
}

show_keyprint() {
	say ""
	say "  keyprint  $(keyprint_of)"
	say ""
	say "  address that skips the trust prompt in ncdc and DC++:"
	say "    nmdcs://$HUB_ADDR:$TLS_PORT?kp=$(keyprint_of)"
}

# --- page 3, hub settings ---------------------------------------------------
# Settings are never hand edited while the hub runs: it rewrites cfg/ from memory
# on shutdown. Stopped, the file is written; running, SetMan goes over the console.
page_hub() {
	_own='HUB STATE_DIR PROXY_ADDR TCP_PORT TLS_PORT'
	snapshot $_own
	while :; do
		head2 "3  hub settings"
		intro "Turns on the hub's proxy listener and the pinger address list." \
		      "Set through pxctl and the console, never by hand while it runs."
		d=$(hub_state_dir 2>/dev/null || true)
		row a "hub name"        "${HUB:-<none>}"        "systemd instance ptokax@<name>"
		row b "state dir"       "${STATE_DIR:-<pxctl>}" "${d:-unknown}"
		row c "TLSProxyAddress" "$PROXY_ADDR"           "loopback listener the terminator feeds"
		row d "plaintext port"  "$TCP_PORT"             "first entry in TCPPorts"
		row e "NMDCS port"      "$TLS_PORT"             "external port nginx listens on"
		say ""
		row "" "hub"     "$(rung_running && echo running || echo stopped)" ""
		row "" "console" "$(rung_console && echo up || echo down)" "needed to set a running hub"
		say ""
		act l "list hubs known to systemd"
		act k "show what is enabled"
		act i "apply the settings"
		act m "print the settings without applying"
		act r "reset this page to defaults"
		act s "save and return"
		act q "discard changes and return"
		menu
		case $REPLY_KEY in
			a) edit HUB "hub name" "Instance name, the part after the @ in ptokax@<name>." ;;
			b) edit STATE_DIR "state dir" "Config directory. Left empty it comes from pxctl get <hub> statedir." ;;
			c) edit PROXY_ADDR "TLSProxyAddress" "Address and port PtokaX listens on for the terminator. Loopback keeps it unreachable from off the host." ;;
			d) edit TCP_PORT "plaintext port" "Port PtokaX serves dchub:// on directly, unchanged by any of this." ;;
			e) edit TLS_PORT "NMDCS port" "External port nginx terminates TLS on. Above 1024 means the unit needs no capability." ;;
			l) list_hubs; pause ;;
			k) report_rungs; pause ;;
			i) apply_hub_settings; pause ;;
			m) print_hub_settings; pause ;;
			r) reset_vars $_own; say "  page reset" ;;
			s) save_conf; return ;;
			q) restore; return ;;
		esac
	done
}

report_rungs() {
	say ""
	row "" "units installed" "$(rung_units    && echo yes || echo no)" "$(rung_units    || echo 'make install')"
	row "" "instance"        "$(rung_instance && echo yes || echo no)" "$(rung_instance || echo 'pxctl create <hub>')"
	row "" "hub running"     "$(rung_running  && echo yes || echo no)" ""
	row "" "console socket"  "$(rung_console  && echo yes || echo no)" "$(rung_console  || echo 'needs the hub stopped to enable')"
	row "" "socat/pxconsole" "$(rung_tooling  && echo yes || echo no)" ""
}

list_hubs() {
	say ""
	if rung_units; then pxctl list || say "  pxctl list failed"
	else
		say "  pxctl not found, so there is no hub registry to read."
		say "  See ADMIN-GUIDE, \"pxctl\"."
	fi
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

print_hub_settings() {
	d=$(hub_state_dir 2>/dev/null || true)
	say ""
	say "  with the hub stopped, in ${d:-<state dir>}/cfg/Settings.pxt:"
	say ""
	hub_setting_lines | sed 's/^/    /'
	say ""
	say "  against a running hub, over the console socket:"
	say ""
	hub_setting_chunk | sed 's/^/    /'
}

apply_hub_settings() {
	rung_units    || { say "  pxctl not found, see ADMIN-GUIDE \"pxctl\""; return 0; }
	rung_instance || { say "  no state tree for ${HUB:-<hub>}, pxctl create <hub> first"; return 0; }
	if rung_running; then apply_via_console; else apply_via_file; fi
}

apply_via_file() {
	d=$(hub_state_dir); f=$d/cfg/Settings.pxt
	[ -f "$f" ] || { say "  no $f"; return 0; }
	say ""
	say "  ptokax@$HUB is stopped, so the file is written directly."
	confirm "write $f?" || { say "  nothing changed"; return 0; }

	priv_cp "$f" "$f.bak-nmdcs"
	tmp=$(mktemp); priv_cat "$f" > "$tmp"
	for key in TLSEnabled TLSProxyAddress PingerAddresses; do
		sed -i "/^#\{0,1\}$key[[:space:]]*=/d" "$tmp"
	done
	hub_setting_lines >> "$tmp"
	priv_write "$f" < "$tmp"
	rm -f "$tmp"
	say "  written, previous file kept as Settings.pxt.bak-nmdcs"
}

apply_via_console() {
	if ! rung_console; then
		say ""
		say "  ptokax@$HUB is running and its console socket is down. systemd will"
		say "  not enable a socket whose service is already up, so this costs one"
		say "  stop and start. Declining changes nothing."
		say ""
		confirm "stop ptokax@$HUB, enable the console socket, start it again?" || {
			say "  nothing changed. The other route is to stop the hub and come"
			say "  back here, which writes Settings.pxt directly."
			return 0
		}
		priv systemctl stop "ptokax@$HUB" || { say "  stop failed, nothing else tried"; return 0; }
		if ! priv systemctl enable --now "ptokax-console@$HUB.socket"; then
			say "  enable failed, starting the hub again"
			priv systemctl start "ptokax@$HUB" || true
			return 0
		fi
		priv systemctl start "ptokax@$HUB" || { say "  start failed, see journalctl -u ptokax@$HUB"; return 0; }
		i=0
		while [ $i -lt 10 ] && ! rung_console; do sleep 1; i=$((i + 1)); done
		rung_console || { say "  console socket still down, giving up"; return 0; }
		say "  console socket up, and it returns with sockets.target from now on"
	fi

	rung_tooling || { say "  needs socat or pxconsole, see ADMIN-GUIDE \"Lua console\""; return 0; }

	say ""
	hub_setting_chunk | sed 's/^/    /'
	say ""
	confirm "send this over the console?" || { say "  nothing changed"; return 0; }

	tmp=$(mktemp); hub_setting_chunk > "$tmp"
	if command -v socat >/dev/null 2>&1; then
		priv_sh "socat -t5 - 'UNIX-CONNECT:/run/ptokax/$HUB-console.sock' < '$tmp'" || say "  send failed"
	else
		priv_sh "pxconsole '$HUB' attach '$tmp'" || say "  send failed"
	fi
	rm -f "$tmp"
	say "  SetMan.Save writes cfg/ at once, so this survives a restart."
	say "  journalctl PTOKAX_SUBSYSTEM=console shows the output."
}

# --- page 4, nginx config ---------------------------------------------------
page_conf() {
	_own='STREAM_DIR CONFD_DIR'
	snapshot $_own
	while :; do
		head2 "4  nginx config"
		_blk=$(conf_blocked_by)
		if [ -n "$_blk" ]; then
			intro "Writes the stream block and the pinger snippet. It $_blk," \
			      "since the config names the binary's paths and the certificate."
		else
			intro "Writes the stream block nginx terminates NMDCS with, and the" \
			      "snippet that serves hubinfo.json."
		fi
		row a "stream dir" "${STREAM_DIR:-<detect>}" "stream {} is a sibling of http {}"
		row b "conf.d dir" "${CONFD_DIR:-<detect>}"  "pinger snippet, inside http {}"
		say ""
		act d "detect both from nginx -V"
		act i "write both files"
		act t "run nginx -t"
		act r "reset this page to defaults"
		act s "save and return"
		act q "discard changes and return"
		menu
		case $REPLY_KEY in
			a) edit STREAM_DIR "stream dir" "Directory included from a stream {} block at the top level of nginx.conf, not from conf.d." ;;
			b) edit CONFD_DIR "conf.d dir" "Directory the existing http {} block already includes." ;;
			d) detect_conf_dirs; pause ;;
			i) write_conf; pause ;;
			t) b=$(nginx_bin); [ -n "$b" ] && priv "$b" -t || say "  no nginx binary"; pause ;;
			r) reset_vars $_own; say "  page reset" ;;
			s) save_conf; return ;;
			q) restore; return ;;
		esac
	done
}

detect_conf_dirs() {
	p=$(nginx_conf_prefix 2>/dev/null || true)
	[ -n "$p" ] || { say "  could not read --conf-path from nginx -V"; return 0; }
	STREAM_DIR=$p/stream.d; CONFD_DIR=$p/conf.d
	save_conf
	say "  stream dir  $STREAM_DIR"
	say "  conf.d dir  $CONFD_DIR"
}

write_conf() {
	[ -n "$STREAM_DIR" ] || { say "  set or detect the stream dir first"; return 0; }
	d=$(hub_state_dir 2>/dev/null || true)

	priv_mkdir "$STREAM_DIR"
	sed -e "s|@TLSPORT@|$TLS_PORT|g" -e "s|@TCPPORT@|$TCP_PORT|g" \
	    -e "s|@CERT@|$CERT|g" -e "s|@KEY@|$KEY|g" \
	    -e "s|@PROXYADDR@|$PROXY_ADDR|g" -e "s|@HUBADDR@|$HUB_ADDR|g" \
	    "$here/stream.conf" | priv_write "$STREAM_DIR/ptokax-nmdcs.conf"
	say "  wrote $STREAM_DIR/ptokax-nmdcs.conf"

	if [ -n "$CONFD_DIR" ] && [ -n "$d" ]; then
		priv_mkdir "$CONFD_DIR"
		sed -e "s|@STATEDIR@|$d|g" "$here/hubinfo.conf" | priv_write "$CONFD_DIR/ptokax-hubinfo.conf"
		say "  wrote $CONFD_DIR/ptokax-hubinfo.conf"
	else
		say "  pinger snippet skipped, needs both a conf.d dir and a hub state dir"
	fi

	say ""
	say "  nginx.conf needs this at the top level, outside http {}:"
	say ""
	say "      stream {"
	say "          include $STREAM_DIR/*.conf;"
	say "      }"
	save_conf
}

# --- page 5, systemd --------------------------------------------------------
page_systemd() {
	_own='USE_SYSTEMD NGINX_USER'
	snapshot $_own
	while :; do
		head2 "5  systemd"
		intro "Units to keep nginx running and to hand PtokaX its proxy socket." \
		      "The nginx unit runs as an unprivileged account, created here."
		row a "use systemd" "$USE_SYSTEMD" "in effect: $(have_systemd && echo yes || echo no)"
		row b "nginx runs as" "$NGINX_USER" "$(user_exists "$NGINX_USER" && echo 'exists' || echo 'created when the unit is installed')"
		say ""
		row "" "nginx unit"   "$([ -f /etc/systemd/system/nginx-ptokax.service ] && echo installed || echo 'not installed')"
		row "" "proxy socket" "$([ -n "$HUB" ] && [ -f "/etc/systemd/system/ptokax@$HUB.socket.d/20-proxy.conf" ] && echo installed || echo 'not installed')"
		say ""
		act p "install the proxy socket drop-in for ptokax@${HUB:-<hub>}"
		act n "install a hardened unit for the source-built nginx"
		act e "start or restart nginx through systemd"
		act x "start or reload nginx directly, no systemd"
		act r "reset this page to defaults"
		act s "save and return"
		act q "discard changes and return"
		menu
		case $REPLY_KEY in
			a) edit USE_SYSTEMD "use systemd" "auto detects /run/systemd/system, yes and no force it" auto yes no ;;
			b) edit NGINX_USER "nginx runs as" "User= and Group= on the nginx unit, so nginx never runs as root" ;;
			p) install_proxy_socket; pause ;;
			n) install_nginx_unit; pause ;;
			e) restart_nginx; pause ;;
			x) start_nginx_direct; pause ;;
			r) reset_vars $_own; say "  page reset" ;;
			s) save_conf; return ;;
			q) restore; return ;;
		esac
	done
}

install_proxy_socket() {
	have_systemd || { say "  systemd is switched off on this page"; return 0; }
	[ -n "$HUB" ] || { say "  set a hub name on page 3 first"; return 0; }
	if [ ! -f /etc/systemd/system/ptokax@.socket ] && [ ! -f /usr/lib/systemd/system/ptokax@.socket ]; then
		say "  ptokax@.socket is not installed, so socket activation is not in use."
		say "  PtokaX binds TLSProxyAddress itself then, and this drop-in is not"
		say "  needed. Install the units with: make install"
		return 0
	fi
	dir=/etc/systemd/system/ptokax@$HUB.socket.d
	priv_mkdir "$dir"
	printf '[Socket]\nListenStream=%s\nFileDescriptorName=proxy\n' "$PROXY_ADDR" | priv_write "$dir/20-proxy.conf"
	say "  wrote $dir/20-proxy.conf"
	priv systemctl daemon-reload
	confirm "restart ptokax@$HUB.socket now?" && priv systemctl restart "ptokax@$HUB.socket"
	return 0
}

install_nginx_unit() {
	have_systemd || { say "  systemd is switched off on this page"; return 0; }
	d=$(hub_state_dir 2>/dev/null || true)
	[ -n "$d" ] || { say "  need a hub state dir, it becomes ReadOnlyPaths"; return 0; }
	gen=$here/../systemd/unitgen.sh
	[ -x "$gen" ] || { say "  unitgen.sh not found at $gen"; return 0; }

	if ! user_exists "$NGINX_USER"; then
		say "  $NGINX_USER does not exist. The unit runs nginx as this account"
		say "  instead of root, so it has to exist before the unit starts."
		confirm "create $NGINX_USER as a system user?" || return 0
		priv useradd --system --no-create-home --shell /usr/sbin/nologin "$NGINX_USER" \
			|| { say "  useradd failed"; return 0; }
	fi

	v=$(systemctl --version 2>/dev/null | sed -n '1s/^systemd \([0-9]*\).*/\1/p'); [ -n "$v" ] || v=0
	"$gen" --systemd-version="$v" \
		--define="NGINXBIN=$(nginx_bin)" \
		--define="NGINXUSER=$NGINX_USER" \
		--define="STATEDIR=$d" \
		--define="docdir=/usr/share/doc/ptokax" \
		< "$here/nginx.service.in" | priv_write /etc/systemd/system/nginx-ptokax.service
	say "  wrote /etc/systemd/system/nginx-ptokax.service for systemd $v"
	priv systemctl daemon-reload
	command -v systemd-analyze >/dev/null 2>&1 && systemd-analyze verify /etc/systemd/system/nginx-ptokax.service || true
	return 0
}

restart_nginx() {
	have_systemd || { say "  systemd is switched off, use the direct option"; return 0; }
	unit=nginx-ptokax
	[ -f /etc/systemd/system/nginx-ptokax.service ] || unit=nginx
	b=$(nginx_bin); [ -n "$b" ] || { say "  no nginx binary"; return 0; }
	priv "$b" -t || { say "  config test failed, not restarting"; return 0; }
	priv systemctl restart "$unit"
	priv systemctl --no-pager --lines=5 status "$unit" || true
	return 0
}

start_nginx_direct() {
	b=$(nginx_bin); [ -n "$b" ] || { say "  no nginx binary"; return 0; }
	priv "$b" -t || { say "  config test failed"; return 0; }
	if priv "$b" -s reload 2>/dev/null; then say "  reloaded"; else priv "$b"; say "  started"; fi
	return 0
}

# --- page 6, verify ---------------------------------------------------------
page_verify() {
	head2 "6  verify"
	say ""
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

	d=$(hub_state_dir 2>/dev/null || true)
	if [ -n "$d" ] && [ -f "$d/hubinfo.json" ]; then
		say ""; say "  $d/hubinfo.json present"
	elif [ -n "$d" ]; then
		say ""; say "  no $d/hubinfo.json yet, written 60s after start once"
		say "  PingerAddresses is set"
	fi
	pause
}

# --- main -------------------------------------------------------------------
main_menu() {
	while :; do
		head2 "PtokaX NMDCS setup"
		row 1 "nginx"        "$(st_nginx)"   ""
		row 2 "certificate"  "$(st_cert)"    "$CERT_METHOD"
		row 3 "hub settings" "$(st_hub)"     ""
		row 4 "nginx config" "$(st_conf)"    "$(conf_blocked_by)"
		row 5 "systemd"      "$(st_systemd)" ""
		act 6 "verify"
		say ""
		act R "reset everything to defaults"
		act q "quit"
		say ""
		printf '    choices kept in %s\n' "$CONF"
		menu
		case $REPLY_KEY in
			1) page_nginx ;;
			2) page_cert ;;
			3) page_hub ;;
			4) page_conf ;;
			5) page_systemd ;;
			6) page_verify ;;
			R) confirm "reset every setting?" && { set_defaults; save_conf; say "  reset"; } ;;
			q|Q) exit 0 ;;
		esac
	done
}

case ${1:-} in
	-h|--help)
		printf 'Usage: %s\n\nInteractive. Choices are kept in %s and reused next run.\nOverride that path with PX_NGINX_SETUP_CONF.\n' "$self" "$CONF"
		exit 0 ;;
esac

main_menu
