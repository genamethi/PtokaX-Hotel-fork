# firewalld

The default frontend on the RHEL family. Rich rules carry a rate limit, and firewalld
writes nftables underneath, so the enforcement is the same as `nftables.nft`.

See `POLICY` for where the numbers come from.

## Rate limit

	firewall-cmd --permanent --add-rich-rule='rule family="ipv4" port port="411" protocol="tcp" accept limit value="10/m"'
	firewall-cmd --permanent --add-rich-rule='rule family="ipv4" port port="5411" protocol="tcp" accept limit value="10/m"'
	firewall-cmd --permanent --add-rich-rule='rule family="ipv6" port port="411" protocol="tcp" accept limit value="10/m"'
	firewall-cmd --permanent --add-rich-rule='rule family="ipv6" port port="5411" protocol="tcp" accept limit value="10/m"'
	firewall-cmd --reload

## What this does not do

The rich rule limit is a total rate for the port, not a rate per source address. One
address at the limit blocks every other client, where `nftables.nft` blocks only that
address.

For a per-address limit, firewalld passes rules through to nftables directly:

	firewall-cmd --permanent --direct --add-rule inet filter INPUT 0 \
		-p tcp -m multiport --dports 411,5411 -m conntrack --ctstate NEW \
		-m hashlimit --hashlimit-name ptokax --hashlimit-mode srcip \
		--hashlimit-above 10/minute -j DROP
	firewall-cmd --reload

`--direct` rules are not managed by the zone model and firewalld has deprecated them.
A host that needs the per-address form is better served by `nftables.nft`.

## SYN floods

No synproxy through firewalld.

	sysctl -w net.ipv4.tcp_syncookies=1
