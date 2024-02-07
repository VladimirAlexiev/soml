Current minor problems:

## OTKG
```
make
curl -Ls "https://docs.google.com/spreadsheets/d/11_PY93IT6HcNIXM8Mn0WzVux9z-X-OXWpHCWpnP9ED4/export?format=tsv" | \
  perl -S tsv2owl.pl -v s: -o otkg: -t | cat otkg-preamble.ttl - > otkg-and-schema-unformatted.ttl
line 140: OntotextPerson has s:jobTitle but replacement=none: ignoring this prop
line 141: OntotextPerson has s:sameAs but replacement=none: ignoring this prop
riot.bat --formatted=ttl otkg-and-schema-unformatted.ttl | perl -00e '@a=<>; print sort @a' > otkg-and-schema.ttl
```

## STRAT 
(This is an old client project, just for demo
```
make STRAT.ttl
curl -Ls "https://docs.google.com/spreadsheets/d/1xhDNls0zRB16HzwjPNwbEnDvvbb7M1K_o1NT-_P2NKE/export?format=tsv" | \
  perl -S tsv2owl.pl -v k2: -o k2: -t | cat STRAT-preamble.ttl - > STRAT-unformatted.ttl
Prop k2:input: range k2:Product,k2:Material has no rdf_replaced at D:\GitHub\soml\bin/tsv2owl.pl line 153, <ARGV> line 282.
riot.bat --formatted=ttl STRAT-unformatted.ttl | perl -00e '@a=<>; print sort @a' > STRAT.ttl
```