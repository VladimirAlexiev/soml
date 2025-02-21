import yaml
from rdflib import Graph, Namespace, RDF, RDFS, OWL, XSD, Literal, BNode

# Recursive creation of rdf:parseType = "Collection"
def collection_from_list(g, *rest):
    node_union = BNode()
    g.add((node_union, RDF.first, rest[0]))
    if len(rest) > 1:
        g.add((node_union, RDF.rest, collection_from_list(g, *(rest[1:]))))
    else:
        g.add((node_union, RDF.rest, RDF.nil))
    return node_union

# Load SOML schema
def load_soml_schema(file_path):
    with open(file_path, "r", encoding="utf-8") as file:
        return yaml.safe_load(file)

# Initialize RDF graph
def initialize_graph():
    g = Graph()
    bsdd = Namespace("http://bsdd.buildingsmart.org/def#")
    schema = Namespace("https://schema.org/")
    g.bind("bsdd", bsdd)
    g.bind("schema", schema)
    g.bind("owl", OWL)
    g.bind("rdfs", RDFS)
    g.bind("xsd", XSD)
    return g, bsdd, schema

# Handle unionOf for properties with multiple class ranges
def merge_object_property_ranges(graph):
    updated_graph = Graph()
    updated_graph += graph

    # Find all owl:ObjectProperty with multiple rdfs:range values
    properties_to_update = {}
    for s, p, o in graph.triples((None, RDF.type, OWL.ObjectProperty)):
        ranges = list(graph.objects(s, RDFS.range))
        if len(ranges) > 1:
            properties_to_update[s] = ranges

    # Remove old range declarations and replace with unionOf restriction
    for prop, ranges in properties_to_update.items():
        for r in ranges:
            updated_graph.remove((prop, RDFS.range, r))
        
        # Create an owl:unionOf restriction
        union_bnode = BNode()
        restriction_bnode = BNode()
        updated_graph.add((restriction_bnode, RDF.type, OWL.Restriction))
        updated_graph.add((prop, RDFS.range, restriction_bnode))
        updated_graph.add((restriction_bnode, OWL.unionOf, collection_from_list(updated_graph, *ranges)))
            
    return updated_graph

# Mapping of SOML types to RDF types
def get_rdf_type(soml_type, bsdd):
    xsd_mapping = {
        "string": XSD.string,
        "int": XSD.integer,
        "boolean": XSD.boolean,
        "decimal": XSD.decimal,
        "dateTime": XSD.dateTime,
        "iri": XSD.anyURI
    }
    if soml_type in xsd_mapping:
        return xsd_mapping[soml_type]
    return bsdd[soml_type] if soml_type[0].isupper() else XSD.string

# Convert types to OWL enumerations
def convert_types(g, bsdd, types):
    for type_name, type_data in types.items():
        type_uri = bsdd[type_name]
        g.add((type_uri, RDF.type, RDFS.Datatype))
        list_items = [Literal(v["name"]) for v in type_data["values"]]
        list_bnode = BNode()

        equivalent_class_bnode = BNode()
        g.add((type_uri, OWL.equivalentClass, equivalent_class_bnode))
        g.add((equivalent_class_bnode, RDF.type, RDFS.Datatype))
        g.add((equivalent_class_bnode, OWL.oneOf, collection_from_list(g, *list_items)))

# Convert objects to OWL classes and properties
def convert_objects(g, bsdd, schema, objects):
    for obj_name, obj_data in objects.items():
        obj_uri = bsdd[obj_name]
        g.add((obj_uri, RDF.type, OWL.Class))
        g.add((obj_uri, RDFS.comment, Literal(obj_data["label"])))
        for prop_name, prop_data in obj_data.get("props", {}).items():
            prop_uri = bsdd[prop_name]
            prop_range = get_rdf_type(prop_data.get("range", "string"), bsdd)
            is_object_property = isinstance(prop_range, (str, Namespace)) and str(prop_range).startswith(str(bsdd))
            prop_type = OWL.ObjectProperty if is_object_property else OWL.DatatypeProperty
            g.add((prop_uri, RDF.type, prop_type))
            g.add((prop_uri, RDFS.comment, Literal(prop_data["label"])))
            g.add((prop_uri, RDFS.range, prop_range))
            g.add((prop_uri, schema.domainIncludes, obj_uri))
        
        # Apply cardinality and range restrictions at the class level
        for prop_name, prop_data in obj_data.get("props", {}).items():
            restriction_bnode = BNode()
            g.add((restriction_bnode, RDF.type, OWL.Restriction))
            g.add((restriction_bnode, OWL.onProperty, bsdd[prop_name]))
            
            prop_range = get_rdf_type(prop_data.get("range", "string"), bsdd)
            if "min" in prop_data and prop_data["min"] >= 1:
                g.add((restriction_bnode, OWL.someValuesFrom, prop_range))
                g.add((restriction_bnode, OWL.minCardinality, Literal(prop_data["min"], datatype=XSD.integer)))
            if "max" in prop_data and prop_data["max"] != "inf":
                g.add((restriction_bnode, OWL.maxCardinality, Literal(prop_data["max"], datatype=XSD.integer)))
            else:
                g.add((restriction_bnode, OWL.allValuesFrom, prop_range))
            
            g.add((obj_uri, RDFS.subClassOf, restriction_bnode))

# Convert SOML schema to RDF graph
def convert_soml_to_turtle(soml_schema):
    g, bsdd, schema = initialize_graph()
    convert_types(g, bsdd, soml_schema["types"])
    convert_objects(g, bsdd, schema, soml_schema["objects"])
    g = merge_object_property_ranges(g)
    return g.serialize(format="turtle", base="http://bsdd.buildingsmart.org/def#")

# Load schema and convert to Turtle
soml_schema = load_soml_schema("bsdd-graphql-soml-refact.yaml")
turtle_output = convert_soml_to_turtle(soml_schema)
print(turtle_output)
