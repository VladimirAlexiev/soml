# Converting Ontologies to SOML

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Converting Ontologies to SOML](#converting-ontologies-to-soml)
- [Intro](#intro)
- [Ontologies](#ontologies)
    - [SKOS](#skos)
    - [DCTerms](#dcterms)
    - [Schema.org](#schema-org)
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


## Schema.org

Download:
- Location https://schema.org/docs/developers.html
- Downloaded `jsonld`, `rdf` and `ttl`
- `schema.nt` is not appropriate because it doesn't define prefixes, so we can't obtain GraphQL (developer-friendly) class and prop names.
- `schemaorg.owl` is missing.
  https://schema.org/docs/schemaorg.owl and https://webschemas.org/docs/schemaorg.owl give error 404 Not Found.
  Posted [schemaorg#2472](https://github.com/schemaorg/schemaorg/issues/2472).
  - Note: "Experimental/Unsupported: schema:domainIncludes and schema:rangeIncludes values are converted into rdfs:domain and rdfs:range values using owl:unionOf to capture the multiplicity of values. Included in the range values are the, implicit within the vocabulary, default values of Text, URL, and Role. As an experimental feature, there are no expectations as to its interpretation by any third party tools."
- Should perhaps strip HTML tags from descriptions, eg `<br/><br/>\n\n  <ul>\n   <li><a class="localLink" href="http://schema.org/RejectAction">RejectAction</a>: The antonym of AcceptAction.</li>`
- This is the largest ontology I've tested (508k ttl, 730k rdf, 808k jsonld; results in 428k yaml) and it takes substantial time to process: posted [attean#154](https://github.com/kasei/attean/issues/154)
- We have to specify the `-voc` prefix because schema.org doesn't define an `owl:Ontology`.

```sh
time perl ../owl2soml.pl -voc schema schema.ttl    > schema1.yaml
real    4m9.203s
user    0m0.000s
sys     0m0.094s
```

- `schema.ttl`: worked ok, see [schema.yaml](schema.yaml)
  - SOML does not yet support multiple inheritance (issue PLATFORM-360), so we get a bunch of warnings like: `Multiple superclasses found for schema:PaymentCard, using only the first one: FinancialProduct`. 
  - Schema.org uses multiple domains and ranges pervasively. SOML supports the former but not the latter (issue PLATFORM-1493 to support multiple ranges), so we get a bunch of warnings like `Multiple ranges found for prop interestRate, using only the first one: QuantitativeValue`
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
-  Fixed a wrong range `rdf:Literal` to `rdfs:Literal` (reported to Getty)
- A few warnings like `Multiple superclasses found for gvp:Facet, using only the first one: Subject`
- Multiple warnings like `Found multiple labels for property gvp:tgn3101_near-adjacent_to, using the first one: tgn3101_near-adjacent_to, near/adjacent to - any`. The reason is that GVP [Relationship Representation](http://vocab.getty.edu/doc/#Relationship_Representation) emits the local name in `skos:prefLabel` and "<name> - <range>" in `dc:title`, but the tool handles only one label per prop:

```ttl
gvp:aat2208_locus-setting_for a owl:ObjectProperty;
  skos:prefLabel "aat2208_locus-setting_for";
  dc:title "locus/setting for - things".
```
- GVP includes partially duplicated decriptions (`rdfs:comment+skos:example=dct:description), eg

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
- Mapped `fibo-fnd-dt-fd:CombinedDateTime` to datatype `dateOrYearOrMonth` (a named scalar union)
- Mapped `owl:rational` to `xsd:decimal` even though that won't really work because `owl:rational` are exact ratios of integers (eg `1/3`) that are a super-set of `xsd:decimal`, and represented differently (as two integers separated with a slash)
- SOML currently does not allow punctuation (`_-.`) in prefixes or local names (issue PLATFORM-1625).
  So a prop like `fibo-fnd-acc-aeq:Equity` is mapped to `fibofndaccaeq:Equity`, which is not good.
- FIBO does not have a dominant ontology. 
  Currently the first encountered ontology
  (https://spec.edmcouncil.org/fibo/ontology/FND/Arrangements/Communications/) 
  is treated specially: the `fibo-fnd-arr-com:` is treated as `vocab_prefix` 
  and is stripped from GraphQL names.
  It would be better to run without `vocab_prefix` and afford it no such special treatment.
- Timing:

```sh
make fibo-FND.yaml
time perl ../owl2soml.pl fibo-FND.ttl > fibo-FND.yaml 2> fibo-FND.log

real    5m27.442s
user    0m0.015s
sys     0m0.046s
```

## Cocktails

Cocktail Ontology is a simple PoolParty schema extending `skos:Concepts` with specific classes and properties:
- Uses dashes in prop names (eg `cocktail-ontology:is-used-by`) that are removed (eg `isusedby`) since SOML does not yet allow punctuation in names.
- Should filter out empty descriptions like `""@de` or `"  \n     "@de`.
