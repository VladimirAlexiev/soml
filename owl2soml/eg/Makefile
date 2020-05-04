IGNORE = skos-fix.ttl skos-xl.ttl skos-thes.ttl
TTL    = $(filter-out $(IGNORE), $(wildcard *.ttl))
YAML   = $(patsubst %.ttl, %.yaml, $(TTL)) # schema1.yaml

all : clean $(YAML)

clean :
	find . -size 0 -delete

%.yaml : ../owl2soml.pl %.ttl
	time perl $^ $(EXTRA) > $@ 2> $*.log

skos.yaml		: EXTRA = skos-fix.ttl
gvp.yaml		: EXTRA = skos.ttl skos-fix.ttl skos-xl.ttl # skos-thes.ttl
dct_owldl.yaml		: EXTRA = -voc dcterms
schema.yaml		: EXTRA = -voc schema
schema-all-layers.yaml  : EXTRA = -voc schema
fibo-FND.yaml		: EXTRA = -voc NONE -id fibo-FND -label "FIBO Foundation" 

## Read more bytes than requested. Do you use an encoding-related PerlIO layer?
# schema1.yaml : ../owl2soml.pl schema.rdf
# 	perl ../owl2soml.pl -voc schema schema.rdf > schema1.yaml
