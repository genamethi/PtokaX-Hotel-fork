# ufw

The default frontend on Ubuntu and Debian. It covers part of what `POLICY` describes
and the shortfall is worth knowing before relying on it.

## What ufw gives you

	ufw limit 411/tcp
	ufw limit 5411/tcp

`ufw limit` is fixed at 6 connections per 30 seconds per address. The rate is not
configurable through ufw, so `NewConnectionsCount` and `NewConnectionsTime` have no
frontend equivalent. Editing the generated rule puts it out of step with `ufw status`
and it is rewritten on reload.

There is no synproxy.

	sysctl -w net.ipv4.tcp_syncookies=1

## Raising the limit

ufw reads `/etc/ufw/before.rules` before its own chains, and rules there survive a
reload. This is the same hashlimit rule as `iptables.rules`, at the POLICY numbers:

	# /etc/ufw/before.rules, above the *filter COMMIT line
	-A ufw-before-input -p tcp -m multiport --dports 411,5411 -m conntrack --ctstate NEW \
		-m hashlimit --hashlimit-name ptokax --hashlimit-mode srcip \
		--hashlimit-above 10/minute -j DROP

Leave `ufw limit` off those ports when using this, otherwise both limits apply and the
lower one wins.

## Which to use

A host already running ufw and wanting the POLICY numbers is running iptables rules
inside a ufw file. `nftables.nft` states the same thing in one place. ufw is the right
choice when 6 per 30 seconds is close enough.
