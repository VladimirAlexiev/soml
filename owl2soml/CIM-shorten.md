# CIM Shorten Prop Names
<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [CIM Shorten Prop Names](#cim-shorten-prop-names)
- [Intro](#intro)
    - [Motivation](#motivation)
    - [LLM Querying Example](#llm-querying-example)
    - [Ontological Concern](#ontological-concern)
    - [Class Disjointness](#class-disjointness)
    - [Define Super-properties?](#define-super-properties)
    - [Shorten Props in JSON-LD](#shorten-props-in-json-ld)
- [CIM Prop Name Analysis](#cim-prop-name-analysis)
    - [CIM Local Prop Name Conflicts](#cim-local-prop-name-conflicts)

<!-- markdown-toc end -->

# Intro
This is an analysis of CIM class disjointness and potential "conflicts" of props that have the same local part.
- Note: it is based on 2020 versions of CIM/CGMES ontologies

Once completed, the intent is to add to `owl2soml` an option `-shorten` to shorten the GraphQL prop names to just the local part:
- `1` When the prop name matches its domain
- `2` When the prop has no domain, or its name matches the domain
- `3` Always

If "conflicts" occur on parent-child classes, then implement [PLATFORM-3035](https://ontotext.atlassian.net/browse/PLATFORM-3035) override rdfProp in subclasses

## Motivation

The overly-long CIM prop names (which are prefixed by the domain class name) have been bugging me for a couple of years.

- In electrical CIM, all props are unique to the domain class, and prop names duplicate the domain
- Furthermore, most object prop names also include the range class (or a plural version of it)
- We like the practice that a prop name replicates the range
- But replicating the domain is verbose, so we'd like to shorten prop names by removing the domain local name from the prop name (see column "SOML name", where `cim:` is the default `voc_prefix`)

| domain                 | prop name                         | SOML name           | range                            |
|------------------------|-----------------------------------|---------------------|----------------------------------|
| cim:ApparentPower      | cim:ApparentPower.value           | value               | cim:Float                        |
| cim:CurrentLimit       | entsoe2:CurrentLimit.normalValue  | entsoe2:normalValue | cim:CurrentFlow                  |
| cim:Equipment          | cim:Equipment.EquipmentContainer  | EquipmentContainer  | cim:EquipmentContainer           |
| cim:EquipmentContainer | cim:EquipmentContainer.Equipments | Equipments          | cim:Equipment.EquipmentContainer |

This would allow natural and shorter GraphQL querying, eg:

```graphql
query {equipmentContainer(ID:"...") {
  name
  equipments { # shorter and nicer than: equipmentContainer_equipments
    id
    name
  }
}}
```

But we must first analyze props that need shortening, and whether there is any potential conflict.

## LLM Querying Example
I am experimenting with LLM querying of CIM data (using GraphQL), and ChatGPT made the very natural mistake of using short prop names eg:

```graphql
query {
  location {
    coordinateSystem {
      crsUrn
    }
    positionPoints {
      xPosition
      yPosition
      zPosition
    }
  }
}
```

I corrected it:
- CIM prop names are redundant, eg in `Location` there is `location_CoordinateSystem` rather than merely `coordinateSystem`.

Then it tried something like this:
```graphql
query {
  aCLineSegment(where: { aCLineSegment_Location: {} }) {
    aCLineSegment_Location {
      location_PositionPoints {
        positionPoint_xPosition
        positionPoint_yPosition
        positionPoint_sequenceNumber
      }
    }
    aCLineSegment_BaseVoltage {
      baseVoltage_nominalVoltage
    }
  }
}
```

I had to correct it again till it got it right:
- Refer to the entity schema for the precise prop names, eg `powerSystemResource_Location` 

## Ontological Concern
Rather than convenience, I have a more serious (ontological) worry about these prop names.

The good thing about RDF is that you can slap any set of props together on the same resource, which gives you infinite extensibility.
- Some KG builders abuse that extensibility and do it without a schema.
- Some ontologists err in the opposite direction and make too strong ontological commitments, use the monomorphic `rdfs:domain/range` and burden their ontologies with too specialized props, deep abstract class hierarchies, or complex `owl:Restrictions`.

I firmly believe the fewer (and more universal) props, the better. 
If the description of two props is the same, and the domain and range are similar or compatible, 
then clearly the semantics is the same, so we better treat the two props as one.
A couple of examples:
- In the framework of the ACCORD research project (automated compliance checking of buildings/infrastructure),
  we talked with OGC about "duplicate definition of props" in several CityGML packages.
- The FIBO family of ontologies takes the same stance, and customizes prop characteristics when attaching them to classes using `owl:Restriction`.
  See [Principles of best practices for FIBO, section Overarching Principles](https://github.com/edmcouncil/fibo/blob/master/ONTOLOGY_GUIDE.md#overarching-principles) item 2:

> we attempt to define properties at the highest level in the property hierarchy where they may be applicable and limit the use of the domain and range restrictions

## Class Disjointness

A PNNL expert said that all CIM RDF resources have exactly one direct (most specific) type:
is that true?

If not then we need to complete the "conflict" analysis below with CIM domain experts to see whether:
a resource may be typed by 2 compatible types (multiple instantiation) that themselves have conflicting props.

 What is the disposition of values in such a case?
- The conflicting props may have different info
- The conflicting props must have the same info (redundant)
- Only one prop (the more specific one) is filled out

AFAIK, CIM doesn't declare disjoint classes: neither in its ontology, nor in SHACL shapes.

## Define Super-properties?
Props with the same semantics are not related in any way, you cannot query for them in a general way:
cannot write a direct query for "give me the  AsynchronousMachineDynamics of all resources"
(is this a valid competency question?).

All CIM object props have inverses.
So if it happens that the same AsynchronousMachineDynamics is shared between several resources
(if it can be a shared object not owned sub-object)
then it gets worse: you cannot find all resources using this AsynchronousMachineDynamics with a simple query.

I'm sure it's too late to change CIM prop names.
But I think that we could define common super-properties to enable more generic SPARQL querying.

## Shorten Props in JSON-LD

We can use class-dependent contexts to define that the same JSON-LD term
is expanded to different RDF props depending in which class the prop occurs.

# CIM Prop Name Analysis

- CIM uses 3761 props with an alphanumeric "local part" that follows `.`
  (there are 24 more `rdf:Property` that don't have such local part,
  these all are probably system props like `rdf:type` or `rdfs:subClassOf`)

```sparql
select * {
  ?prop a rdf:Property
  bind(replace(str(?prop1),".*\\.","") as ?localname)
  filter(regex(?localname,"^\\w+$"))
}
```

- Of them 137 don't have `rdfs:domain`. 

```sparql
select * {
  ?prop a rdf:Property
  filter not exists {?prop rdfs:domain ?domain}
  bind(replace(str(?prop),".*\\.","") as ?localname)
  filter(regex(?localname,"^\\w+$"))
}
```

- The likely reason is that we don't have (and haven't loaded) the respective extension ontologies.
  `rdf:Property` is inferred, but a domain cannot be guessed.
  We will ignore these domain-less props.
  Here is the count per extension ontology:

```sparql
select (count(*) as ?c) ?namespace {
  ?prop a rdf:Property
  filter not exists {?prop rdfs:domain ?domain}
  bind(replace(str(?prop),".*\\.","") as ?localname)
  filter(regex(?localname,"^\\w+$"))
  bind(replace(str(?prop),"(.*[/#]).*","$1") as ?namespace)
} group by ?namespace order by ?namespace
```
|  c | namespace                                      |
|----|------------------------------------------------|
| 37 | http://entsoe.eu/CIM/Framework/1/0#            |
| 18 | http://entsoe.eu/CIM/SchemaExtension/3/2#      |
| 12 | http://iec.ch/TC57/2013/CIM-schema-cim16#      |
| 33 | http://iec.ch/TC57/2013/CIM-schema-cim16-info# |
|  4 | http://powerinfo.us/CIM/Diagram/1#             |
| 33 | http://www.pti-us.com/PTI_CIM-schema-cim16#    |

- The props without domain in the `cim:` namespace are:

```
cim:BasePower.basePower
cim:Equipment.normallyInService
cim:GeneratingUnit.highControlLimit
cim:GeneratingUnit.lowControlLimit
cim:GeneratingUnit.maxEconomicP
cim:GeneratingUnit.minEconomicP
cim:IdentifiedObject.aliasName
cim:OperatingShare.OperatingParticipant
cim:OperatingShare.PowerSystemResource
cim:OperatingShare.percentage
cim:SynchronousMachine.maxU
cim:SynchronousMachine.minU
```

- Now let's look for prop names that don't repeat the domain name exactly.
  There are 25 such props:
  - `entsoe` extension props that have an extension class as domain (eg `entsoe:ConnectivityNode`), 
    which repeats the local name of the base class (eg `cim:ConnectivityNode`)
  - `md` props that have `md:Model` in the name but `md:FullModel` as domain
    (I made this mistake since I didn't have the `ISO-61970-552-model` ontology and used `md:FullModel` rather than `md:Model`):

| prop                                       | domain                   | localname            |
|--------------------------------------------|--------------------------|----------------------|
| entsoe:ConnectivityNode.boundaryPoint      | cim:ConnectivityNode     | boundaryPoint        |
| entsoe:ConnectivityNode.fromEndIsoCode     | cim:ConnectivityNode     | fromEndIsoCode       |
| entsoe:ConnectivityNode.fromEndName        | cim:ConnectivityNode     | fromEndName          |
| entsoe:ConnectivityNode.fromEndNameTso     | cim:ConnectivityNode     | fromEndNameTso       |
| entsoe:ConnectivityNode.toEndIsoCode       | cim:ConnectivityNode     | toEndIsoCode         |
| entsoe:ConnectivityNode.toEndName          | cim:ConnectivityNode     | toEndName            |
| entsoe:ConnectivityNode.toEndNameTso       | cim:ConnectivityNode     | toEndNameTso         |
| entsoe:EnergySource.EnergySchedulingType   | cim:EnergySource         | EnergySchedulingType |
| entsoe:IdentifiedObject.energyIdentCodeEic | cim:IdentifiedObject     | energyIdentCodeEic   |
| entsoe:IdentifiedObject.shortName          | cim:IdentifiedObject     | shortName            |
| entsoe:OperationalLimitType.limitType      | cim:OperationalLimitType | limitType            |
| entsoe:TopologicalNode.boundaryPoint       | cim:TopologicalNode      | boundaryPoint        |
| entsoe:TopologicalNode.fromEndIsoCode      | cim:TopologicalNode      | fromEndIsoCode       |
| entsoe:TopologicalNode.fromEndName         | cim:TopologicalNode      | fromEndName          |
| entsoe:TopologicalNode.fromEndNameTso      | cim:TopologicalNode      | fromEndNameTso       |
| entsoe:TopologicalNode.toEndIsoCode        | cim:TopologicalNode      | toEndIsoCode         |
| entsoe:TopologicalNode.toEndName           | cim:TopologicalNode      | toEndName            |
| entsoe:TopologicalNode.toEndNameTso        | cim:TopologicalNode      | toEndNameTso         |
| md:Model.DependentOn                       | md:FullModel             | DependentOn          |
| md:Model.created                           | md:FullModel             | created              |
| md:Model.description                       | md:FullModel             | description          |
| md:Model.modelingAuthoritySet              | md:FullModel             | modelingAuthoritySet |
| md:Model.profile                           | md:FullModel             | profile              |
| md:Model.scenarioTime                      | md:FullModel             | scenarioTime         |
| md:Model.version                           | md:FullModel             | version              |

## CIM Local Prop Name Conflicts

The following query finds all prop local names that are prefixed by several different domains:
```sparql
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
select ?localName (group_concat(?domainName) as ?domains) {
  {select ?localName ?domainName {
     ?prop a rdf:Property 
     bind(replace(str(?prop),".*\\.","") as ?localName)
     filter(regex(?localName,"^\\w+$"))
     bind(replace(str(?prop),"(.*)\\..*","$1") as ?domainFullName)
     bind(replace(?domainFullName,"(.*[/#]).*","$1") as ?namespace)
     optional {
       values (?prefix ?namespace) {
         ("cim:"     "http://iec.ch/TC57/2013/CIM-schema-cim16#"              )
         ("cims:"    "http://iec.ch/TC57/1999/rdf-schema-extensions-19990926#")
         ("entsoe:"  "http://entsoe.eu/CIM/SchemaExtension/3/1#"              )
         ("entsoe2:" "http://entsoe.eu/CIM/SchemaExtension/3/2#"              )
         ("fw:"      "http://entsoe.eu/CIM/Framework/1/0#"                    )
         ("icim:"    "http://iec.ch/TC57/2013/CIM-schema-cim16-info#"         )
         ("md:"      "http://iec.ch/TC57/61970-552/ModelDescription/1#"       )
         ("pid:"     "http://powerinfo.us/CIM/Diagram/1#"                     )
         ("pti:"     "http://www.pti-us.com/PTI_CIM-schema-cim16#"            )}
       bind(replace(?domainFullName,?namespace,?prefix) as ?domainShortName)}
     bind(coalesce(?domainShortName,?domainFullName) as ?domainName)
  } order by ?domainName}
} 
group by ?localName 
having regex(?domains," ")
order by ?localName
```

- There are 2214 props (504 local names) that mention several different domains: [CIM-shorten-potential-conflict.csv](CIM-shorten-potential-conflict.csv)
  - For example, the prop `ProprietaryParameterDynamics` mentions all of these domains:
  - `cim:AsynchronousMachineUserDefined cim:DiscontinuousExcitationControlUserDefined cim:ExcitationSystemUserDefined cim:LoadUserDefined cim:MechanicalLoadUserDefined cim:OverexcitationLimiterUserDefined cim:PFVArControllerType1UserDefined cim:PFVArControllerType2UserDefined cim:PowerSystemStabilizerUserDefined cim:SynchronousMachineUserDefined cim:TurbineGovernorUserDefined cim:TurbineLoadControllerUserDefined cim:UnderexcitationLimiterUserDefined cim:VoltageAdjusterUserDefined cim:VoltageCompensatorUserDefined cim:WindPlantUserDefined cim:WindType1or2UserDefined cim:WindType3or4UserDefined`
- Conversely, there are 1143 props that mention only one domain: `CIM-shorten-no-conflict.csv`.
  We can find them by replacing the "having" clause with:
```sparql
having (!regex(?domains," "))
```
