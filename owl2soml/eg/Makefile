IGNORE = skos-fix.ttl
TTL    = $(filter-out $(IGNORE), $(wildcard *.ttl))
YAML   = $(patsubst %.ttl, %.yaml, $(TTL)) # schema1.yaml

all : clean $(YAML)

clean :
	find . -size 0 -delete

%.yaml : ../owl2soml.pl %.ttl
	time perl $^ > $@ 2> $*.log

skos.yaml : ../owl2soml.pl skos.rdf skos-fix.ttl
	time perl $^ > $@ 2> $*.log

dct_owldl.yaml : ../owl2soml.pl dct_owldl.ttl
	time perl ../owl2soml.pl -voc dcterms dct_owldl.ttl > $@ 2> $*.log

schema.yaml : ../owl2soml.pl schema.ttl
	time perl ../owl2soml.pl -voc schema > $@ 2> $*.log

## Read more bytes than requested. Do you use an encoding-related PerlIO layer?
# schema1.yaml : ../owl2soml.pl schema.rdf
# 	perl ../owl2soml.pl -voc schema schema.rdf > schema1.yaml
