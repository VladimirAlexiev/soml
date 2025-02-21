# soml2owl

This script takes a [Semantic Objects (SOML) schema](https://platform.ontotext.com/semantic-objects/soml/index.html) and generates an OWL ontology.
We first used it for the [Building Smart Data Dictionary](https://bsdd.ontotext.com/), which came with a [GraphQL schema](https://test.bsdd.buildingsmart.org/graphiql/).
We made a [refactored GraphQL schema](https://bsdd.ontotext.com/graphiql) and derived the [BSDD SOML schema](bsdd-soml.yaml) from it.
This script converted it to a [BSDD Ontology](bsdd-ontology.ttl)

Acknowledgement: this work was done by Nataliya Keberle (@nataschake) as part of the [ACCORD project](https://accordproject.eu/) 
that has received funding from the European Union's Horizon Europe research and innovation programme under grant agreement no. 101056973.

Features
- TODO

Usage:
```
python soml2owl.py bsdd-soml.yaml > bsdd-ontology.ttl
```
