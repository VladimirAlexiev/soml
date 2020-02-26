# SKOS

## SKOS Turtle
```sh
$ time perl ../owl2soml.pl skos.ttl > skos.yaml
Multiple ranges found for prop member, using only the first one: Concept
real    0m8.982s
user    0m0.016s
sys     0m0.062s
```

## SKOS RDF
```
$ time perl ../owl2soml.pl skos.rdf > skos1.yaml
Multiple ranges found for prop member, using only the first one: Concept
real    0m8.796s
user    0m0.015s
sys     0m0.046s
```

# Schema

https://schema.org/docs/developers.html

schema.nt is not appropriate for this tool because it doesn't define prefixes.

## Schema OWL (Experimental)

"Experimental/Unsupported"
schema:domainIncludes and schema:rangeIncludes values are converted into rdfs:domain and rdfs:range values using owl:unionOf to capture the multiplicity of values. Included in the range values are the, implicit within the vocabulary, default values of Text, URL, and Role.
As an experimental feature, there are no expectations as to its interpretation by any third party tools.

https://schema.org/docs/schemaorg.owl : 404 Not Found
https://github.com/schemaorg/schemaorg/issues/2472