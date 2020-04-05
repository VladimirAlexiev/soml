# owl2soml

Generate SOML schema from RDFS/OWL/Schema ontologies

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [owl2soml](#owl2soml)
- [Usage](#usage)
    - [Features](#features)
        - [Ontologies](#ontologies)
        - [`vocab_prefix, vocab_iri`](#vocab_prefix-vocab_iri)
        - [Classes](#classes)
            - [subClassOf](#subclassof)
        - [Properties](#properties)
            - [Domain and Range](#domain-and-range)
        - [Datatypes](#datatypes)
        - [Labels and Descriptions](#labels-and-descriptions)
    - [Limitations](#limitations)
        - [Handle Property Inheritance](#handle-property-inheritance)
        - [Handle OWL Restrictions](#handle-owl-restrictions)
        - [Handle OWL Cardinalities](#handle-owl-cardinalities)
    - [Gaps in Ontologies](#gaps-in-ontologies)
    - [Dependencies](#dependencies)
        - [Dependency Problems](#dependency-problems)
    - [Change Log](#change-log)
- [Platform Service](#platform-service)

<!-- markdown-toc end -->

# Usage

```
owl2soml.pl ontology.(ttl|rdf) ... > ontology.yaml
Options:
  --vocab pfx     Uses "pfx" as the main vocab_prefix
```

The [Semantic Objects Modeling Language (SOML)](http://platform.ontotext.com/soml/index.html)
is a simple YAML-based language for describing business objects (business entities, domain objects) 
that are handled using semantic technologies and GraphQL.
It is the basis of the [Ontotext Platform](http://platform.ontotext.com/) that helps create knowledge graphs in an easier way.
See https://github.com/VladimirAlexiev/soml for motivation, description and links.

`owl2soml` is a command-line tool to generate SOML from RDFS/OWL/Schema ontologies.
It is still evolving.
- We have tested it on various ontologies (see [owl2soml/eg](https://github.com/VladimirAlexiev/soml/tree/master/owl2soml/eg)) and continue testing on more and refining it.
- If you test it on more ontologies, please describe your experience in an issue or pull request
- If you find problems or want to suggest a new feature, post an issue

We also have plans to rewrite the tool in Java, as a [Platform Service](#platform-service).

## Features

`owl2soml` can read ontologies in these RDF formats: RDF/XML, Turtle, JSONLD.
It requires approprite prefixes to be defined, so it can obtain GraphQL (developer-friendly) class and prop names.
- NTriples is not an appropriate format because it doesn't define prefixes.
- Some JSONLD ontologies do not define a good context and are not usable by the tool.
  For example, the [schema.org JSONLD distribution](https://schema.org/docs/developers.html) has a very poor context 
  and doesn't define the `schema:` prefix, see [schemaorg#2477](https://github.com/schemaorg/schemaorg/issues/2477)

The tool handles the following features.

### Ontologies

The first provided RDF file should contain the "root" ontology.
This means that the default `vocab_prefix` is assigned to it (see next section),
and the tool looks for an `owl:Ontology` node (optional) to extract metadata.

The following ontology metadata is handled:
- label (see [Labels and Descriptions](#labels-and-descriptions))
- dct:created, dct:modified. If dateTime stamp is provided, only the date part is used.
- dc:creator, dct:creator. It handles literal or IRI `creator` and concatenates if it finds multiple values.
- owl:versionInfo
  
### `vocab_prefix, vocab_iri`

`vocab_prefix` is the default prefix of a SOML schema, and `vocab_iri` is the corresponding namespace.
It's convenient to have one for better GraphQL names:
- RDF elements (classes and props) in the `vocab_iri` namespace get nice names like `Class` and `prop`
- RDF elements in other namespaces get longer names like `pfx_Class` and `pfx_prop`

`vocab_prefix` and `vocab_iri` are searched in the following order:

1. If the option `--vocab` is provided, it sets `vocab_prefix`
   (it can also be shortened to `-voc`, `-v`, etc).
   The same prefix must also be defined in the input RDF and is used to find `vocab_iri`.
2. If the prop `swc:identifier` of `owl:Ontology` is defined, it sets `vocab_prefix`.
   A slash is appended to the ontology URL and used as `vocab_iri`.
   This is how [PoolParty Custom Schemes](https://help.poolparty.biz/pp/user-guide-for-knowledge-engineers/advanced-features/ontology-management-overview/the-custom-scheme-and-ontology-management-tree) work.
3. If the prop `vann:preferredNamespaceUri` of `owl:Ontology` is defined (it must be a string), it sets `vocab_iri`.
   Then the value of `vann:preferredNamespacePrefix` 
   (or simply the prefix corresponding to `vann:preferredNamespaceUri`)
   is used as `vocab_prefix`.
   These are part of [VANN: A vocabulary for annotating vocabulary descriptions](https://vocab.org/vann/) and also used in VOID.
4. If a prefix is defined that matches the ontology IRI with appended `[#/]?` (optional hash or slash),
   that is used as `vocab_prefix` and the corresponding namespace as `vocab_iri`.
5. Otherwise the tool quits with an error.

`vocab_prefix` is also used in the SOML identifier, 
which is used for SOML operations (create, update, delete, bind) [by the SOaaS services](http://platform.ontotext.com/semantic-objects/semantic-objects.html#define-star-wars-semantic-objects):

```yaml
id: /soml/$vocab_prefix
```

Also, the prop `swc:BaseUrl` of `owl:Ontology` is used to set `base_iri`.
This is currently not used to shorten IRIs in GraphQL queries and responses, but may be in the future.

### Classes

The tool recognizes instances of `rdfs:Class` and/or `owl:Class` as classes:
- If one instance has both types, it's processed only once
- Anonymous (blank node) classes are ignored
- It ignores instances of `schema:DataType` and that class itself (see [Datatypes](#datatypes) below)
- Also ignores the classes `owl:Thing, owl:Nothing` that are not useful for querying

Classes are processed as follows:
- The chars `[-_.]` are removed from class & property local names in order to make valid GraphQL names.
- Gets class [Labels and Descriptions](#labels-and-descriptions)
- If a property range is not defined in the ontology, it is emitted in SOML as a class without any props,
  otherwise the SOML schema would be invalid
- Class inheritance is processed as described in the next section

#### subClassOf

`rdfs:subClassOf` is emitted in SOML as `inherits`.
- Anonymous (blank node) classes are ignored
- Currently the platform doesn't support multiple inheritance, so only the first superclass is used.

GraphQL represents superclasses as interfaces, and interfaces cannot have instances.
Also, it does not allow an interface and class (type) to have the same name as there would be a name conflict.

`owl2soml` uses a trick to generate dual entities:
a superclass `*` and a corresponding interface `*Interface`.
Consider this example from SKOS:

```ttl
skos:Collection a owl:Class .

skos:OrderedCollection a owl:Class ; rdfs:subClassOf skos:Collection .

skos:member a rdf:Property , owl:ObjectProperty ;
  rdfs:domain skos:Collection ;
  rdfs:range [a owl:Class ; owl:unionOf (skos:Concept skos:Collection)] .

skos:memberList a rdf:Property , owl:FunctionalProperty , owl:ObjectProperty ;
  rdfs:domain skos:OrderedCollection ;
  rdfs:range rdf:List .
```

It generates the following SOML schema:

```yaml
objects:
  CollectionInterface:
    kind: abstract
    props:
      member: {}
  Collection:
    inherits: CollectionInterface
  OrderedCollection:
    inherits: CollectionInterface
    props:
      memberList: {}
  rdf:List:
properties:
  member:
    kind: object
    max: inf
    range: Concept
  memberList:
    kind: object
    range: rdf:List
```

- `CollectionInterface` is generated as abstract superclass (`kind: abstract`)
- `Collection` is generated as concrete subclass that `inherits: CollectionInterface`.
  It is **not** used as a superclass (GraphQL would prevent you from having instances of it)
- Any subclasses refer to the interface, eg `OrderedCollection: {inherits: CollectionInterface}`
- The properties referencing `Collection` as domain/range are also migrated to refer to `CollectionInterface`.
  In this case there's only one: `member` has domain `CollectionInterface`.
  
By the way, this example shows two more aspects:
- Since `rdf:List` is referenced as a range but is not defined in SKOS, 
  it is declared as a class with no props.
- Only the first range of `skos:member` is used (see [Limitations](#limitations))

With this schema you can have instances of `Collection` and `OrderedCollection`
and can make GraphQL queries referencing `collection` and `orderedCollection`.

However, the generated GraphQL schema also has queries referencing `collectionInterface`,
which is confusing 
and if used, would require breaking changes to your queries if the class hierarchy changes.
So we consider queries like `collectionInterface` to be parasitic and bad practice.

Issue PLATFORM-1344 will implement Concrete Superclasses by generating 
the dual superclass and corresponding interface automatically behind the scenes,
and avoiding the parasitic queries.

### Properties

The tool recognizes instances of the following as props: `rdf:Property, owl:AnnotationProperty, owl:DatatypeProperty, owl:ObjectProperty`.
- If one instance has several types, it's processed only once.
- Normally each prop should have one of these basic prop types.
  However, some ontologies omit the basic type and declare props using 
  only the more advanced "prop characteristic" types:
  `owl:FunctionalProperty owl:InverseFunctionalProperty owl:ReflexiveProperty owl:IrreflexiveProperty owl:SymmetricProperty owl:AsymmetricProperty owl:TransitiveProperty`.
  So the tool recognizes these too.
- It doesn't recognize props 
  that participate in prop relations like `rdfs:domain, rdfs:range` but are not declared: 
  each prop must have one of the above types.
- It ignores the following, which are not useful for querying:
  `owl:topObjectProperty owl:bottomObjectProperty owl:topDataProperty owl:bottomDataProperty`

Properties are processed as follows:
- The chars `[-_.]` are removed from class & property local names in order to make valid GraphQL names.
- Gets prop [Labels and Descriptions](#labels-and-descriptions)
- Assigns `kind: literal` or `kind: object` depending on property type and range: 
  see [Datatypes](#datatypes) for details
- Processes the following prop characteristics:
  - `owl:FunctionalProperty` is mapped to `max: 1`. 
    Unfortunately too few ontologies use this characteristic, 
    so most properties end up with the cardinality `max: inf`, 
    which is significantly more expensive to query.
  - `owl:SymmetricProperty` is mapped to `symmetric: true`

`X owl:inverseOf Y` and `X schema:inverseOf Y` are mapped to two SOML assertions:
  
```yaml
properties:
  X: {inverseOf: Y}
  Y: {inverseOf: X}
```

- You must therefore have `Y` defined as a prop in the same ontology(ies),
- You must not have more than 2 props be inverses of each other.
- By the way, you don't need to have inverses actually stored in the RDF reposotory.
  You could use `inverseAlias` to navigate the SOML Knowledge Graph in any direction,
  without requiring the storage of inverse triples.

#### Domain and Range

The tool processes the following:
- domains (`rdfs:domain, schema:domainIncludes`). Multiple domains are allowed (which must be classes).
- ranges (`rdfs:range, schema:rangeIncludes`). Only the first encountered range is used. Class or datatype ranges are allowed.

The tool also handles `owl:unionOf` constructs, eg (`a owl:Class` is not necessary):

```ttl
:propP   rdfs:domain         [a owl:Class; owl:unionOf (:classX :classY :classZ].
:propP schema:domainIncludes [a owl:Class; owl:unionOf (:classX :classY)], :classZ.
:propP   rdfs:domain         [a owl:Class; owl:unionOf (:classX [a owl:Class; owl:unionOf (:classY :classZ)])].
```

In all these cases `:prop` is attached to (uses as domain) all mentioned classes:

```yaml
objects:
  classX: {props: {propP: {}}}
  classY: {props: {propP: {}}}
  classZ: {props: {propP: {}}}
```

### Datatypes

The tool handles the following datatypes:
- `xsd:` datatypes: `boolean, byte, date, dateTime, decimal, double, gYear, gYearMonth, int, integer, long, negativeInteger, nonNegativeInteger, nonPositiveInteger, positiveInteger, short, string, time, unsignedByte, unsignedInt, unsignedLong, unsignedShort`
- `schema:` (schema.org) datatypes: `Boolean, Date, DateTime, Float, Integer, Number, Text, Time`
- `schema:URL, rdfs:Resource, xsd:anyURI` are mapped to `iri`, i.e. a "free-standing" IRI that does not designate an instance (object) stored in the platform.
- You cannot use `owl:ObjectProperty` with a datatype range.
  - An `owl:ObjectProperty` without specified class is mapped to `iri` (a "free-standing" IRI)
- You cannot use `owl:DatatypeProperty` or `owl:AnnotationProperty` with a class range.
  - The default datatype of a prop that doesn't mention a range is `string`.
    This applies to `rdf:Property, owl:DatatypeProperty, owl:AnnotationProperty`.
  - These datatypes are also mapped to string: `rdf:langString, rdfs:Literal`.
  - Finally, `rdfs:Resource` is mapped to `iri`, a free-standing IRI pointing to an external resource

### Labels and Descriptions

The tool handles the following descriptive attributes of schema elements (Ontology, Classes and Properties):
- labels: `rdfs:label, skos:prefLabel, dc:title, dct:title`
- descriptions: `rdfs:comment, skos:definition, skos:description, skos:scopeNote, dc:description, dct:description`

It looks only for values without lang tag or with lang `en` (as well as "dialects" such as `en-US, en-GB`).
The reason is that many ontologies include translations, but SOML currently supports only one value per element.
Furthermore:
- If it finds several labels, it warns and uses only the first one
- If it finds several descriptions, it concatenates them separated with ". ". Duplicate descriptions are eliminated.
  - TODO: some ontologies (e.g. [Getty Vocabulary Program](http://vocab.getty.edu/ontology.ttl)) include partially duplicate descriptions like the following.
    Use substring matching to eliminate these partial duplicates.
    
```ttl
gvp:broaderGenericExtended a owl:ObjectProperty;
  rdfs:comment "Ancestors (Generic). Meaningful closure of gvp:broaderGeneric. Infers iso:broaderGeneric for pairs of directly related skos:Concepts";
  skos:example """<anvils and anvil accessories> BTG <forging and metal-shaping tools> BTG <forging and metal-shaping equipment>,
so <anvils and anvil accessories> BTGE <forging and metal-shaping equipment>""";
  dct:description """Ancestors (Generic). Meaningful closure of gvp:broaderGeneric. Infers iso:broaderGeneric for pairs of directly related skos:Concepts.
Example: <anvils and anvil accessories> BTG <forging and metal-shaping tools> BTG <forging and metal-shaping equipment>,
so <anvils and anvil accessories> BTGE <forging and metal-shaping equipment>""".
```

TODO: strip HTML tags, which are used e.g. in schema.org `rdfs:comment`:

```ttl
schema:AcceptAction a rdfs:Class ;
    rdfs:comment """The act of committing to/adopting an object.<br/><br/>

Related actions:<br/><br/>

<ul>
<li><a class="localLink" href="http://schema.org/RejectAction">RejectAction</a>: The antonym of AcceptAction.</li>
</ul>
""" ;
```

TODO:
- Trim leading and trailing whitespace including spaces and newlines
- Ignore empty labels/descriptions, which are found in some ontologies

## Limitations

In addition to TODOs sprinkled above, `owl2soml` (or the Ontotext Platform) 
has other limitations (thus ideas for improvement) that are described below.
If one of these limitations is especially important for you, please send feedback.
In some cases we've referenced the issue number in our internal issue tracker,
so you can enquire about the status of that particular issue.

- The platform supports metadata (`label:` and `descr`) in only one language, 
  so the tool uses only labels/descriptions without language tag,
  or in Egnlish and "dialects" (`en`, `en-US`, `en-GB`, etc).
- `owl:AnnotationProperty` and `owl:DatatypeProperty` are treated the same,
  but there are some ontologies that use `owl:AnnotationProperty` with resources.
- The platform does not yet support multiple inheritance, 
  so only the first superclass is used (PLATFORM-360).
- TODO: The platform does not yet support multiple prop ranges (union ranges), 
  so only one is used (PLATFORM-1493).
  The tool picks a random range, which is undeterministic.
- The platform does not yet support `rdf:langString`,
  so `rdf:langString` and `rdfs:Literal` are mapped to `xsd:string` (PLATFORM-1241).
  We are planning powerful features to fetch only selected languages, 
  language preference and fallback,
  find objects having values in certain languages,
  validation of languages on mutation, etc.
- Currently the platform handles only these prop characteristics:
  `owl:FunctionalProperty owl:SymmetricProperty` (and `inverseOf`)
  It should process more prop characteristics: 
  `owl:InverseFunctionalProperty owl:ReflexiveProperty owl:IrreflexiveProperty owl:AsymmetricProperty owl:TransitiveProperty`.
- SOML currently does not allow punctuation (`_-.`) in prefixes or local names (issue PLATFORM-1625).
  So a prop like `fibo-fnd-acc-aeq:Equity` is mapped to `fibofndaccaeq:Equity`, which is not good.
  Such prefixes are prevalent in FIBO. 
  Other ontologies (especially related to biology and life sciences) use punctuation (even `:`) in local names.

### Better Handling of Multiple Ontologies

To handle numerous related ontologies (eg like FIBO), these improvements could be relevant:

- The tool doesn't handle `owl:import`. Instead, provide multiple ontologies on input
  (or in the case of FIBO I've concatenated Turtle files)
- Takes metadata only from `owl:Ontology` of the first supplied RDF file.
  This is a minor limitation since you can always supply the relevant file first.
- [`vocab_prefix, vocab_iri`](#vocab_prefix-vocab_iri) describes how the tool seeks to find a default `vocab_prefix`.
  It's usually convenient to have one for better GraphQL names, but
  if you have many ontologies and none of them is "dominant"
  you may not care for a `vocab_prefix`.
  - Eg in the case of FIBO the first encountered ontology
  (https://spec.edmcouncil.org/fibo/ontology/FND/Arrangements/Communications/) 
  is treated specially: the `fibo-fnd-arr-com:` is treated as `vocab_prefix` 
  and is stripped from GraphQL names.
  - It would be better to run without `vocab_prefix` and afford it no such special treatment.
  - The platform has default values (see [Special Prefixes](http://platform.ontotext.com/soml/preamble.html#special-prefixes)) as shown below, so they are optional in SOML.
    We could add a special value `--voc NONE` to disable `vocab_prefix` processing.

```
specialPrefixes:
  base_iri:     http://example.org/resource/
  vocab_iri:    http://example.org/vocabulary/
  vocab_prefix: voc
```

### Handle Property Inheritance

Some ontologies (e.g. SKOS) expect that 
a subProperty inherits its domain and range from its transitive ancestors 
(e.g. none of the 10 subprops of `skos:semanticRelation` define their own domain and range,
but expect to inherit it). 
- Such inheritance is defined in OWL2, see [Web Ontology Language Profiles](https://www.w3.org/TR/owl2-profiles), 
  Table 9 The Semantics of Schema Vocabulary, rules [scm-dom2](https://www.w3.org/TR/owl2-profiles/#scm-dom2), [scm-rng2](https://www.w3.org/TR/owl2-profiles/#scm-rng2)
- Such inheritance is **not** defined in RDFS, see [RDF 1.1 Semantics](https://www.w3.org/TR/rdf11-mt), [Entailment](https://www.w3.org/TR/rdf11-mt/#rdfs-entailment)
- The platform does not yet support property domain/range inheritance (PLATFORM-1500)

One ontology that uses property inheritance is SKOS.
All descendant props of `skos:semanticRelation` (including `skos:broader, narrower, broaderMatch, narrowerMatch, related` etc)
do not define their own domain & range.
As a workaround, the file `skos-fix.ttl` adds domain & range to these props.

### Handle OWL Restrictions

The tool should perhaps handle the following [Domain and Range](#domain-and-range) constructs:

```ttl
:classX rdfs:subClassOf [a owl:Restriction; owl:onProperty :propP; owl:allValuesFrom  :classY]
:classX rdfs:subClassOf [a owl:Restriction; owl:onProperty :propP; owl:someValuesFrom :classY]
```

In both cases should emit the following (`props` definitions are local so this won't cause range conflict between classes):

```yaml
objects:
  classX: {props: {propP: {range: classY}}}
```

- Also handle variants with `owl:equivalentClass` instead of `rdfs:subClassOf`
- Also handle variants with `owl:intersectionOf`, they are common in LifeSci ontologies.
  Eg see this variant from [Populous_tutorial_SWAT4LS_2011.zip::Output_ontology/cell_types.owl](https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/owlpopulous/Populous_tutorial_SWAT4LS_2011.zip)
  (note: two of the intersections are superfluous since they have a single member).

```ttl
ont:CTODEV18198000  a        owl:Class ;
        rdfs:label           "macula densa epithelial cell"@en ;
        rdfs:subClassOf      ont:CTODEV70164000 , ont:CTODEV54509000 ;
        rdfs:subClassOf      [ a                   owl:Class ;
                               owl:intersectionOf  ( [ a                   owl:Restriction ;
                                                       owl:onProperty      properties_populous_tutorial_SWAT4LS2011:participates_in ;
                                                       owl:someValuesFrom  GO:GO_0003093
                                                     ]
                                                     [ a                   owl:Restriction ;
                                                       owl:onProperty      properties_populous_tutorial_SWAT4LS2011:participates_in ;
                                                       owl:someValuesFrom  GO:GO_0003098
                                                     ]
                                                   )
                             ] ;
        rdfs:subClassOf      [ a                   owl:Class ;
                               owl:intersectionOf  ( [ a                   owl:Restriction ;
                                                       owl:onProperty      properties_populous_tutorial_SWAT4LS2011:has_phenotypic_quality ;
                                                       owl:someValuesFrom  PATO:PATO_0001407
                                                     ]
                                                   )
                             ] ;
        owl:equivalentClass  [ a                   owl:Class ;
                               owl:intersectionOf  ( obo:CL_0000000
                                                     [ a                   owl:Class ;
                                                       owl:intersectionOf  ( [ a                   owl:Restriction ;
                                                                               owl:onProperty      OBO_REL:part_of ;
                                                                               owl:someValuesFrom  obo:UBERON_0002335
                                                                             ]
                                                                           )
                                                     ]
                                                   )
                             ] .
```

Should become:

```yaml
objects:
  ont:CTODEV18198000:
    label: "macula densa epithelial cell"
    inherits: [ont:CTODEV70164000, ont:CTODEV54509000, obo:CL_0000000]
    props:
      properties_populous_tutorial_SWAT4LS2011:participates_in: {range: [GO:GO_0003093, GO:GO_0003098]}
      properties_populous_tutorial_SWAT4LS2011:has_phenotypic_quality: {range: PATO:PATO_0001407}
      OBO_REL:part_of: {range: obo:UBERON_0002335}
```

Notes:
- PLATFORM-1625 to allow punctuation in local names
- `participates_in: {range: [GO:GO_0003093, GO:GO_0003098]}` is not quite correct 
  since it means the object of `participates_in` can be from either of these classes, 
  whereas the Turtle means the object should be from both of these classes.
  - But it's the best we can do, without introducing anynymous (or auto-generated) intersection classes:
    `gen:GO_GO_0003093__AND__GO_GO_0003098: {inherits: [GO:GO_0003093, GO:GO_0003098]}`

Also map `:X owl:equivalentClass [owl:intersectionOf (:Y...)]` to `X inherits: Y` (see `obo:CL_0000000` above)

- TODO: check FIBO for some more variants.

### Handle OWL Cardinalities

- Handle OWL cardinality and qualified cardinality restrictions to map to `min: max:`
- `owl:someValuesFrom` is logically equivalent to `min: 1`. It is widely used in FIBO because it's less computationally expensive for reasoners
  (see [FIBO Ontology Guidelines T15. Use of "min 1" cardinality restrictions](https://github.com/edmcouncil/fibo/blob/master/ONTOLOGY_GUIDE.md#t15--use-of-min-1-cardinality-restrictions))

## Gaps in Ontologies

- A major shortcoming of most ontologies is that fery few props are declared `owl:FunctionalProperty`, so most of them get cardinality `max: inf` in SOML.
  Such multi-valued props are considerably more expensive to query, and if used in a filter have an implicit `EXISTS` semantics.
- Some ontologies leave some props without domain (unbound), so they can be reused in  more situations.
  - One example are all SKOS label and note props: SKOS says they are universally applicable.
    But unless we bind them to `skos:Concept`, they won't show up in any class.
    So we wrote a `skos-fix.ttl` that does that.
    (See [Handle Property Inheritance](#handle-property-inheritance) for other fixes in the same file.)
  - Another example are DC and DCT properties, 
    most of which are very generic (defined on `rdfs:Resource`, which is mapped to `range: iri`).
    For specific applications, we recommend writing an RDF "fix" file to bind them to specific classes.
  - A particular example is this generated piece where 
    `isFormatOf/hasFormat` are not attached yet are declared inverses.
    SOML currently wants to check that they are defined on a pair of classes
    and to check domain/range conformance, so that is invalid SOML (issue PLATFORM-1509):

```yaml
  isFormatOf:
    descr: 'A related resource that is substantially the same as the described resource, but in another format'
    inverseOf: hasFormat
    kind: object
    label: Is Format Of
    max: inf
    range: iri
```

## Dependencies

The tool depends on the following requirements:

- Perl 5.14 or later (but not Perl 6)
- Specific modules: `Attean URI::NamespaceMap List::MoreUtils Array::Utils YAML`
  - If you want to read JSONLD: `AtteanX::Parser::JSONLD`
- Generally installed modules: `warnings strict Carp::Always Getopt::Long` (don't need to install these)

You can install all required modules with `cpan` (or `cpanm` on straberry-perl).
In some cases, using `-f` to force-install even if some test fails, can help, e.g.:

```sh
cpan -fi Attean URI::NamespaceMap List::MoreUtils Array::Utils YAML
cpanm -f Attean URI::NamespaceMap List::MoreUtils Array::Utils YAML
```

- TODO: Do any of the modules use `XS` and thus require a working C toolchain?

The tool has been tested on:
- Windows 10.0.17134.112 (MSWin32-x64-multi-thread) with strawberry-perl 5.28.0.1 and `cpanm`
- Linux: TODO specify

We are also working on a Dockerfile.

### Dependency Problems

Some problems in the dependencies:
- schema.org is the largest ontology tested so far.
  `schema.ttl` is 508k ttl, 9k triples, results in 428k yaml, 
  and takes 4 minutes to process: posted [attean#154](https://github.com/kasei/attean/issues/154)
- `schema.rdf` causes error `Read more bytes than requested` in `XML::LibXML`
  (other RDF ontologies don't cause this error): 
  posted [rt.cpan.org#131982](https://rt.cpan.org/Ticket/Display.html?id=131982), see [eg/LibXML-schema.rdf.err](eg/LibXML-schema.rdf.err).
  - To upgrade `XML::LibXML` to the latest version 2.0202, 
    ensure you don't have the `PERL_UNICODE` env var set
    or you'll get error `Installing Alien::Build::MM failed`, 
    posted [Alien-Build#173](https://github.com/Perl5-Alien/Alien-Build/issues/173), see [eg/Alien-Build-MM_build.log](eg/Alien-Build-MM_build.log)..
    But even this latest version still has the above problem.
- Installing `AtteanX::Parser::JSONLD` causes warning 
  `Subroutine spacepad redefined at Debug/ShowStuff.pm` on every execution of the script.
  The warning is harmless but annoying and I don't know how to quash it 
  (`no warnings 'redefine'` doesn't help).
  So don't install this module unless you need to read JSONLD.
  See [attean#153](https://github.com/kasei/attean/issues/153) and [rt.cpan.org#131983](https://rt.cpan.org/Ticket/Display.html?id=131983). Example:

```sh
perl ../owl2soml.pl -voc schema schema.jsonld > schema2.yaml
Subroutine spacepad redefined at C:/Strawberry/perl/site/lib/Debug/ShowStuff.pm line 1635.
        require Debug/ShowStuff.pm called at C:/Strawberry/perl/site/lib/JSONLD.pm line 57
        JSONLD::BEGIN() called at C:/Strawberry/perl/site/lib/Debug/ShowStuff.pm line 1635
        ...
```


## Change Log

5-Apr-2020
- Add datatypes `xsd:dateTimeStamp` (mapped to `dateTime`), `fibo-fnd-dt-fd:CombinedDateTime` (mapped to `dateOrYearOrMonth`), `owl:rational` (mapped to `xsd:decimal` even though that's a lie)
- Add `eg/Makefile` to make the various examples; capture stderr warnings in `.log`

3-Apr-2020
- `make_superClass()`: fix to return both values when cached: `Use of uninitialized value $super2 in concatenation (.) or string at owl2soml.pl line 420.`
- `schema:URL, rdfs:Resource, xsd:anyURI` are mapped to `iri`, i.e. a "free-standing" IRI pointing to an external resource (before only the first one was)
- `get_descr()`: Sort multiple descriptions before concatenating, so the output is deterministic

15-Мар-2020:
- Emit `owl:inverseOf` in both directions

13-Mar-2020:
- Recognize extra prop types: `owl:FunctionalProperty owl:InverseFunctionalProperty owl:ReflexiveProperty owl:IrreflexiveProperty owl:SymmetricProperty owl:AsymmetricProperty owl:TransitiveProperty`
- Ignore `owl:topObjectProperty owl:bottomObjectProperty owl:topDataProperty owl:bottomDataProperty`

12-Mar-2020:
- Ignore `owl:Thing owl:Nothing` as classe, in particular in `rdfs:subClassOf`
- Use `*Interface` instead of `*Common` for abstract super-classes
- fix_superClasses: Migrate props from concrete subclass to its corresponding abstract superclass
- Handle `vann:preferredNamespacePrefix`
- Unicode: `Wide character in print at owl2soml.pl line 445`: fixed by `use open ':std', ':encoding(utf8)'`

27-Feb-2020:
- initial version

# Platform Service

TODO 

We have plans to rewrite the tool to Java and as a platform service.
We also need to design how it is invoked and how input/output/errors are handled.
The best is to use the same soaas REST APIs, just with different content-type (application/rdf+xml, text/turtle, application/ld+json)
Need to decide whether the posted ontologies are saved, or only the generated SOML
It often needs to take several ontologies as input
Often needs some extra options:
For now just "-voc", but we could also add:
bind props to classes. Eg the majority of DCT props are not attached, and the core SKOS props are not attached (except semanticRelations). [^skos-fix.ttl] is an RDF fix for this SKOS problem, is that how we'd like to proceed?
"name" characteristic of classes
declaring inverseAliases?
tighten up properties cardinality to single-valued i.e. max=1 (very few ontologies use owl:FunctionalProperty)
tighten up incoming prop cardinality, i.e. cardinality of inverseAlais (very few ontologies use owl:InverseFunctionalProperty)
How would that be passed on?

I definitely think there needs to be a command-line version of owl2soml. It's a utility, so it should be easily invocable as a utility.
 it will need to be re-engineered using JAVA (as part of SOaaS) and made available at existing /soml endpoints:
We can build a CLI (or/and a GUI) that uses /soml Content-Type: text/turtle

should be able to pass a few params (eg voc prefix)
should also be available as command line tool
should test on ontologies collected in owl2soml/eg and more:
Skos, dct, schema, gvp; parts of FIBO...
