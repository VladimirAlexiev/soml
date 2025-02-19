prefix rdfs:     <http://www.w3.org/2000/01/rdf-schema#>
prefix owl:      <http://www.w3.org/2002/07/owl#>
prefix bib:      <https://bib.schema.org/>
prefix bibo:     <http://purl.org/ontology/bibo/>
prefix d0:       <http://www.ontologydesignpatterns.org/ont/d0.owl#>
prefix dul:      <http://www.ontologydesignpatterns.org/ont/dul/DUL.owl#>
prefix foaf:     <http://xmlns.com/foaf/0.1/>
prefix gn:       <http://www.geonames.org/ontology#>
prefix gnd:      <https://d-nb.info/standards/elementset/gnd#>
prefix mo:       <http://purl.org/ontology/mo/>
prefix nl-bag:   <http://bag.basisregistraties.overheid.nl/def/bag#>
prefix nl-ceo:   <https://linkeddata.cultureelerfgoed.nl/vocab/def/ceo#>
prefix nl-rkd:   <http://data.rkd.nl/def#>
prefix prov:     <http://www.w3.org/ns/prov#>
prefix schema:   <http://schema.org/>
prefix skos:     <http://www.w3.org/2004/02/skos/core#>
prefix wgs84pos: <http://www.w3.org/2003/01/geo/wgs84_pos#>
prefix wikidata: <http://www.wikidata.org/entity/>

delete {?x ?p ?y}
where {
  values ?p {owl:equivalentClass owl:equivalentProperty rdfs:subClassOf rdfs:subPropertyOf}
  ?x ?p ?y
  filter (
   strstarts(str(?y),str(owl:     )) ||
   strstarts(str(?y),str(bib:     )) ||
   strstarts(str(?y),str(bibo:    )) ||
   strstarts(str(?y),str(d0:      )) ||
   strstarts(str(?y),str(dul:     )) ||
   strstarts(str(?y),str(foaf:    )) ||
   strstarts(str(?y),str(gn:      )) ||
   strstarts(str(?y),str(gnd:     )) ||
   strstarts(str(?y),str(mo:      )) ||
   strstarts(str(?y),str(nl-bag:  )) ||
   strstarts(str(?y),str(nl-ceo:  )) ||
   strstarts(str(?y),str(nl-rkd:  )) ||
   strstarts(str(?y),str(prov:    )) ||
   strstarts(str(?y),str(schema:  )) ||
   strstarts(str(?y),str(skos:    )) ||
   strstarts(str(?y),str(wgs84pos:)) ||
   strstarts(str(?y),str(wikidata:)) )
}
