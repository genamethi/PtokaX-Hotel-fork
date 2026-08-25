#!/bin/sh
# Render a PtokaX unit template for a target systemd version.
#
#   unitgen.sh --systemd-version=N [--define name=value]... < in > out
#
# Two guard forms are understood:
#
#   Directive=value        #@since N     drop the line when target < N
#   #@if systemd >= N  / #@elif systemd >= N / #@else / #@endif
#
# A version of 0 drops every guarded directive, which is the safe direction for an
# unknown target.
set -eu

version=
defines=

usage() {
	cat >&2 <<'EOF'
Usage: unitgen.sh --systemd-version=N [--define name=value]... < template > unit
EOF
}

for arg do
	case $arg in
	--systemd-version=*) version=${arg#*=} ;;
	--define=*) defines="$defines ${arg#*=}" ;;
	--define) usage; exit 2 ;;
	-h|--help) usage; exit 0 ;;
	*) printf 'unitgen.sh: unknown argument %s\n' "$arg" >&2; usage; exit 2 ;;
	esac
done

case $version in
'' ) printf 'unitgen.sh: --systemd-version is required\n' >&2; exit 2 ;;
*[!0-9]* ) printf 'unitgen.sh: --systemd-version must be a number, got %s\n' "$version" >&2; exit 2 ;;
esac

awk -v target="$version" -v defines="$defines" '
BEGIN {
	n = split(defines, d, / +/)
	for (i = 1; i <= n; i++) {
		if (d[i] == "") continue
		eq = index(d[i], "=")
		if (eq == 0) continue
		key[++keys] = substr(d[i], 1, eq - 1)
		val[keys]   = substr(d[i], eq + 1)
	}
	depth = 0          # nesting is not supported; depth is 0 or 1
	emit  = 1          # emitting lines in the current block?
	taken = 0          # has a branch of the current #@if already matched?
}

function substitute(s,   i) {
	for (i = 1; i <= keys; i++) gsub("@" key[i] "@", val[i], s)
	return s
}

/^[ \t]*#@if[ \t]+systemd[ \t]*<[ \t]*[0-9]+/ {
	match($0, /[0-9]+[ \t]*$/); want = substr($0, RSTART, RLENGTH) + 0
	depth = 1; taken = (target < want); emit = taken
	next
}
/^[ \t]*#@if[ \t]+systemd[ \t]*>=[ \t]*[0-9]+/ {
	match($0, /[0-9]+[ \t]*$/); want = substr($0, RSTART, RLENGTH) + 0
	depth = 1; taken = (target >= want); emit = taken
	next
}
/^[ \t]*#@elif[ \t]+systemd[ \t]*>=[ \t]*[0-9]+/ {
	if (depth == 0) { print "unitgen.sh: #@elif outside #@if" > "/dev/stderr"; exit 1 }
	match($0, /[0-9]+[ \t]*$/); want = substr($0, RSTART, RLENGTH) + 0
	emit = (!taken && target >= want)
	if (emit) taken = 1
	next
}
/^[ \t]*#@else[ \t]*$/ {
	if (depth == 0) { print "unitgen.sh: #@else outside #@if" > "/dev/stderr"; exit 1 }
	emit = !taken; taken = 1
	next
}
/^[ \t]*#@endif[ \t]*$/ {
	if (depth == 0) { print "unitgen.sh: #@endif outside #@if" > "/dev/stderr"; exit 1 }
	depth = 0; emit = 1; taken = 0
	next
}

!emit { next }

# Trailing "#@since N" guard on a single directive.
/#@since[ \t]+[0-9]+[ \t]*$/ {
	match($0, /[0-9]+[ \t]*$/); want = substr($0, RSTART, RLENGTH) + 0
	if (target < want) next
	sub(/[ \t]*#@since[ \t]+[0-9]+[ \t]*$/, "")
}

{ print substitute($0) }

END {
	if (depth != 0) { print "unitgen.sh: unterminated #@if" > "/dev/stderr"; exit 1 }
}
'
