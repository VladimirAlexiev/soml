IGNORE          = skos-fix.ttl skos-xl.ttl skos-thes.ttl dbo-archivo-202502.ttl dbo-databus-202407.ttl dbo-defs.ttl dbo-lov-201605.ttl
TTL             = $(filter-out $(IGNORE), $(wildcard *.ttl) dbo.ttl)
YAML            = $(patsubst %.ttl, %.yaml, $(TTL))
OWL2SOML        = ../../bin/owl2soml.pl
SOML_SIMPLIFY   = ../../bin/soml-simplify.pl

all : clean $(YAML) dbo-simplified.yaml SWAPI-lang1.yaml SWAPI-lang2.yaml

clean :
	find . -size 0 -delete

%.yaml : %.ttl
	time perl $(OWL2SOML) $^ $(EXTRA) > $@ 2> $*.log
	time perl $(OWL2SOML) $^ -super 1 $(EXTRA) > $*-super.yaml 2> $*-super.log

dbo.ttl: dbo-simplify.ru dbo-databus-202407.ttl
	update.bat --update=dbo-simplify.ru --data=dbo-databus-202407.ttl --dump > temp.ttl
	owl.bat write temp.ttl dbo.ttl
	rm temp.ttl

dbo-simplified.yaml: dbo.yaml
	perl $(SOML_SIMPLIFY) $^ > $@

SWAPI-lang1.yaml : SWAPI.ttl
	time perl $(OWL2SOML) $^ $(EXTRA) > $@ 2> SWAPI-lang1.log

SWAPI-lang2.yaml : SWAPI.ttl
	time perl $(OWL2SOML) $^ $(EXTRA) > $@ 2> SWAPI-lang2.log

SWAPI.yaml              : EXTRA = -id swapi -name rdfs:label
SWAPI-lang1.yaml        : EXTRA = -id swapi -name rdfs:label -lang en
SWAPI-lang2.yaml        : EXTRA = -id swapi -name rdfs:label -lang "fetch: en, validate: en,fr;UNIQ, implicit: en"
skos.yaml               : EXTRA = -name skos:prefLabel skos-fix.ttl
gvp.yaml                : EXTRA = skos.ttl skos-fix.ttl skos-xl.ttl # skos-thes.ttl
dct_owldl.yaml          : EXTRA = -voc dcterms
dbo.yaml                : EXTRA = -voc dbo
schema.yaml             : EXTRA = -voc schema
schema-all-layers.yaml  : EXTRA = -voc schema
fibo-FND.yaml           : EXTRA = -voc NONE -id fibo-FND -label "FIBO Foundation" 

## Read more bytes than requested. Do you use an encoding-related PerlIO layer?
# schema1.yaml : $(OWL2SOML) schema.rdf
# 	perl $(OWL2SOML) -voc schema schema.rdf > schema1.yaml
