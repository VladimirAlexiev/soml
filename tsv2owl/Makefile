
otkg-and-schema.ttl ::
	curl -Ls "https://docs.google.com/spreadsheets/d/11_PY93IT6HcNIXM8Mn0WzVux9z-X-OXWpHCWpnP9ED4/export?format=tsv" | \
	  perl -S tsv2owl.pl -v s: -o otkg: -t | cat otkg-preamble.ttl - > otkg-and-schema-unformatted.ttl
	riot.bat --formatted=ttl otkg-and-schema-unformatted.ttl | perl -00e '@a=<>; print sort @a' > otkg-and-schema.ttl
	# rm otkg-and-schema-unformatted.ttl # keep for debugging

# This sheet may not be exactly compatible with the latest version
STRAT.ttl ::
	curl -Ls "https://docs.google.com/spreadsheets/d/1xhDNls0zRB16HzwjPNwbEnDvvbb7M1K_o1NT-_P2NKE/export?format=tsv" | \
	  perl -S tsv2owl.pl -v k2: -o k2: -t | cat STRAT-preamble.ttl - > STRAT-unformatted.ttl
	riot.bat --formatted=ttl STRAT-unformatted.ttl | perl -00e '@a=<>; print sort @a' > STRAT.ttl
