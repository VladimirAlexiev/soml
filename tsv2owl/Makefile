.DELETE_ON_ERROR:

all: otkg.ttl otkg-domain-range.ttl

otkg-unformatted.ttl::
	curl -Ls "https://docs.google.com/spreadsheets/d/11_PY93IT6HcNIXM8Mn0WzVux9z-X-OXWpHCWpnP9ED4/export?format=tsv" | \
	  perl -S tsv2owl.pl -v s: -o otkg: -t | cat otkg-preamble.ttl - > otkg-unformatted.ttl

otkg.ttl: otkg-unformatted.ttl
	riot.bat --formatted=ttl $^ | perl -00e '@a=<>; print sort @a' > $@

otkg-domain-range.ttl: otkg-unformatted.ttl
	update.bat --update=../bin/tsv2owl-domain-range.ru --data=$^ --dump | perl -00e '@a=<>; print sort @a' > $@

# This sheet may not be exactly compatible with the latest version
STRAT.ttl::
	curl -Ls "https://docs.google.com/spreadsheets/d/1xhDNls0zRB16HzwjPNwbEnDvvbb7M1K_o1NT-_P2NKE/export?format=tsv" | \
	  perl -S tsv2owl.pl -v k2: -o k2: -t | cat STRAT-preamble.ttl - > STRAT-unformatted.ttl
	riot.bat --formatted=ttl STRAT-unformatted.ttl | perl -00e '@a=<>; print sort @a' > STRAT.ttl
