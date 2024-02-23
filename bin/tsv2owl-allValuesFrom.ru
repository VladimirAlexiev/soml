prefix s:    <http://schema.org/>
prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>
prefix owl:  <http://www.w3.org/2002/07/owl#>

insert {?restriction owl:allValuesFrom ?range}
where {
  ?class rdfs:subClassOf ?restriction.
  ?restriction a owl:Restriction; owl:onProperty ?prop.
  ?prop (s:rangeIncludes|rdfs:range) ?range
}
