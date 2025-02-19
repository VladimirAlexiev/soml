# Converting Ontologies to SOML

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Converting Ontologies to SOML](#converting-ontologies-to-soml)
- [Intro](#intro)
- [Ontologies](#ontologies)
    - [SKOS](#skos)
    - [DCTerms](#dcterms)
    - [DBPedia Ontology](#dbpedia-ontology)
        - [Which DBpedia Ontology](#which-dbpedia-ontology)
    - [Schema.org](#schemaorg)
    - [Getty Vocabulary Program](#getty-vocabulary-program)
    - [FIBO](#fibo)
    - [Cocktails](#cocktails)

<!-- markdown-toc end -->

# Intro

See `owl2soml/README` for tool usage instructions and notes about specific ontologies.

This `owl2soml/eg/README` gives information about performance, formats and bugs encountered.
- A `Makefile` causes all conversions to be rerun if the script or the input file(s) are changed.
- `.log` files are created for each conversion.

# Ontologies

## SKOS

We had to write `skos-fix.ttl` to attach various props to `Concept`.
Timing and warnings:

```
time perl ../owl2soml.pl skos.rdf skos-fix.ttl > skos.yaml
Multiple ranges found for prop member, using only the first one: Concept
real    0m8.796s
user    0m0.015s
sys     0m0.046s
```

## DCTerms

We tried an OWL DL rendition of DCT.
- We have to specify the vocab prefix because `owl:Ontology` uses a different URL
- Many props are not attached (defined on `rdfs:Resource`)

```sh
perl ../owl2soml.pl -voc dcterms dct_owldl.ttl > dct_owldl.yaml
```

## DBPedia Ontology
(Added 2/18/2025)

We produce [dbo.yaml](dbo.yaml) (a SOML schema), 
and [dbo-simplified.yaml](dbo-simplified.yaml) (a pared-down version used for LLM query generation):

```sh
time perl ../../bin/owl2soml.pl dbo.ttl -voc dbo > dbo.yaml 2> dbo.log
perl ../../bin/soml-simplify.pl dbo.yaml > dbo-simplified.yaml
wc dbo.ttl dbo*.yaml | grep -v total | sort -rn
  34270  124861 1314303 dbo.ttl
  25072   61434  625751 dbo.yaml
   4006    7234  102907 dbo-simplified.yaml
```
You can see the significant reduction in size compared to the Turtle ontology: 
1.36x for SOML, and 8.5x for simplified.

See next version for peculiarities and problems I had to fix.

Remaining problems:
- Prefixes are not defined in the simplified version. Use prefixes defined in the full version
- Different naming of `prov` classes (which are misdefined as `dbo:prov:*` in the ontology)
```yaml
prov_Entity:
  avgRevSizePerMonth: '[iri]'
  avgRevSizePerYear: '[iri]'
  nbRevPerMonth: '[iri]'
  nbRevPerYear: '[iri]'
  nbUniqueContrib: '[integer]'
Prov_Revision:
  isMinorRevision: '[boolean]'
  wikiPageLengthDelta: '[integer]'
```

### Which DBpedia Ontology
Where to get the `dbo` ontology?
- http://dev.dbpedia.org/Download_DBpedia#ontology is the documentation for download, but isn't very helpful
- https://databus.dbpedia.org/denis/ontology/dbo-snapshots gives 404
- http://dbpedia.org/ontology/data/definitions.ttl : saved as `dbo-defs.ttl` with 10363 triples: nogood
```
curl -L -Haccept:text/turtle http://dbpedia.org/ontology/data/definitions.ttl > dbo-defs.ttl
```
- https://lov.linkeddata.es/dataset/lov/vocabs/dbpedia-owl/versions/2016-05-21.n3 :
  saved as `dbo-lov-201605.ttl` with 30740 triples
- https://archivo.dbpedia.org/list#list gives https://archivo.dbpedia.org/download?o=http%3A//dbpedia.org/ontology/&f=ttl ,
reformatted with `owl write` and saved as `dbo-archivo-202502.ttl` with 34126 triples
  - Got error "Not advised IRI: `<Prov:Revision>` Code: 11/LOWERCASE_PREFERRED in SCHEME: lowercase is preferred in this component"
  - Also added prefixes
```ttl
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix dbo: <http://dbpedia.org/ontology/>.
@prefix voaf: <http://purl.org/vocommons/voaf#>.
@prefix owl: <http://www.w3.org/2002/07/owl#>.
@prefix cc:   <http://creativecommons.org/ns#>.
@prefix dbd: <http://dbpedia.org/datatype/>.
@prefix ov: <http://open.vocab.org/terms/>.
@prefix dct: <http://purl.org/dc/terms/>.
@prefix vann: <http://purl.org/vocab/vann/>.
@prefix foaf: <http://xmlns.com/foaf/0.1/>.
@prefix powder:  <http://www.w3.org/2007/05/powder-s#>.
@prefix prov: <http://www.w3.org/ns/prov#>.
@prefix xsd: <http://www.w3.org/2001/XMLSchema#>.
```

- https://databus.dbpedia.org/ontologies/dbpedia.org/ontology--DEV/2024.07.29-001000 gives https://databus.dbpedia.org/ontologies/dbpedia.org/ontology--DEV/2024.07.29-001000/ontology--DEV_type=parsed.ttl :
  reformatted with `owl write` and saved as `dbo-databus-202407.ttl` with 34653 triples
  - Added prefixes
```ttl
@prefix dbo:    <http://dbpedia.org/ontology/> .
@prefix dbd:    <http://dbpedia.org/datatype/>.
@prefix dbmo:   <http://mappings.dbpedia.org/index.php/OntologyClass:>.
@prefix dbpo:   <http://mappings.dbpedia.org/index.php/OntologyProperty:>.
@prefix bib:    <https://bib.schema.org/>.
@prefix bibo:   <http://purl.org/ontology/bibo/>.
@prefix dblp:   <https://dblp.org/rdf/schema-2020-07-01#>.
@prefix gn:     <http://www.geonames.org/ontology#> .
@prefix gnd:    <https://d-nb.info/standards/elementset/gnd#>.
@prefix mo:     <http://purl.org/ontology/mo/>.
@prefix nl-bag: <http://bag.basisregistraties.overheid.nl/def/bag#>.
@prefix nl-ceo: <https://linkeddata.cultureelerfgoed.nl/vocab/def/ceo#>.
@prefix nl-rkd: <http://data.rkd.nl/def#>.
@prefix schema: <http://schema.org/> .
@prefix skos:   <http://www.w3.org/2004/02/skos/core#> .
```

We'll work with this version.
This ontology has the following peculiarities:
- Has numerous links to external ontologies including `subClassOf`, eg
```ttl
dbo:Agent a owl:Class ;
  owl:equivalentClass dul:Agent ;
  owl:equivalentClass wikidata:Q24229398 ;
dbo:Band a owl:Class ;
  rdfs:subClassOf dbo:Group ;
  rdfs:subClassOf schema:MusicGroup ;
  rdfs:subClassOf dul:SocialPerson .
dbo:governmentPosition a owl:ObjectProperty, rdf:Property ;
  rdfs:range wgs84pos:SpatialThing ;
  rdfs:subPropertyOf dul:sameSettingAs .
dbo:PenaltyShootOut a owl:Class ;
  rdfs:subClassOf dul: .
```
- Because of that last defective link (empty local name) https://github.com/dbpedia/ontology-tracker/issues/39 ,
  the script fails with an exception. 
```
Can't parse dul: into dul: ?!
```
- Also, those external classes and properties are not described in `dbo`: 
  so I've removed all links 
  `owl:equivalentClass owl:equivalentProperty rdfs:subClassOf rdfs:subPropertyOf` 
  to external terms and saved as `dbo.ttl` (32829 triples)
  - But I kept `rdfs:range` though in some cases they are non-sensical 
    (eg `dbo:governmentPosition->wgs84pos:SpatialThing` as above)
- Defines two classes in wrong namespace (https://github.com/dbpedia/ontology-tracker/issues/38) :
```
dbo:prov:Entity a owl:Class .
dbo:prov:Revision a owl:Class .
```
- Two classes violate the naming convention:
```
dbo:company
dbo:year
```
- Uses non-standard datatypes that are a mixture of 
  units of measure (without any link to quantity kind or conversion factor), 
  and some unclear things (perhaps strings):
```
@prefix dbd: <http://dbpedia.org/datatype/> .

dbo:configuration a owl:DatatypeProperty, rdf:Property ;
  rdfs:domain dbo:AutomobileEngine ;
  rdfs:range dbd:engineConfiguration .
dbd:engineConfiguration a rdfs:Datatype ;
  rdfs:label "engineConfiguration"@en .

<http://dbpedia.org/ontology/Astronaut/timeInSpace> a owl:DatatypeProperty ;
  rdfs:range dbd:minute .
dbd:minute a rdfs:Datatype ;
  rdfs:label "minute"@en .
```
These are actually used in data, eg:
```ttl
dbr:Rover_KV6_engine
  dbo:configuration
    "V6"^^dbd:engineConfiguration.
dbr:Pyotr_Dubrov
  <http://dbpedia.org/ontology/Astronaut/timeInSpace>
    "511425.0"^^dbd:minute.
```
But custom datatypes are not used in SOML, and the convertor returned errors like this:
`Prop configuration is owl:DatatypeProperty or owl:AnnotationProperty but has range class dbd:engineConfiguration`
So we replaced most of them with `decimal`, and only 2 with `string`: `dbd:fuelType, dbd:engineConfiguration`

- Has multilingual labels in 36 langs (EN is the biggest: 5153 labels):
```
grep -o -P '@\w+' dbo.ttl|sort|uniq -c
    108 @am
     25 @ar
      5 @be
     14 @bg
      4 @bn
     29 @ca
     19 @cs
    147 @da
   2197 @de
   1367 @el
   5153 @en
    267 @es
     16 @eu
   1561 @fr
    459 @ga
     50 @gl
     24 @hi
      1 @hy
      8 @in
    258 @it
    584 @ja
    234 @ko
      1 @kr
      3 @lv
      1 @mk
   1479 @nl
    139 @pl
    248 @pt
      1 @ro
     50 @ru
      1 @sk
     26 @sl
    267 @sr
     27 @tr
   1199 @ur
     27 @zh
```
- 140 class-specific props, eg `<http://dbpedia.org/ontology/Weapon/length>`
- 16 multivalued `domain` or `range` that leads to invalid class URLs 
  (reported in 2016 as [dbpedia/ontology-tracker#14](https://github.com/dbpedia/ontology-tracker/issues/14) not yet fixed), eg
```ttl
rdfs:domain <http://dbpedia.org/ontology/MilitaryConflict,_AdministrativeRegion>
rdfs:range  <http://dbpedia.org/ontology/Organisation,_Person>
```
- redeclares XSD datatypes
```ttl
xsd:nonNegativeInteger a rdfs:Datatype
```

## Schema.org

Download:
- Location https://schema.org/docs/developers.html
- You can download `jsonld`, `rdf` and `ttl` but:
  - `schema.nt` is not appropriate because it doesn't define prefixes, so we can't obtain GraphQL (developer-friendly) class and prop names.
  - `schemaorg.owl` is missing.
    https://schema.org/docs/schemaorg.owl and https://webschemas.org/docs/schemaorg.owl give error 404 Not Found.
    Posted [schemaorg#2472](https://github.com/schemaorg/schemaorg/issues/2472).
    - Note: "Experimental/Unsupported: schema:domainIncludes and schema:rangeIncludes values are converted into rdfs:domain and rdfs:range values using owl:unionOf to capture the multiplicity of values. Included in the range values are the, implicit within the vocabulary, default values of Text, URL, and Role. As an experimental feature, there are no expectations as to its interpretation by any third party tools."
- We have to specify the `-voc` prefix because schema.org doesn't define an `owl:Ontology`.

```sh
time perl ../owl2soml.pl schema.ttl -voc schema > schema.yaml 2> schema.log
real    3m39.310s
user    0m0.000s
sys     0m0.078s
```

- `schema.ttl`: worked ok, see [schema.yaml](schema.yaml)
  - This is the largest ontology I've tested (508k ttl, 730k rdf, 808k jsonld; results in 428k yaml) and it takes substantial time to process: posted [attean#154](https://github.com/kasei/attean/issues/154)
  - SOML does not yet support multiple inheritance (issue PLATFORM-360), so we get a bunch of warnings like: `Multiple superclasses found for schema:PaymentCard, using only the first one: FinancialProduct`. 
  - Schema.org uses multiple domains and ranges pervasively. SOML supports the former but not the latter (issue PLATFORM-1493 to support multiple ranges), so we get a bunch of warnings like `Multiple ranges found for prop interestRate, using only the first one: QuantitativeValue`
- Should perhaps strip HTML tags from descriptions, eg `<br/><br/>\n\n  <ul>\n   <li><a class="localLink" href="http://schema.org/RejectAction">RejectAction</a>: The antonym of AcceptAction.</li>`
- [schema.ttl](https://schema.org/version/latest/schema.ttl) does not define all classes used as ranges (issue [schemaorg#2537](https://github.com/schemaorg/schemaorg/issues/2537)); [all-layers.ttl](https://schema.org/version/latest/all-layers.ttl) defines them.
  This pertains to `CategoryCode CssSelectorType DefinedTerm EducationalOccupationalCredential GeospatialGeometry PhysicalActivityCategory XPathType`.
- `schema.jsonld`: needs extra module `AtteanX::Parser::JSONLD`. 
  - Uses a very poor context and doesn't define the `schema:` namespace, so is not usable by the tool, posted [schemaorg#2477](https://github.com/schemaorg/schemaorg/issues/2477). Causes error `can't find vocab_iri of --vocab prefix schema`
- `schema.rdf`: Caused error `Read more bytes than requested`, 
  posted [rt.cpan.org#131982](https://rt.cpan.org/Ticket/Display.html?id=131982), see [LibXML-schema.rdf.err](LibXML-schema.rdf.err) eg:

```sh
time perl ../owl2soml.pl -voc schema schema.rdf    > schema3.yaml
Read more bytes than requested. Do you use an encoding-related PerlIO layer? at C:/Strawberry/perl/vendor/lib/XML/LibXML.pm line 882.
```

## Getty Vocabulary Program

- `gvp.ttl` is saved from http://vocab.getty.edu/ontology.ttl
- Fixed a wrong range `rdf:Literal` to `rdfs:Literal` (reported to Getty)
- This imports other ontologies (`skos.ttl skos-xl.ttl`) so we include them as extra inputs.
- It also imports `skos-thes.ttl` but we skip it because it causes error `No suitable prefix for IRI <http://ec.europa.eu/esco/model#statusDataType>`
- Timing:

```sh
make  gvp.yaml
time perl ../owl2soml.pl gvp.ttl skos.ttl skos-fix.ttl skos-xl.ttl > gvp.yaml 2> gvp.log

real    1m10.143s
user    0m0.015s
sys     0m0.031s
```

- A few warnings like `Multiple superclasses found for Facet, using only the first one: Subject`
- Multiple warnings like `Found multiple labels for property gvp:tgn3101_near-adjacent_to, using the first one: tgn3101_near-adjacent_to, near/adjacent to - any`. The reason is that GVP [Relationship Representation](http://vocab.getty.edu/doc/#Relationship_Representation) emits the local name in `skos:prefLabel` and "<name> - <range>" in `dc:title`, but the tool handles only one label per prop:

```ttl
gvp:aat2208_locus-setting_for a owl:ObjectProperty;
  skos:prefLabel "aat2208_locus-setting_for";
  dc:title "locus/setting for - things".
```
- GVP includes partially duplicated decriptions (`rdfs:comment+skos:example=dct:description`), eg

```ttl
gvp:GroupConcept a owl:Class ;
  rdfs:isDefinedBy <http://vocab.getty.edu/ontology> ;
  rdfs:subClassOf gvp:Subject, skos:Concept ;
  rdfs:label "GroupConcept" ;
  rdfs:comment "Two or more people who generally worked together to collectively create art. Not necessarily legally incorporated. A family of artists may be considered a \"corporate body\". Corresponds to crm:E74_Group, not its subclass crm:E40_Legal_Body" ;
  skos:example "500356337 Albrecht Duerer Workshop (ULAN)" ;
  dct:description "Two or more people who generally worked together to collectively create art. Not necessarily legally incorporated. A family of artists may be considered a \"corporate body\". Corresponds to crm:E74_Group, not its subclass crm:E40_Legal_Body.\nExample: 500356337 Albrecht Duerer Workshop (ULAN)".
```

Since the tool concatenates multiple descriptions, this causes partially duplicated descriptions, eg:

```yaml
  GroupConcept:
    descr: |-
      Two or more people who generally worked together to collectively create art. Not necessarily legally incorporated. A family of artists may be considered a "corporate body". Corresponds to crm:E74_Group, not its subclass crm:E40_Legal_Body. Two or more people who generally worked together to collectively create art. Not necessarily legally incorporated. A family of artists may be considered a "corporate body". Corresponds to crm:E74_Group, not its subclass crm:E40_Legal_Body.
      Example: 500356337 Albrecht Duerer Workshop (ULAN)
```

## FIBO

FIBO is a large family of fintech-related ontologies.
- Obtained the latest [dev.ttl.zip](https://spec.edmcouncil.org/fibo/ontology/master/latest/dev.ttl.zip) (Mar 2020). After you remove all `catalog` files and `ont-policy` (Jena ontology/document policy), this makes 321 Turtle files, 8.6 Mb.
- That'd probably be too much for the perl implementation of the tool, so we took the FND Subset: 75 files (1.2Mb). This includes:
  - 2 "All" files that just import other ontologies
  - 18 "Metadata" files with info *about* ontologies
  - 55 proper ontologies (1.09 Mb ttl), including some individuals. 
- We use only this subset and concatenate the Turtle files for simplicity:

```
find latest/FND/* -type f ! -name "Metadata*" ! -name "All*" | xargs cat > fibo-FND.ttl
```
- Added 15 prefixes that are missing in some of these files, see [fibo#995](https://github.com/edmcouncil/fibo/issues/995)
- Mapped `fibo-fnd-dt-fd:CombinedDateTime` to datatype `dateOrYearOrMonth` (a named scalar union)
- Ignore the datatype `owl:rational`, which will have the effect of downgrading it to string.
  - `owl:rational` are exact ratios of integers (eg `1/3`) that are a super-set of `xsd:decimal`, and represented differently (as two integers separated with a slash). 
     So mapping to `xsd:decimal` won't really work
- SOML currently does not allow punctuation (`_-.`) in prefixes or local names (issue PLATFORM-1625).
  So a prop like `fibo-fnd-acc-aeq:Equity` is mapped to `fibofndaccaeq:Equity`, which is not good.
- FIBO does not have a dominant ontology, so we use `-id` and
  run without `vocab_prefix` to avoid giving special treatment to any of the 55 fibo-FND ontologies.
- Timing:

```sh
make fibo-FND.yaml
time perl ../owl2soml.pl -id fibo-FND -label "FIBO Foundation" fibo-FND.ttl > fibo-FND.yaml 2> fibo-FND.log

real    5m27.442s
user    0m0.015s
sys     0m0.046s
```

## Cocktails

Cocktail Ontology is a simple PoolParty schema extending `skos:Concepts` with specific classes and properties:
- Uses dashes in prop names (eg `cocktail-ontology:is-used-by`) that are removed (eg `isusedby`) since SOML does not yet allow punctuation in names.
- Should filter out empty descriptions like `""@de` or `"  \n     "@de`.
