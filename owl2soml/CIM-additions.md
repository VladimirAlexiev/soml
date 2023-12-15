---
title: CIM Additions to owl2soml
date: 2020-11-06
---

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Intro](#intro)
- [CIM Multiplicities](#cim-multiplicities)
- [CIM Inverses](#cim-inverses)
- [CIM Datatypes](#cim-datatypes)
    - [Example of ActivePowerPerCurrentFlow](#example-of-activepowerpercurrentflow)
    - [Example of CurrentLimit](#example-of-currentlimit)
    - [Example of Measurement](#example-of-measurement)
    - [Example of RegulatingControl](#example-of-regulatingcontrol)
    - [Mapping Primitive Datatypes](#mapping-primitive-datatypes)
    - [Mapping Non-Primitive Datatypes](#mapping-non-primitive-datatypes)

<!-- markdown-toc end -->

# Intro
- `owl2soml` now includes specific handling for IEC CIM (thus ENTSO-E CGMES).
- BEWARE: this handling depends on the following namespaces. Notice that CIM has various versions, so you may also encounter `cim15` and others.

```ttl
@prefix cims:  <http://iec.ch/TC57/1999/rdf-schema-extensions-19990926#> .
@prefix cim:   <http://iec.ch/TC57/2013/CIM-schema-cim16#> .
```

- DONE: ignore `^^rdf:XMLLiteral` in descriptions
- TODO: [CIM-shorten.md](CIM-shorten.md)

# CIM Multiplicities

DONE: map `cims:multiplicity` to `min, max`:

```
"cims:M:0..1" => {min => 0, max => 1},
"cims:M:0..2" => {min => 0, max => 2},
"cims:M:0..n" => {min => 0, max => "inf"},
"cims:M:1"    => {min => 1, max => 1},
"cims:M:1..1" => {min => 1, max => 1},
"cims:M:1..n" => {min => 1, max => "inf"},
"cims:M:2..n" => {min => 2, max => "inf"}
```

# CIM Inverses

DONE:
- `cims:inverseRoleName` is treated as `owl:inverseOf`
- The following SPARQL Update ([sol/demonstrators/statnett/data/update/inverses.ru](https://gitlab.ontotext.com/sol/demonstrators/statnett/-/blob/master/data/update/inverses.ru)) does this in the RDF data:

```sparql
prefix cims: <http://iec.ch/TC57/1999/rdf-schema-extensions-19990926#>
prefix owl:  <http://www.w3.org/2002/07/owl#>

insert {
  ?p owl:inverseOf ?q
} where {
  ?p cims:inverseRoleName ?q
}
```

# CIM Datatypes

DONE

CIM has its own way of handling datatypes (`cims:dataType`) that also mixes in Units of Measure.

Datatypes are described by the following characteristics (`value` is primary and the rest are auxiliary):

```sparql
select ?propName (count(*) as ?c) {
  ?prop rdfs:domain ?dt.
  ?dt cims:stereotype "CIMDatatype".
    bind(replace(str(?prop),".*\\.","") as ?propName)
} group by ?propName order by ?propName
```

- `cim:Simple_Float` has only characteristic `value`, which is the primitive `cim:Float`
- 21 datatypes have characteristics `unit, multiplier, value`
- 8 datatypes have characteristics `unit, multiplier, denominatorUnit, denominatorMultiplier, value`.
  These include `cim:RotationSpeed, cim:VolumeFlowRate` and "xPerY" units like `cim:InductancePerLength, cim:VoltagePerReactivePower`
- The axiliary characteristics are optional with multiplicity `cims:M:0..1`
  - And indeed they are fixed by the datatype so are omitted from data
- It's unclear why `value` also has multiplicity `cims:M:0..1`: if the value is not present then none of the other have any point?
  (Only `cim:Simple_Float.value` is mandatory: `cims:M:1..1`)

We have a somewhat complicated SPARQL Update ([sol/demonstrators/statnett/data/update/datatypes.ru](https://gitlab.ontotext.com/sol/demonstrators/statnett/-/blob/master/data/update/datatypes.ru))
that fixes the datatypes of literal values, based on the analysis in the following sections.

## Example of ActivePowerPerCurrentFlow

Example of a datatype with all characteristics:

```ttl
cim:ActivePowerPerCurrentFlow a rdfs:Class ;
  cims:stereotype         "CIMDatatype" .

cim:ActivePowerPerCurrentFlow.denominatorMultiplier a rdf:Property ;
  rdfs:domain        cim:ActivePowerPerCurrentFlow ;
  rdfs:range         cim:UnitMultiplier ;
  cims:isFixed       "none" ;
  cims:multiplicity  cims:M:0..1.

cim:ActivePowerPerCurrentFlow.denominatorUnit a rdf:Property ;
  rdfs:domain        cim:ActivePowerPerCurrentFlow ;
  rdfs:range         cim:UnitSymbol ;
  cims:isFixed       "A" ;
  cims:multiplicity  cims:M:0..1.

cim:ActivePowerPerCurrentFlow.multiplier a rdf:Property ;
  rdfs:domain        cim:ActivePowerPerCurrentFlow ;
  rdfs:range         cim:UnitMultiplier ;
  cims:isFixed       "M" ;
  cims:multiplicity  cims:M:0..1.

cim:ActivePowerPerCurrentFlow.unit a rdf:Property ;
  rdfs:domain        cim:ActivePowerPerCurrentFlow ;
  rdfs:range         cim:UnitSymbol ;
  cims:isFixed       "W" ;
  cims:multiplicity  cims:M:0..1.

cim:ActivePowerPerCurrentFlow.value a rdf:Property ;
  rdfs:domain        cim:ActivePowerPerCurrentFlow ;
  cims:dataType      cim:Float ;
  cims:multiplicity  cims:M:0..1.
```

This means that `ActivePowerPerCurrentFlow` is measured in `MW/A`.
These characteristics (`mutliplier, unit, denominatorUnit`) are fixed.
In data, an attribute with datatype `cim:ActivePowerPerCurrentFlow` will have only field `value`.

## Example of CurrentLimit

`CurrentLimit` is declared to use datatype `CurrentFlow`, which is an example of a datatype with 3 characteristics:

```ttl
cim:CurrentLimit  a rdfs:Class ;
  rdfs:subClassOf         cim:OperationalLimit.

cim:CurrentLimit.value a rdf:Property ;
  rdfs:domain        cim:CurrentLimit ;
  cims:dataType      cim:CurrentFlow ;
  cims:multiplicity  cims:M:1..1.


cim:CurrentFlow  a rdfs:Class ;
  cims:stereotype         "CIMDatatype" .

cim:CurrentFlow.multiplier a rdf:Property ;
  rdfs:domain        cim:CurrentFlow ;
  rdfs:range         cim:UnitMultiplier ;
  cims:isFixed       "none" ;
  cims:multiplicity  cims:M:0..1.

cim:CurrentFlow.unit  a rdf:Property ;
  rdfs:domain        cim:CurrentFlow ;
  rdfs:range         cim:UnitSymbol ;
  cims:isFixed       "A" ;
  cims:multiplicity  cims:M:0..1.

cim:CurrentFlow.value a rdf:Property ;
  rdfs:domain        cim:CurrentFlow ;
  cims:dataType      cim:Float ;
  cims:multiplicity  cims:M:0..1.
```

Actual data uses only `value` (not `unit` or `multiplier`), and in some cases has a second field `normalValue`:

```ttl
<#_07a05ab2-d780-11e7-9296-cec278b6b50a> a cim:CurrentLimit ;
  entsoe2:CurrentLimit.normalValue "7880" ;
  cim:CurrentLimit.value           "7880" ;
  cim:IdentifiedObject.description "CurrentLimit TATL Negative 30 degree Celsius" ;
```

## Example of Measurement

`cim:Measurement` has fields `unitSymbol` and `unitMultiplier` that are objects not strings, and are mandatory.
So it differs completely from CIM datatypes.

```ttl
cim:Analog a rdfs:Class; rdfs:subClassOf cim:Measurement.

cim:Measurement a rdfs:Class ;
cim:Measurement.measurementType a rdf:Property ;
  rdfs:domain        cim:Measurement ;
  cims:dataType      cim:String ;
  cims:multiplicity  cims:M:1..1.
cim:Measurement.unitMultiplier a rdf:Property ;
  rdfs:domain        cim:Measurement ;
  rdfs:range         cim:UnitMultiplier ;
  cims:multiplicity  cims:M:1..1.
cim:Measurement.unitSymbol a rdf:Property ;
  rdfs:domain        cim:Measurement ;
  rdfs:range         cim:UnitSymbol ;
  cims:multiplicity  cims:M:1..1.

<#_0aa5e8dd-7ee5-e04c-a5f4-400089570f6c> a cim:Analog ;
  cim:IdentifiedObject.description "NO1 BiddingZone Installed Hydro Reservoir Capacity Active Power" ;
  cim:Measurement.measurementType  "ThreePhaseActivePower" ;
  cim:Measurement.unitMultiplier    cim:UnitMultiplier.M ;
  cim:Measurement.unitSymbol        cim:UnitSymbol.W ;
  pti:Measurement.uncefactUnitCode "B12" .
```

In this case `unitSymbol, unitMultiplier` is "MW" whereas `uncefactUnitCode=B12` is "joule per metre" (see [UNCEFACT Rec 20 Annex B3](https://unece.org/fileadmin/DAM/cefact/recommendations/add3b.htm)).
I have no idea what this means, since these two units are different: W is "joule per second" (see QUDT [unit:W](http://qudt.org/vocab/unit/W)).

## Example of RegulatingControl

`cim:RegulatingControl` has these fields:

- `targetDeadband`: an optional `cim:Simple_Float`
- `targetValue`: a mandatory `cim:Simple_Float`
- `targetValueUnitMultiplier`: a mandatory `cim:UnitMultiplier` (object not string)

```ttl
<#_f1769817-9aeb-11e5-91da-b8763fd99c5f> a cim:RegulatingControl ;
  cim:RegulatingControl.discrete       "false" ;
  cim:RegulatingControl.enabled        "true" ;
  cim:RegulatingControl.targetDeadband "0" ;
  cim:RegulatingControl.targetValue    "420" ;
  cim:RegulatingControl.targetValueUnitMultiplier cim:UnitMultiplier.k .
```

This uses prop `targetValue` not `value`.
So the field `cim:Simple_Float.value` is a falsehood: it does not guarantee that the class using the datatype will have such a field.

## Mapping Primitive Datatypes

Primitive datatypes have stereotype "Primitive":
```sparql
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX cims: <http://iec.ch/TC57/1999/rdf-schema-extensions-19990926#>
select ?datatype ?primitive {
  ?datatype cims:stereotype "Primitive".
} order by ?datatype
```

There are 8 that are mapped to XSD datatypes as follows:

```
   "cim:Boolean"  => "boolean",
   "cim:Date"     => "date",
   "cim:DateTime" => "dateTime",
   "cim:Decimal"  => "decimal",  # infinite precision
   "cim:Float"    => "double",   # or maybe "float"? But that's not standard in GraphQL
   "cim:Integer"  => "int",      # or maybe "integer" for infinite precision?
   "cim:MonthDay" => "string",   # TODO: xsd:gMonthDay not yet supported by the platform, but this datatype is not used
   "cim:String"   => "string",
```

## Mapping Non-Primitive Datatypes

Non-primitive datatypes have stereotype "CIMDatatype" and include the following 30.

The upshot of the examples given above is that such datatypes should be expressed as the corresponding primitive datatype.

- Their characteristics `unit, multiplier, denominatorUnit, denominatorMultiplier` (when present) are fixed, and not expressed in data.
- The characterstic `value` serves merely to point to the primitive datatype; actual data may use a different property to express the value.

```sparql
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX cims: <http://iec.ch/TC57/1999/rdf-schema-extensions-19990926#>
select ?datatype ?primitive {
  ?datatype cims:stereotype "CIMDatatype".
  ?value rdfs:domain ?datatype.
  ?value cims:dataType ?primitive
} order by ?datatype
```

Afer we map primitive datatypes to SOML (see previous section), we get this:

```
   "cim:ActivePower"                => "double",   # cim:Float
   "cim:ActivePowerPerCurrentFlow"  => "double",   # cim:Float
   "cim:ActivePowerPerFrequency"    => "double",   # cim:Float
   "cim:AngleDegrees"               => "double",   # cim:Float
   "cim:AngleRadians"               => "double",   # cim:Float
   "cim:ApparentPower"              => "double",   # cim:Float
   "cim:Area"                       => "double",   # cim:Float
   "cim:Capacitance"                => "double",   # cim:Float
   "cim:CapacitancePerLength"       => "double",   # cim:Float
   "cim:Conductance"                => "double",   # cim:Float
   "cim:CurrentFlow"                => "double",   # cim:Float
   "cim:Frequency"                  => "double",   # cim:Float
   "cim:Inductance"                 => "double",   # cim:Float
   "cim:InductancePerLength"        => "double",   # cim:Float
   "cim:Length"                     => "double",   # cim:Float
   "cim:Money"                      => "decimal",  # cim:Decimal
   "cim:PerCent"                    => "double",   # cim:Float
   "cim:PU"                         => "double",   # cim:Float
   "cim:Reactance"                  => "double",   # cim:Float
   "cim:ReactivePower"              => "double",   # cim:Float
   "cim:Resistance"                 => "double",   # cim:Float
   "cim:ResistancePerLength"        => "double",   # cim:Float
   "cim:RotationSpeed"              => "double",   # cim:Float
   "cim:Seconds"                    => "double",   # cim:Float
   "cim:Simple_Float"               => "double",   # cim:Float
   "cim:Susceptance"                => "double",   # cim:Float
   "cim:Temperature"                => "double",   # cim:Float
   "cim:Voltage"                    => "double",   # cim:Float
   "cim:VoltagePerReactivePower"    => "double",   # cim:Float
   "cim:VolumeFlowRate"             => "double",   # cim:Float
```
