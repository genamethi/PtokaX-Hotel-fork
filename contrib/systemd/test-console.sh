#!/bin/sh
# Exercise the Lua console against a real systemd instance.
#
# Needs root, socat and systemd 240 or newer. Everything it creates is
# transient: units under /run/systemd/system, a binary copy under /run, and one
# state directory. All of it is removed on exit, including after a failure.
#
#   sudo ./contrib/systemd/test-console.sh
#
# The instance is named apart from any real hub, so a running production
# instance is left alone. Takes about a minute, most of it the input deadline.

set -eu

self=${0##*/}
srcdir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

INST=t1
TEMPLATE=pxconsoletest
UNITDIR=/run/systemd/system
BINDIR=/run/$TEMPLATE/bin
SOCK=/run/$TEMPLATE/$INST-console.sock
SERVICE=$TEMPLATE@$INST.service
SOCKET=$TEMPLATE-console@$INST.socket

pass=0
fail=0
CUR=

say() { printf '%s\n' "$*"; }
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }
die() { printf '%s: %s\n' "$self" "$*" >&2; exit 1; }

mark() { CUR=$(journalctl -u "$SERVICE" -n0 --show-cursor --no-pager 2>/dev/null |
	sed -n 's/^-- cursor: //p'); }

jlog() {
	ac=
	[ -n "$CUR" ] && ac="--after-cursor=$CUR"
	journalctl -u "$SERVICE" $ac --no-pager "$@" 2>/dev/null || :
}

send() { printf '%s' "$1" | socat - UNIX-CONNECT:"$SOCK" 2>/dev/null || :; sleep 1; }

# -t keeps socat reading after it closes its own write side, long enough
# for an attached chunk to finish
ask() { printf '%s\n' "$1" | socat -t5 - UNIX-CONNECT:"$SOCK" 2>/dev/null || :; }

cleanup() {
	systemctl stop "$SOCKET" "$SERVICE" "ptokax-console@$INST.socket" >/dev/null 2>&1 || :
	systemctl reset-failed "$SOCKET" "$SERVICE" "ptokax-console@$INST.socket" >/dev/null 2>&1 || :
	rm -f "/run/ptokax/$INST-console.sock"
	rm -f "$UNITDIR/$TEMPLATE@.service" "$UNITDIR/$TEMPLATE-console@.socket"
	systemctl daemon-reload >/dev/null 2>&1 || :
	rm -rf "/run/$TEMPLATE" "/var/lib/private/$TEMPLATE" "/var/lib/$TEMPLATE"
}

#-------------------------------------------------------------------- preflight

[ "$(id -u)" -eq 0 ] || die "must be run as root"

for prog in socat systemctl journalctl systemd-run stat; do
	command -v "$prog" >/dev/null 2>&1 || die "$prog is required"
done

[ -x "$srcdir/PtokaX" ] || die "$srcdir/PtokaX is not built -- run make first"
[ -f "$srcdir/contrib/systemd/ptokax-console@.socket.in" ] || die "cannot find the unit templates"

sdver=$(systemctl --version | awk 'NR==1 {print $2; exit}')
sdver=${sdver%%[!0-9]*}
[ "${sdver:-0}" -ge 240 ] || die "systemd 240 or newer is required, found ${sdver:-unknown}"

trap cleanup EXIT INT TERM

#------------------------------------------------------------------------ setup

say "setting up $TEMPLATE@$INST"

mkdir -p "$BINDIR"
cp "$srcdir/PtokaX" "$BINDIR/PtokaX"
chmod 0755 "$BINDIR/PtokaX"

gen() { "$srcdir/contrib/systemd/unitgen.sh" --systemd-version="$sdver" \
	--define=bindir="$BINDIR" --define=sysconfdir="/run/$TEMPLATE" \
	--define=datadir="/run/$TEMPLATE" --define=docdir="/run/$TEMPLATE"; }

# a separate template name keeps a real ptokax@ instance out of this
gen < "$srcdir/contrib/systemd/ptokax@.service.in" |
	sed -e "s/ptokax-%i/$TEMPLATE-%i/g" -e "s#ptokax/%i#$TEMPLATE/%i#g" \
	    -e "s/^Sockets=ptokax-console@/Sockets=$TEMPLATE-console@/" \
	> "$UNITDIR/$TEMPLATE@.service"

gen < "$srcdir/contrib/systemd/ptokax-console@.socket.in" |
	sed -e "s#/run/ptokax/#/run/$TEMPLATE/#" \
	    -e "s/^RuntimeDirectory=ptokax\$/RuntimeDirectory=$TEMPLATE/" \
	    -e "s/ptokax@%i\.service/$TEMPLATE@%i.service/" \
	> "$UNITDIR/$TEMPLATE-console@.socket"

systemctl daemon-reload

# systemd-run, not mkdir: the directory needs the unit's own identity
systemd-run --quiet --collect --wait --pipe \
	--unit="$TEMPLATE-mkdir-$INST" \
	--property="User=$TEMPLATE-$INST" \
	--property="DynamicUser=yes" \
	--property="StateDirectory=$TEMPLATE/$INST" \
	--property="StateDirectoryMode=0700" \
	/bin/true >/dev/null 2>&1 || die "could not create the state directory"

statedir=$(readlink -f "/var/lib/$TEMPLATE/$INST")
mkdir -p "$statedir/cfg" "$statedir/scripts" "$statedir/texts" "$statedir/logs"
cp "$srcdir/cfg.example/"* "$statedir/cfg/" 2>/dev/null || :

port=34119
while ss -ltnH 2>/dev/null | awk '{print $4}' | grep -q ":$port\$"; do
	port=$((port + 1))
done

if grep -qE '^[[:space:]]*TCPPorts[[:space:]]*=' "$statedir/cfg/Settings.pxt" 2>/dev/null; then
	sed -i "s/^\([[:space:]]*TCPPorts[[:space:]]*=[[:space:]]*\).*/\1$port/" "$statedir/cfg/Settings.pxt"
else
	printf 'TCPPorts\t=\t%s\n' "$port" >> "$statedir/cfg/Settings.pxt"
fi
cat > "$statedir/scripts/pxtest.lua" <<'PXTEST'
px_test_marker = "pxtest-alive"

function PxTestSum(a, b)
	return a + b
end
PXTEST

chown -R --reference="$statedir" "$statedir"

say "port $port, state $statedir"
say ""

#-------------------------------------------------- the socket before the service

say "socket unit"

systemctl start "$SOCKET"

if [ -S "$SOCK" ]; then
	ok "socket exists before the service has ever started"
else
	bad "socket exists before the service has ever started"
fi

mode=$(stat -c '%a %U:%G' "$SOCK" 2>/dev/null || echo none)
if [ "$mode" = "600 root:root" ]; then
	ok "socket is root:root 0600"
else
	bad "socket is root:root 0600 (got $mode)"
fi

if [ -n "${SUDO_USER:-}" ] && command -v runuser >/dev/null 2>&1; then
	if runuser -u "$SUDO_USER" -- \
		sh -c "printf 'print(1)' | socat - UNIX-CONNECT:$SOCK" >/dev/null 2>&1; then
		bad "an unprivileged user is refused"
	else
		ok "an unprivileged user is refused"
	fi
fi

#------------------------------------------------------------------ send and log

say ""
say "console"

mark
systemctl start "$SERVICE"
sleep 2

if systemctl is-active --quiet "$SERVICE"; then
	ok "the hub starts with the socket already listening"
else
	bad "the hub starts with the socket already listening"
fi

if jlog | grep -q "Lua console listening"; then
	ok "the hub inherited the console fd through Sockets="
else
	bad "the hub inherited the console fd through Sockets="
fi

if jlog | grep -q "nothing claimed"; then
	bad "exactly one console socket was passed"
else
	ok "exactly one console socket was passed"
fi

marker="console-test-$$"
mark
send "print(\"$marker\")"

if jlog | grep -q "$marker"; then
	ok "print output reached the journal"
else
	bad "print output reached the journal"
fi

if jlog -o json | grep -q '"PTOKAX_SUBSYSTEM"[[:space:]]*:[[:space:]]*"console"'; then
	ok "output carries PTOKAX_SUBSYSTEM=console as a journal field"
else
	bad "output carries PTOKAX_SUBSYSTEM=console as a journal field"
fi

if journalctl PTOKAX_SUBSYSTEM=console --no-pager -n 50 2>/dev/null | grep -q "$marker"; then
	ok "journalctl PTOKAX_SUBSYSTEM=console finds it"
else
	bad "journalctl PTOKAX_SUBSYSTEM=console finds it"
fi

prio=$(jlog -o json | grep "$marker" |
	sed -n 's/.*"PRIORITY"[[:space:]]*:[[:space:]]*"\([0-9]\)".*/\1/p' | head -1)
if [ "${prio:-}" = 6 ]; then
	ok "print logs at info"
else
	bad "print logs at info (got ${prio:-none})"
fi

#----------------------------------------------------------------------- the API

say ""
say "hub API"

mark
send 'print("version:" .. Core.Version)'
if jlog | grep -q "version:"; then
	ok "the hub API is registered in the console state"
else
	bad "the hub API is registered in the console state"
fi

mark
send "SetMan.SetString(SetMan.tStrings.HubTopic, \"$marker\")"
send 'print("topic:" .. SetMan.GetString(SetMan.tStrings.HubTopic))'
if jlog | grep -q "topic:$marker"; then
	ok "a setting written by one chunk is read by the next"
else
	bad "a setting written by one chunk is read by the next"
fi

mark
send 'leaked_global = 1'
send 'print("leaked:" .. tostring(leaked_global))'
if jlog | grep -q "leaked:nil"; then
	ok "each connection gets a fresh state"
else
	bad "each connection gets a fresh state"
fi

#---------------------------------------------------------------------- directives

say ""
say "directives"

# CheckForNewScripts adds a file it has not seen disabled, so it needs starting
mark
send 'print("start:" .. tostring(ScriptMan.StartScript("pxtest.lua")))'
if jlog | grep -q "start:true"; then
	ok "the test script started"
else
	bad "the test script started"
fi

reply=$(ask 'print("bare chunk")')
if [ -z "$reply" ]; then
	ok "a bare chunk still gets no reply"
else
	bad "a bare chunk still gets no reply (got $reply)"
fi

row=$(ask '--!px list' | awk -F'\t' '$1 == "pxtest.lua" { print; exit }')
if [ -n "$row" ]; then
	ok "list has a row for the running script"
else
	bad "list has a row for the running script"
fi

state=$(printf '%s' "$row" | cut -f2)
if [ "$state" = enabled ]; then
	ok "the row reports it enabled"
else
	bad "the row reports it enabled (got ${state:-none})"
fi

path=$(printf '%s' "$row" | cut -f4)
if [ -n "$path" ] && [ -f "$path" ]; then
	ok "the row carries a path that exists"
else
	bad "the row carries a path that exists (got ${path:-none})"
fi

printf 'px_late = 1\n' > "$statedir/scripts/pxlate.lua"
chown --reference="$statedir" "$statedir/scripts/pxlate.lua"

if ask '--!px list' | grep -q '^pxlate\.lua'; then
	bad "a file added since start is absent until the hub looks again"
else
	ok "a file added since start is absent until the hub looks again"
fi

send 'ScriptMan.Refresh()'

if ask '--!px list' | grep -q '^pxlate\.lua'; then
	ok "ScriptMan.Refresh puts it in the list"
else
	bad "ScriptMan.Refresh puts it in the list"
fi

reply=$(ask 'px_attached = 41 + 1
--!px attach pxtest.lua')
if [ "$reply" = ok ]; then
	ok "attach replies ok"
else
	bad "attach replies ok (got ${reply:-none})"
fi

# the assert carries the check, so this does not depend on where print goes
reply=$(ask 'assert(px_attached == 42, "got " .. tostring(px_attached))
--!px attach pxtest.lua')
if [ "$reply" = ok ]; then
	ok "a global set by one attach survives to the next"
else
	bad "a global set by one attach survives to the next (got ${reply:-none})"
fi

reply=$(ask 'assert(px_test_marker == "pxtest-alive")
assert(PxTestSum(1, 2) == 3)
--!px attach pxtest.lua')
if [ "$reply" = ok ]; then
	ok "attach reaches what the script itself defined"
else
	bad "attach reaches what the script itself defined (got ${reply:-none})"
fi

reply=$(ask '--!px attach nosuch.lua')
if [ "$reply" = "error: no such script" ]; then
	ok "attaching to an unknown script is refused"
else
	bad "attaching to an unknown script is refused (got ${reply:-none})"
fi

reply=$(ask '--!px attach pxlate.lua')
if [ "$reply" = "error: script not running" ]; then
	ok "attaching to a disabled script is refused"
else
	bad "attaching to a disabled script is refused (got ${reply:-none})"
fi

reply=$(ask '--!px bogus')
if [ "$reply" = "error: unknown directive" ]; then
	ok "an unknown directive is refused"
else
	bad "an unknown directive is refused (got ${reply:-none})"
fi

mark
reply=$(ask 'local a = 1
local b = 2
error("attach boom")
--!px attach pxtest.lua')
if printf '%s' "$reply" | grep -q '^error: .*attach boom'; then
	ok "a runtime error under attach comes back in the reply"
else
	bad "a runtime error under attach comes back in the reply (got ${reply:-none})"
fi

if jlog -p err | grep -q "stack traceback"; then
	ok "the same error logs a traceback"
else
	bad "the same error logs a traceback"
fi

if jlog -p err | grep -q "console:3:"; then
	ok "the traceback line number is the line the client sent"
else
	bad "the traceback line number is the line the client sent"
fi

reply=$(ask 'assert(px_attached == 42)
--!px attach pxtest.lua')
if [ "$reply" = ok ]; then
	ok "the error left the script running with its state intact"
else
	bad "the error left the script running with its state intact (got ${reply:-none})"
fi

# -u closes the read side, so the hub replies to nobody
printf 'px_noread = 1\n--!px attach pxtest.lua\n' |
	socat -u - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1 || :
sleep 1

if systemctl is-active --quiet "$SERVICE"; then
	ok "a client that never reads the reply leaves the hub healthy"
else
	bad "a client that never reads the reply leaves the hub healthy"
fi

#--------------------------------------------------------------------- the edges

say ""
say "errors and limits"

mark
send 'this is not lua ('
if jlog -p err | grep -q "syntax error"; then
	ok "a syntax error logs at err"
else
	bad "a syntax error logs at err"
fi

mark
send 'error("deliberate")'
if jlog -p err | grep -q "stack traceback"; then
	ok "a runtime error logs a traceback"
else
	bad "a runtime error logs a traceback"
fi

if systemctl is-active --quiet "$SERVICE"; then
	ok "the hub survived both errors"
else
	bad "the hub survived both errors"
fi

mark
{
	printf -- '-- '
	dd if=/dev/zero bs=1024 count=1100 2>/dev/null | tr '\0' 'x'
	printf '\nprint("oversize ran")\n'
} | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1 || :
sleep 1

if jlog | grep -q "over the size limit"; then
	ok "a chunk over the size limit is refused"
else
	bad "a chunk over the size limit is refused"
fi

if jlog | grep -q "oversize ran"; then
	bad "the oversize chunk did not run"
else
	ok "the oversize chunk did not run"
fi

say ""
say "holding a connection open past the deadline, this takes 30s"

mark
{ printf 'print("held open")'; sleep 40; } | socat - UNIX-CONNECT:"$SOCK" >/dev/null 2>&1 &
holder=$!
sleep 38
kill "$holder" 2>/dev/null || :
wait "$holder" 2>/dev/null || :

if jlog | grep -q "no end of input"; then
	ok "a connection that never sends EOF is dropped"
else
	bad "a connection that never sends EOF is dropped"
fi

if jlog | grep -q "held open"; then
	bad "the abandoned chunk did not run"
else
	ok "the abandoned chunk did not run"
fi

#------------------------------------------------------------------- lifecycles

say ""
say "lifecycle"

systemctl stop "$SERVICE"
sleep 1

if [ -S "$SOCK" ]; then
	ok "the socket survives the hub stopping"
else
	bad "the socket survives the hub stopping"
fi

if systemctl restart "$SOCKET" >/dev/null 2>&1; then
	ok "the socket restarts while the hub is stopped"
else
	bad "the socket restarts while the hub is stopped"
fi

systemctl start "$SERVICE"
sleep 2

if systemctl restart "$SOCKET" >/dev/null 2>&1; then
	bad "starting the socket under a running hub is refused"
else
	ok "starting the socket under a running hub is refused"
fi

systemctl restart "$SERVICE"
sleep 2
mark
send 'print("after restart")'
if jlog | grep -q "after restart"; then
	ok "the hub picks the socket up again after a restart"
else
	bad "the hub picks the socket up again after a restart"
fi

#--------------------------------------------------------------------- teardown

say ""
say "teardown"

systemctl stop "$SOCKET"

if [ -S "$SOCK" ]; then
	bad "RemoveOnStop removed the socket"
else
	ok "RemoveOnStop removed the socket"
fi

if systemctl is-active --quiet "$SERVICE"; then
	ok "stopping the socket left the hub running"
else
	bad "stopping the socket left the hub running"
fi

#---------------------------------------------------------------------- summary

say ""
say "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
