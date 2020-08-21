# owl2soml

Generate SOML schema from RDFS/OWL/Schema ontologies

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [owl2soml](#owl2soml)
    - [Usage](#usage)
    - [Features](#features)
        - [Ontologies](#ontologies)
        - [`vocab_prefix, vocab_iri`](#vocab_prefix-vocab_iri)
        - [No `vocab_prefix`](#no-vocab_prefix)
        - [Classes](#classes)
            - [subClassOf](#subclassof)
            - [Superclass Interfaces](#superclass-interfaces)
            - [Name Characteristic](#name-characteristic)
        - [Properties](#properties)
            - [Domain and Range](#domain-and-range)
            - [Real Inverses](#real-inverses)
            - [TODO Virtual Inverses](#todo-virtual-inverses)
        - [Datatypes](#datatypes)
            - [String Handling](#string-handling)
            - [Lang Specs](#lang-specs)
        - [Labels and Descriptions](#labels-and-descriptions)
    - [Implemented as Platform Service](#implemented-as-platform-service)
        - [Handle OWL Restrictions](#handle-owl-restrictions)
        - [Handle OWL Cardinalities](#handle-owl-cardinalities)
    - [Limitations](#limitations)
        - [Better Handling of Multiple Ontologies](#better-handling-of-multiple-ontologies)
        - [Handle Property Inheritance](#handle-property-inheritance)
        - [Unusual Datatypes](#unusual-datatypes)
        - [owl:rational](#owl-rational)
        - [GeoSPARQL Serializations](#geosparql-serializations)
        - [PlainLiteral, XMLLiteral, HTMLLiteral](#plainliteral-xmlliteral-htmlliteral)
    - [Gaps in Ontologies](#gaps-in-ontologies)
        - [Missing Cardinality Information](#missing-cardinality-information)
        - [Unbound Props](#unbound-props)
    - [Tool Dependencies](#tool-dependencies)
        - [Dependency Problems](#dependency-problems)
    - [Change Log](#change-log)

<!-- markdown-toc end -->

## Usage

```
owl2soml.pl [options] ontology.(ttl|rdf) ... > ontology.yaml
Options:
  -voc    pfx    Use "pfx" as vocab_prefix (and default SOML ID).
  -voc    NONE   Don't look for vocab_prefix in the first ontology using various heuristics.
  -id     id     Set SOML ID
  -label  label  Set SOML label
  -super  0|1    Generate X and XInterface for every superclass X (default 0: Platform 3.3 does this internally)
  -name   p1,p2  Designate these props as class "name" characteristics (eg rdfs:label,skos:prefLabel)
  -string 0      Emit rdf:langString as langString; rdfs:Literal & schema:Text & undefined datatype as stringOrLangString; xsd:string as string
          1      Emit rdf:langString & rdfs:Literal & schema:Text & undefined datatype as langString; xsd:string as string
          2      Emit rdf:langString & rdfs:Literal & schema:Text & undefined datatype & xsd:string as string
  -lang   str    Set schema-level lang spec. Doesn't make sense if "-string 2" is specified
Options that are not yet implemented:
  -multi  0|1    Handle multiple parent classes (default 0: use the first one and warn; Platform doesn't yet do this)
  -union  0|1    Handle union (multiple) ranges (default 0: use the first one and warn; Platform doesn't yet do this)
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

We have rewritten the tool in Java, see [Implemented as Platform Service](#implemented-as-platform-service).

## Features

`owl2soml` can read ontologies in these RDF formats: RDF/XML, Turtle, JSONLD.
It requires appropriate prefixes to be defined, so it can obtain GraphQL (developer-friendly) class and prop names.
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
- `dct:created, dct:modified`. If a `dateTime` stamp is provided, only the date part is used.
- `dc:creator, dct:creator`. It handles literal or IRI and concatenates if it finds multiple values.
- `owl:versionInfo`
- `swc:BaseUrl` of `owl:Ontology` is used to set `base_iri`.
  This is currently not used to shorten IRIs in GraphQL queries and responses, but may be in the future.
  
### `vocab_prefix, vocab_iri`

`vocab_prefix` is the default prefix of a SOML schema, and `vocab_iri` is the corresponding namespace.
It's convenient to have one to shorten GraphQL names:
- RDF elements (classes and props) in the `vocab_iri` namespace get nice names like `Class` and `prop`
- RDF elements in other namespaces get longer names like `pfx_Class` and `pfx_prop`

`vocab_prefix` and `vocab_iri` are searched in the following order:

1. If the option `-voc` is provided, it sets `vocab_prefix`.
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

`vocab_prefix` is also used in the SOML id, 
which is used for SOML operations (create, update, delete, bind) [by the SOaaS services](http://platform.ontotext.com/semantic-objects/semantic-objects.html#define-star-wars-semantic-objects):

```yaml
id: /soml/$vocab_prefix
```

### No `vocab_prefix`

If you have many ontologies and prefixes and none of them is "dominant", 
you may not care for the `vocab_prefix` shortening described above.

Eg FIBO consists of about 226 ontologies; the [eg/fibo-FND.ttl](eg/fibo-FND.ttl) subset consists of 55 ontologies.
We don't want the first encountered ontology and its prefix to be treated specially, because they are not special in any way.

Please note that the platform has default values (see [Special Prefixes](http://platform.ontotext.com/soml/preamble.html#special-prefixes)) as shown below,
in order to make it easier to write small examples.
This `vocab_iri` is not likely to appear in real ontologies, so it won't hurt.

```
specialPrefixes:
  base_iri:     http://example.org/resource/
  vocab_iri:    http://example.org/vocabulary/
  vocab_prefix: voc
```

To disable the looking for `vocab_prefix`, specify `-voc NONE`.
Then use the `-id` and `-label` options to set SOML id and label, eg:

```sh
perl owl2soml.pl -voc NONE -id fibo-FND -label "FIBO Foundational" fibo-FND.ttl
```

will result in 

```yaml
id: /soml/fibo-FND
label: "FIBO Foundational"
```

### Classes

The tool recognizes instances of `rdfs:Class` and/or `owl:Class` as classes:
- If one instance has both types, it's processed only once
- Anonymous (blank node) classes are ignored
- It ignores instances of `schema:DataType` and that class itself (see [Datatypes](#datatypes) below)
- Also ignores classes `owl:Thing, owl:Nothing` that are not useful for querying.
  (In contrast, it keeps `schema:Thing` which is the domain/range of useful props).

Classes are processed as follows:
- Gets class [Labels and Descriptions](#labels-and-descriptions)
- If a property range is not defined in the ontology, it is emitted in SOML as a class without any props,
  otherwise the SOML schema would be invalid
- Class inheritance is processed as described in the next section

#### subClassOf

`rdfs:subClassOf` is emitted in SOML as `inherits`.
- Anonymous (blank node) classes are ignored
- Currently the platform doesn't support multiple inheritance, so only the first superclass is used
  (option `-multi` will change that)

#### Superclass Interfaces

GraphQL represents superclasses as interfaces, and interfaces cannot have instances.
Also, it does not allow an interface and class (type) to have the same name as there would be a name conflict.

Issue PLATFORM-1344 will implement Concrete Superclasses by generating 
the dual superclass and corresponding interface automatically behind the scenes.

Until this is done, use option `-super 1` to generate dual entities:
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

Option `-super 1` will generate the following SOML schema:

```yaml
objects:
  CollectionInterface:
    kind: abstract
    props:
      member: {}
  Collection:
    inherits: CollectionInterface
    type: skos:Collection
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
  
With this schema you can have instances of `Collection` and `OrderedCollection`
and can make GraphQL queries referencing `collection` and `orderedCollection`.

However, the generated GraphQL schema also has queries referencing `collectionInterface`,
which is confusing 
and if used, would require breaking changes to your queries if the class hierarchy changes.
We consider queries like `collectionInterface` to be parasitic and bad practice,
so it's better to not use this option.

By the way, this example shows two more aspects:
- Since `rdf:List` is referenced as a range but is not defined in SKOS, 
  it is declared as a class with no props.
- Only the first range of `skos:member` is used (see [Limitations](#limitations))

#### Name Characteristic

The Ontotext Platform has a feature that allows you to use a uniform GraphQL field (`name`) to access object names, regardless of the specific property used for storing the name.
The `-name` option allows you to specify a list of properties to be treated in this special way.
You can either use a comma-separated list, or use the option several times, eg:
- `-name rdfs:label,skos:prefLabel`
- `-name rdfs:label -name skos:prefLabel`

If a class has one of these props, the prop is declared as its `name` characteristic.
You cannot specify this treatment per-class.
So a class should not have several of these props (should not be the domain of several of these props).

The tool does some special processing related to the cardinality of these props:
- (The Platform has a default behavior where a name prop, if not declared in the class, is assumed to be a mandatory single-valued string.)
- The prop is forced to be mandatory in the class (`min: 1`)
- If the prop is mapped to `string` then it's also forced to single-valued in the class (`max: 1`)
- (Platform version 3.3 also allows a multi-valued `langString` to be used as `name` because a single value can be fetched using the lang fallback mechanism)

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

Property IRIs:
- SOML now allows punctuation (`_-.`) in prefixes or local names (issue PLATFORM-1625).
  So a prop like `fibo-fnd-acc-aeq:Equity` is not mangled to `fibofndaccaeq:Equity` anymore.
  Such prefixes are prevalent in FIBO. 
  Other ontologies (especially related to biology and life sciences) use punctuation (even `:`) in local names.

Properties are processed as follows:
- Gets prop [Labels and Descriptions](#labels-and-descriptions)
- Assigns `kind: literal` or `kind: object` depending on property type and range: 
  see [Datatypes](#datatypes) for details
- Processes the following prop characteristics:
  - `owl:FunctionalProperty` is mapped to `max: 1`. 
    Unfortunately too few ontologies use this characteristic, 
    so most properties end up with the cardinality `max: inf`, 
    which is significantly more expensive to query.
  - `owl:SymmetricProperty` is mapped to `symmetric: true`

#### Domain and Range

The tool processes the following:
- domains (`rdfs:domain, schema:domainIncludes`). Multiple domains are allowed (which must be classes).
- ranges (`rdfs:range, schema:rangeIncludes`). Only the first encountered range is used. Class or datatype ranges are allowed.

The tool also handles `owl:unionOf` constructs, eg (`a owl:Class` is not necessary):

```ttl
:propP   rdfs:domain         [a owl:Class; owl:unionOf (:classX :classY :classZ)].
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

#### Real Inverses

`X owl:inverseOf Y` and `X schema:inverseOf Y` are mapped to two SOML assertions:
  
```yaml
properties:
  X: {inverseOf: Y}
  Y: {inverseOf: X}
```

- You must therefore have `Y` defined as a prop in the same ontology(ies)
- You must not have more than 2 props be inverses of each other.

Bidirectional navigation is essential in a Knowledge Graph, whereas GraphQL does not natively provide it.
Considerations:
- Most OWL ontologies have few `owl:inverseOf` props.
  - Eg FIBO 2020-03 has 1465 object props but only 99 inverses (see [fibo#983](https://github.com/edmcouncil/fibo/issues/983) item 15); FIBO-FND has 535 object props but only 80 inverses.
  - One exception is CIDOC-CRM that has a full complement of inverses (but ironically, uses RDFS so does not declare them)
- Inverses are superfluous in RDF because you can always query in the opposite direction.
  - The [PROV ontology deprecates inverses]( http://w3.org/TR/prov-o/#inverse-names): "When all inverses are defined for all properties, modelers may choose from two logically equivalent properties when making each assertion. Although the two options may be logically equivalent, developers consuming the assertions may need to exert extra effort to handle both (e.g., by either adding an OWL reasoner or writing code and queries to handle both cases). This extra effort can be reduced by preferring one inverse over another".
  - PROV defines `prov:inverse`, which declares what (string) name should be used for an inverse property,
    without triggering inverse inference (unlike `owl:inverseOf`)

#### TODO Virtual Inverses
The Ontotext Platform provides [inverseAlias](http://platform.ontotext.com/soml/properties.html#inverses) to create virtual inverses and enable bidirectional navigation in GraphQL.
You don't need to have inverse reasoning or inverses stored in the RDF reposotory to use this feature.

We consider using the following RDF props to specify inverse aliases.
- `prov:inverse` (string) specifies the name of a virtual inverse, resolved against `vocab_prefix`. 
  It doesn't allow changing the namespace of the inverse, nor defining the cardinality of that inverse.
- `so:inverseAliasOf` (property) that specifies a virtual inverse prop, with optional characteristics including cardinality.
Please note that unlike `owl:inverseOf` neither of these are symmetric.

For example, consider the following ontology that describes multivalued relations from City & Company to Person.

```ttl
voc:City    a rdfs:Class.
voc:Company a rdfs:Class.
voc:Person  a rdfs:Class.
voc:resident a owl:ObjectProperty;     rdfs:domain voc:City;    rdfs:range voc:Person; prov:inverse "livesIn".
voc:employee a owl:ObjectProperty;     rdfs:domain voc:Company; rdfs:range voc:Person.
voc:worksFor a owl:FunctionalProperty; rdfs:domain voc:Person;  rdfs:range voc:Company; so:inverseAliasOf voc:employee.
voc:Person rdfs:subClassOf [
  a owl:Restriction;
  owl:onProperty voc:worksFor;
  owl:onClass voc:Company;
  owl:minQualifiedCardinality "1"^^xsd:nonNegativeInteger ;
].
```

It creates two virtual inverses:
- `livesIn`, but cannot specify the cardinality of this prop (so by default it becomes multivalued)
- `worksFor`, and also states the cardinality:
  - mandatory (min: 1): `owl:minQualifiedCardinality`
  - single-valued (max: 1): `owl:FunctionalProperty` (both could be handled with `owl:qualifiedCardinality`)
You see that `so:inverseAliasOf` gives you more control than `prov:inverse` 

It generates the following SOML schema. 

```yaml
objects:
  City: 
    props: 
      resident: {range: Person, max: inf}
  Company: 
    props: 
      employee: {range: Person, max: inf}
  Person:
    props: 
      livesIn:  {range: City,    inverseAlias: resident, max: inf}
      worksFor: {range: Company, inverseAlias: employee, min: 1, max: 1}
```

### Datatypes

The tool handles the following datatypes:
- `xsd:` datatypes: `boolean, byte, date, dateTime, decimal, double, gYear, gYearMonth, int, integer, long, negativeInteger, nonNegativeInteger, nonPositiveInteger, positiveInteger, short, time, unsignedByte, unsignedInt, unsignedLong, unsignedShort`
  - `xsd:dateTimeStamp` is mapped to `dateTime` which is not precise because the former requires timezone
- `schema:` (schema.org) datatypes: `Boolean, Date, DateTime, Integer, Text, Time`
  - `schema:Float` is mapped to `double` because GraphQL `Float` is also in fact a double number
  - `schema:Number` is mapped to `decimal` which is not precise because it could be integer or decimal
- You cannot use `owl:DatatypeProperty` or `owl:AnnotationProperty` with a class range.
  - The default datatype of a prop that doesn't mention a range is controlled by the `-string` option, see next
  - Other datatypes not supported by the platform are ignored with a warning.
- `schema:URL, rdfs:Resource, xsd:anyURI` are mapped to `iri`, i.e. a "free-standing" IRI pointing to an external resource (not an instance stored in the platform).
- You cannot use `owl:ObjectProperty` with a datatype range.
  - An `owl:ObjectProperty` without specified class range is mapped to `iri` (a "free-standing" IRI)
  - If a class is used as property range but not declared in the ontology, it's declared in SOML (without any props)

#### String Handling

Ontotext Platform version 3.3 introduces comprehensive support for strings with lang tag (`langString`):
you can validate lang tags on mutation, find objects with or without labels in certain langs, fetch only certain langs with fallback, etc.
Before this version, lang strings were mapped to plain `string`.

The `-string` option (possible values `0,1,2`) controls how to emit string-related datatypes:

| Datatype                             | 0 (default)        | 1          | 2      |
|--------------------------------------|--------------------|------------|--------|
| rdf:langString                       | langString         | langString | string |
| rdfs:Literal, schema:Text, undefined | stringOrLangString | langString | string |
| xsd:string                           | string             | string     | string |

Notes:
- "undefined" refers to datatype props (`rdf:Property, owl:DatatypeProperty, owl:AnnotationProperty`) with no defined range
- `langString` is treated as a GraphQL class `Literal` with fields `value, lang` (both are strings)
- `stringOrLangString` refers to a union datatype that allows strings with or without lang tag but is otherwise treated as `langString`.
  In particular, to get the value in GraphQL you need to use a query part like `field{value}`

#### Lang Specs

TODO: fix the links to point to documentation rather than branch PLATFORM-1241.

If your schema uses `langString` (and you haven't specified `-string 2` as per the previous section)
then you may want to provide a schema-level lang spec to control how lang strings are handled:
- [fetch](https://gitlab.ontotext.com/platform/platform/blob/PLATFORM-1241-langString/soaas/architecture/includes/literal.md#lang-specs-for-fetching) controls which lang variants to fetch, and a priority/fallback order
- [validate](https://gitlab.ontotext.com/platform/platform/blob/PLATFORM-1241-langString/soaas/architecture/includes/literal.md#lang-specs-for-validation) controls which langs are allowed in mutations, and `UNIQ` of values per lang
- [implicit](https://gitlab.ontotext.com/platform/platform/blob/PLATFORM-1241-langString/soaas/architecture/includes/literal.md#implicit-lang) specifies an implicit lang for `langStrings` in mutations that don't provide a lang

Some examples of [combining lang specs](https://gitlab.ontotext.com/platform/platform/blob/PLATFORM-1241-langString/soaas/architecture/includes/literal.md#combining-lang-specs):

| `-lang`                            | effect                                                                                   |
|------------------------------------|------------------------------------------------------------------------------------------|
| `ALL`                               | fetch all langs                                                                          |
| `ALL,-en-US`                        | fetch all langs except American English                                                  |
| `BROWSER`                           | fetch one lang according to browser's `Accept-Language` heading                          |
| `fetch: en`                         | fetch only English                                                                       |
| `fetch: en~`                        | fetch English or any English dialect                                                     |
| `fetch: -en-US, implicit: en`       | fetch any except American English, use implicit English lang tag                         |
| `fetch: fr,en, validate: en,fr;UNIQ` | fetch French or English (first one), allow only English or French, unique value per lang |

You should use either a string with no spaces (which sets `fetch`),
`key1: val1, key2: val2, ...` where 
the keys are `fetch, validate, implicit`
and the values include no spaces.

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
- If newlines are used in a description, use `".\n"` as delimiter when concatenting, rather than `". "`
- Ignore empty labels/descriptions, which are found in some ontologies

## Implemented as Platform Service

Starting in version 3.1, the platform incorporates an experimental [owl2soml service](http://platform.ontotext.com/soml/owl2soml.html) implemented in Java.
- It allows you to generate and save a schema using the usual `/soml` platform REST endpoint (see [Quickstart: Define Star Wars Semantic Objects](http://platform.ontotext.com/semantic-objects/semantic-objects.html#define-star-wars-semantic-objects))
- Use `Content-Type: multipart/form-data` to pass several ontologies (and some optional parameters) to the REST endpoint.
- There is a way to check validity (`dryrun`) and to get the generated SOML schema.
- There is also a command-line version `owl2soml.jar` that can be provided upon request and has the following options
  in addition to the Perl version (see [Usage](#usage) above)

```
usage: java -jar owl2soml.jar
 -i <arg>     input files
 -o <arg>     output file
 -v <arg>     validate the generated schema
```

In addition to the features described above, the platform service implements a couple more described in the following subsections.

### Handle OWL Restrictions

The tool should handle the following [Domain and Range](#domain-and-range) constructs:

```ttl
:classX rdfs:subClassOf [a owl:Restriction; owl:onProperty :propP; owl:allValuesFrom  :classY]
:classX rdfs:subClassOf [a owl:Restriction; owl:onProperty :propP; owl:someValuesFrom :classY]
```

In both cases should emit the following (`props` definitions are local so this won't cause range conflict between classes):

```yaml
objects:
  classX: {props: {propP: {range: classY}}}
```

- TODO: Also handle variants with `owl:equivalentClass` instead of `rdfs:subClassOf`
- TODO: Also handle variants with `owl:intersectionOf`, they are common in LifeSci ontologies.
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

- Handle OWL cardinality and qualified cardinality restrictions and map to `min:, max:`
- `owl:someValuesFrom` is logically equivalent to `min: 1`. It is widely used in FIBO because it's less computationally expensive for reasoners
  (see [FIBO Ontology Guidelines T15. Use of "min 1" cardinality restrictions](https://github.com/edmcouncil/fibo/blob/master/ONTOLOGY_GUIDE.md#t15--use-of-min-1-cardinality-restrictions))
- The tool handles `owl:FunctionalProperty`
- Should also handle `owl:InverseFunctionalProperty` 
  as `max: 1` of an `inverseAlias` prop
  (see [Lack of Inverses](#lack-of-inverses))

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
  `owl:FunctionalProperty owl:SymmetricProperty` (and `owl:inverseOf`)
  It should process more prop characteristics: 
  `owl:InverseFunctionalProperty owl:ReflexiveProperty owl:IrreflexiveProperty owl:AsymmetricProperty owl:TransitiveProperty`.

### Better Handling of Multiple Ontologies

To handle numerous related ontologies (eg like FIBO), these improvements could be relevant:

- The tool doesn't handle `owl:import`. Instead, provide multiple ontologies on input
  (or in the case of FIBO I've concatenated Turtle files)
- Takes metadata only from `owl:Ontology` of the first supplied RDF file.
  This is a minor limitation since you can always supply the relevant file first.

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


### Unusual Datatypes

Currently the following unsupported datatypes are ignored with warning:

`xsd:duration xsd:gMonthDay xsd:gDay xsd:gMonth xsd:base64Binary xsd:hexBinary xsd:float
xsd:QName xsd:NOTATION xsd:normalizedString xsd:token xsd:language
xsd:Name xsd:NCName xsd:ID xsd:IDREF xsd:IDREFS xsd:ENTITY xsd:ENTITIES xsd:NMTOKEN xsd:NMTOKENS
owl:rational owl:real`

If the property has any other range it is selected, otherwise it's mapped to string.
As we find platform users who wish to use some of these types, we'll gradually add them to the platform.

Below we have notes on some of these types, plus some extras that are not even in the black-list above.

### owl:rational

`owl:real` is defined in OWL2 sec [4.1 Real Numbers, Decimal Numbers, and Integers](https://www.w3.org/TR/owl2-syntax/#Real_Numbers.2C_Decimal_Numbers.2C_and_Integers).
It is only of theoretical interest since it doesn't have a lexical representation.

`owl:rational` is defined in the same section.
as an exact ratio of two integers (eg `"1/3"^^owl:rational`).
This is a super-set of `xsd:decimal` because 
some rationals correspond to an infinite number of decimal digits.

FIBO uses `owl:rational` in two classes (`fibo-fnd-qt-qtu:QuantityKindFactor fibo-fnd-qt-qtu:UnitFactor`).
These are used to represent the dimension factors of units of measurement.

Properly handling them would require an extension to rdf4j: 
both for the special syntax, and to implement arithmetic operations.
rdf4j currently does not support them:

```sparql
PREFIX owl: <http://www.w3.org/2002/07/owl#>
select
  ("1/3"^^owl:rational + "2/3"^^owl:rational as ?x) 
  ("1/3"^^owl:rational < "2/3"^^owl:rational as ?y)
{}
```

The only implementation I've been able to find is 
[OWLRLExtras](https://owl-rl.readthedocs.io/en/latest/OWLRLExtras.html) in the `owl-rl` Python library by Ivan Herman 
(not sure how complete it is, eg whether it has arithmetic functions).

### GeoSPARQL Serializations

TODO: `geo:asWKT, geo:asGML`.

### PlainLiteral, XMLLiteral, HTMLLiteral

TODO

## Gaps in Ontologies

### Missing Cardinality Information

- A major shortcoming of most ontologies is that fery few props are declared `owl:FunctionalProperty`, so most of them get cardinality `max: inf` in SOML.
  Such multi-valued props are considerably more expensive to query, and if used in a filter have an implicit `EXISTS` semantics.
- The tool does not yet [Handle OWL Cardinalities](#handle-owl-cardinalities) fully
  
### Unbound Props

Some ontologies leave some props without domain (unbound), so they can be reused in  more situations.
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

## Tool Dependencies

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

21-Aug-2020:
- map `rdf:PlainLiteral` same as `rdfs:Literal` (to `string`, `langString` or `stringOrLangString` depending on `-string` option)

30-Jun-2020:
- add option `-lang`, see [Lang Specs](#lang-specs)

16-Jun-2020:
- add option `-super`, see [Superclass Interfaces](#superclass-interfaces)
- add option `-name`, see [Name Characteristic](#name-characteristic)
- add option `-string`, see [String Handling](#string-handling): emit `stringOrLangString` vs `langString` vs `string`
- add test versions `*.yaml` (without superclass interfaces) vs `*-super.yaml` (with superclass interfaces) 

4-May-2020:
- Document Java version extensions
- Option `-voc NONE`, so that `-id` and `-label` can be used independently

15-Apr-2020
- `schema:URL` is domain of `schema:category` ([schemaorg#2536](https://github.com/schemaorg/schemaorg/issues/2536)), but is in `%DATATYPES` so filter it out

14-Apr-2020
- If `-id` then don't look for any ontology metadata
- Add option `-label` to specify SOML label
- Always emit RDF terms for objects and props (don't use defaults) for clarity
- Domains "fix for referenced classes": emit "type" at concrete superclass, not at abstract
- Add description to interfaces: `XInterface: {descr: "Abstract superclass of X"}`
- `schema:Float` is a subclass of `DataType` (not a datatype directly), but is in `%DATATYPES` map, so don't emit as class

10-Apr-2020
- Fix regression in `@classes`: emitted props also as classes
- Add option `-id` to set only the SOML id and not `vocab_prefix`
- Sort labels before taking the first one, and descriptions before concatenating them.

9-Apr-2020
- Rewrite of `make_superClass, fix_superClasses` to `make_inherits, make_super, lift_super`: 
  lift `inherits` relation to abstract superclasses, if any
- Sort `creator` in order to be deterministic
- Print out all classes in warnings "Multiple superclasses/ranges found"
- List ignored classes in `@NO_CLASSES` and print them  in `usage()`

6-Apr-2020
- `make_superClass()`: fix `ERROR: Object 'lcclr:Arrangement' should have at least one type value`:
  declare RDF `type` of undefined (external) classes
- Emit the RDF `type` of superclasses at the concrete class not the abstract Interface
- Filter out unsupported datatypes (using a blacklist `@NO_DATATYPES`) and issue warning
- Sort multiple superclasses and multiple ranges by SOML name before picking the first one, in order to be deterministic
- Don't mangle prefixed names: PLATFORM-1625 "Allow punctuation in local names and prefixes" replaces `[-_.:]` with `_` so we don't need to do it

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
