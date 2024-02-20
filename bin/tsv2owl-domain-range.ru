prefix s: <http://schema.org/>
prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>

# If a prop has a single s:domainIncludes, convert it to rdfs:domain
delete {?p s:domainIncludes ?c}
insert {?p rdfs:domain ?c}
where {
  ?p s:domainIncludes ?c
  filter not exists {
    ?p s:domainIncludes ?c1
    filter(?c1 != ?c)
  }
};

# If a prop has a single s:rangeIncludes, convert it to rdfs:range
delete {?p s:rangeIncludes ?c}
insert {?p rdfs:range ?c}
where {
  ?p s:rangeIncludes ?c
  filter not exists {
    ?p s:rangeIncludes ?c1
    filter(?c1 != ?c)
  }
};
