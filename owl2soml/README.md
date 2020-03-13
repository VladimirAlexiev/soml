# owl2soml

Generate SOML schema from RDFS/OWL/Schema ontologies

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [owl2soml](#owl2soml)
- [Usage](#usage)
    - [Features](#features)
        - [Ontologies](#ontologies)
        - [`vocab_prefix, vocab_iri`](#vocabprefix-vocabiri)
        - [Classes](#classes)
        - [Properties](#properties)
        - [Datatypes](#datatypes)
        - [Labels and Descriptions](#labels-and-descriptions)
    - [Limitations](#limitations)
    - [Gaps in Ontologies](#gaps-in-ontologies)
    - [Dependencies](#dependencies)
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
Currently the platform doesn't support multiple inheritance, so only the first superclass is used.

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
- It doesn't recognize props that merely participate in prop relations such as `rdfs:domain rdfs:range`: 
  each prop must have one of the above types.
- It ignores the following, which are not useful for querying: `owl:topObjectProperty owl:bottomObjectProperty owl:topDataProperty owl:bottomDataProperty`

Properties are processed as follows:
- The chars `[-_.]` are removed from class & property local names in order to make valid GraphQL names.
- Gets prop [Labels and Descriptions](#labels-and-descriptions)
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

- Treats 

- prop relations (; but );
- prop domains (rdfs:domain, schema:domainIncludes, owl:unionOf). Multiple domains are allowed.
- prop ranges (rdfs:range, schema:rangeIncludes, owl:unionOf). Object or datatype ranges are allowed.


### Datatypes

The tool handles the following datatypes:
- XSD datatypes: `boolean, byte, date, dateTime, decimal, double, gYear, gYearMonth, int, integer, long, negativeInteger, nonNegativeInteger, nonPositiveInteger, positiveInteger, short, string, time, unsignedByte, unsignedInt, unsignedLong, unsignedShort`
- schema.org datatypes: `Boolean, Date, DateTime, Float, Integer, Number, Text, Time`
- `schema:URL` is mapped to `iri`, i.e. a free IRI that does not designate an instance (object) stored in the platform.
- the default datatype is `string`. These are also mapped to string: `rdf:langString, rdfs:Literal`

### Labels and Descriptions

The tool handles the following descriptive attributes of schema elements (Ontology, Classes and Properties):
- labels (rdfs:label, skos:prefLabel, dc:title, dct:title)
- descriptions (rdfs:comment, skos:definition, skos:description, skos:scopeNote, dc:description, dct:description)

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

TODO: strip HTML tags, which are used e.g. in schema.org rdfs:comments:

```ttl
schema:AcceptAction a rdfs:Class ;
    rdfs:comment """The act of committing to/adopting an object.<br/><br/>

Related actions:<br/><br/>

<ul>
<li><a class="localLink" href="http://schema.org/RejectAction">RejectAction</a>: The antonym of AcceptAction.</li>
</ul>
""" ;
```

## Limitations

In addition to TODOs sprinkled above, `owl2soml` (or the Ontotext Platform) 
has other limitations (thus ideas for improvement) that are described below.
If one of these limitations is especially important for you, please send feedback.
In some cases we've referenced the issue number in our internal issue tracker.

- Takes metadata only from the first ("root") owl:Ontology
- Uses only labels/descriptions in "en" (including en-US, en-GB, etc) or without language tag
- owl:AnnotationProperty and owl:DatatypeProperty are treated the same
- Doesn't support multiple inheritance (only the first superclass is used). Enquire about the status of issue PLATFORM-360
- Doesn't support multiple prop ranges (the first one is used). Enquire about the status of issue PLATFORM-1493
- Doesn't handle owl:import. Instead, provide multiple ontologies on input
- rdf:langString and rdfs:Literal are mapped to xsd:string
- Some ontologies (eg SKOS) expect that a subProperty inherits domain & range from its ancestors transitively (e.g. all 10 subprops of skos:semanticRelation do not define their own domain & range but inherit it). Such inheritance is defined in OWL 2 Web Ontology Language Profiles, Table 9 The Semantics of Schema Vocabulary (rules https://www.w3.org/TR/owl2-profiles/#scm-dom2, https://www.w3.org/TR/owl2-profiles/#scm-rng2); though not by RDFS semantics (https://www.w3.org/TR/rdf11-mt/#rdfs-entailment). Enquire about the status of issue PLATFORM-1500
- [`vocab_prefix, vocab_iri`](#vocabprefix-vocabiri) describes how the tool seeks to find a default `vocab_prefix`.
  It's usually convenient to have one for better GraphQL names, but
  if you have many ontologies and none of them is "dominant", you may not care for a `vocab_prefix`.
  The platform has default values (see [Special Prefixes](http://platform.ontotext.com/soml/preamble.html#special-prefixes)) as shown below, so they are optional in SOML.
  We could add a special value `--voc NONE` to disable `vocab_prefix` processing.

```
specialPrefixes:
  base_iri:     http://example.org/resource/
  vocab_iri:    http://example.org/vocabulary/
  vocab_prefix: voc
```

- The platform should process more prop characteristics: ` owl:InverseFunctionalProperty owl:ReflexiveProperty owl:IrreflexiveProperty owl:AsymmetricProperty owl:TransitiveProperty`.
Currently it only handles `owl:FunctionalProperty owl:SymmetricProperty` (and `inverseOf`)

NOT rdfs:subPropertyOf

## Gaps in Ontologies

## Dependencies


## Change Log


13-Mar-2020:
- Recognize extra prop types: `owl:FunctionalProperty owl:InverseFunctionalProperty owl:ReflexiveProperty owl:IrreflexiveProperty owl:SymmetricProperty owl:AsymmetricProperty owl:TransitiveProperty`
- Ignore `owl:topObjectProperty owl:bottomObjectProperty owl:topDataProperty owl:bottomDataProperty`

12-Mar-2020:
- Ignore `owl:Thing owl:Nothing` as classe, in particular in `rdfs:subClassOf`
- Use `*Interface` instead of `*Common` for abstract super-classes
- fix_superClasses: Migrate props from concrete subclass to its corresponding abstract superclass
- Handle `vann:preferredNamespacePrefix`
- Unicode: `Wide character in print at owl2soml.pl line 445`: fixed by `use open ':std', ':encoding(utf8)'`

27-Feb-2020: initial version

# Platform Service

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
Jem Rayfield how would that be passed on?

I definitely think there needs to be a command-line version of owl2soml. It's a utility, so it should be easily invocable as a utility.
 it will need to be re-engineered using JAVA (as part of SOaaS) and made available at existing /soml endpoints:
We can build a CLI (or/and a GUI) that uses /soml Content-Type: text/turtle

