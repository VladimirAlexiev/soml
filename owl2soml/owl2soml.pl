#!perl -w

# see https://github.com/VladimirAlexiev/soml/tree/master/owl2soml#change-log

use v5.14;
use warnings;
use open ':std', ':encoding(utf8)';
no warnings 'redefine'; # try to quash https://github.com/kasei/attean/issues/153 "Subroutine spacepad redefined" but it's still here :-(
use strict;
use Carp::Always; # use Carp "verbose"
use Attean;
use URI::NamespaceMap;
use List::MoreUtils qw(uniq);
use Array::Utils qw(array_minus);
#use autodie; # https://perldoc.perl.org/5.30.0/autodie.html
#use Data::Dumper;
use Getopt::Long;

our $store = Attean->get_store('Memory')->new();
our $model = Attean::MutableQuadModel->new(store => $store);
our $graph = Attean::IRI->new('http://example.org/');
our $ontology_iri;                     # as Attean::IRI
our $ontology;                         # $ontology_iri as string
our $vocab_iri;                        # vocab namespace as Attean::IRI
our $vocab_prefix;                     # vocab prefix as string
our $map   = URI::NamespaceMap->new(); # prefixes in loaded ontologies
our $MAP   = URI::NamespaceMap->new    # fixed prefixes used in mapping ("service" namespace)
  ({so     => "http://www.ontotext.com/semantic-object/",
    dc     => "http://purl.org/dc/elements/1.1/",
    dct    => "http://purl.org/dc/terms/",
    owl    => "http://www.w3.org/2002/07/owl#",
    rdf    => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
    rdfs   => "http://www.w3.org/2000/01/rdf-schema#",
    schema => "http://schema.org/",
    skos   => "http://www.w3.org/2004/02/skos/core#",
    swc    => "http://schema.semantic-web.at/ppt/",
    vann   => "http://purl.org/vocab/vann/preferredNamespaceUri",
    xsd    => "http://www.w3.org/2001/XMLSchema#",
    "fibo-fnd-dt-fd" => "https://spec.edmcouncil.org/fibo/ontology/FND/DatesAndTimes/FinancialDates/",
   });
our %iri_name;   # Mapping from IRI->as_string to {"rdf" => prefixed name, "gql" => stripped vocab_prefix}
our %gql_rdf;    # Mapping from gql name to rdf name
our %inherits;   # Mapping of rdfs:subClassOf relations as gql names (max one per class: no multiple inheritance)
our %super;      # Mapping from concrete "class" to abstract "classInterface" (for superclasses only) as gql names
our %soml;       # The total SOML as hash (dict), see YAML::Dump at the end

our @PROP_CLASSES =
  qw(rdf:Property owl:AnnotationProperty owl:DatatypeProperty owl:ObjectProperty
   owl:FunctionalProperty owl:InverseFunctionalProperty owl:ReflexiveProperty
   owl:IrreflexiveProperty owl:SymmetricProperty owl:AsymmetricProperty owl:TransitiveProperty);
our @NO_CLASSES = qw(owl:Thing schema:Thing owl:Nothing schema:DataType);
our @NO_PROPS = qw(owl:topObjectProperty owl:bottomObjectProperty owl:topDataProperty owl:bottomDataProperty);
our @LABEL_PROPS = qw(rdfs:label skos:prefLabel dc:title dct:title);
our @DESCR_PROPS = qw(rdfs:comment skos:definition skos:description skos:scopeNote dc:description dct:description);
our @CREATOR_PROPS = qw(dc:creator dct:creator); # dc:contributor dct:contributor
our %DATATYPES =
  (# XSD datatypes
   "xsd:string"             => "string",
   "xsd:double"             => "double",
   "xsd:boolean"            => "boolean",
   "xsd:byte"               => "byte",
   "xsd:short"              => "short",
   "xsd:int"                => "int",
   "xsd:long"               => "long",
   "xsd:unsignedLong"       => "unsignedLong",
   "xsd:unsignedInt"        => "unsignedInt",
   "xsd:unsignedShort"      => "unsignedShort",
   "xsd:unsignedByte"       => "unsignedByte",
   "xsd:decimal"            => "decimal",
   "xsd:integer"            => "integer",
   "xsd:positiveInteger"    => "positiveInteger",
   "xsd:nonPositiveInteger" => "nonPositiveInteger",
   "xsd:negativeInteger"    => "negativeInteger",
   "xsd:nonNegativeInteger" => "nonNegativeInteger",
   "xsd:dateTime"           => "dateTime",
   "xsd:dateTimeStamp"      => "dateTime",
   "xsd:time"               => "time",
   "xsd:date"               => "date",
   "xsd:gYear"              => "year",
   "xsd:gYearMonth"         => "yearMonth",
   # other datatypes
   "rdfs:Literal"           => "string",
   "rdf:langString"         => "string",
   "schema:Boolean"         => "boolean",
   "schema:Date"            => "date",
   "schema:DateTime"        => "dateTime",
   "schema:Float"           => "double",
   "schema:Integer"         => "integer",
   "schema:Number"          => "decimal",
   "schema:Text"            => "string",
   "schema:Time"            => "time",
   "schema:URL"             => "iri",
   "rdfs:Resource"          => "iri",
   "xsd:anyURI"             => "iri",
   # unusual datatypes
   "fibo-fnd-dt-fd:CombinedDateTime" => "dateOrYearOrMonth",
  );

# datatypes ignored with warning
our @NO_DATATYPES =
  qw(xsd:duration xsd:gMonthDay xsd:gDay xsd:gMonth xsd:base64Binary xsd:hexBinary xsd:float xsd:QName xsd:NOTATION xsd:normalizedString xsd:token xsd:language xsd:Name xsd:NCName xsd:ID xsd:IDREF xsd:IDREFS xsd:ENTITY xsd:ENTITIES xsd:NMTOKEN xsd:NMTOKENS owl:rational owl:real);
our %NO_DATATYPES;
map {$NO_DATATYPES{$_} = 1} @NO_DATATYPES;

sub my_exit() {
  # quash warnings "(in cleanup) at URI/Namespace.pm line 104 during global destruction"
  $map = $MAP = undef;
  exit
}

sub my_warn($) {
  my $err = shift;
  $err = "$err\n" unless $err =~ /\n$/;
  print STDERR $err;
}

sub my_die($) {
  my_warn(shift);
  my_exit()
}

sub usage () {
  my $no_classes    = join ", ", sort @NO_CLASSES;
  my $label_props   = join ", ", sort @LABEL_PROPS;
  my $descr_props   = join ", ", sort @DESCR_PROPS;
  my $creator_props = join ", ", sort @CREATOR_PROPS;
  my $datatypes     = join ", ", sort keys %DATATYPES;
  my $no_datatypes  = join ", ", sort @NO_DATATYPES;
  my_die << "END";
$0 - Generates SOML from supplied ontologies

Usage: $0 ontology.(ttl|rdf) ... > ontology.yaml
Options:
  --vocab pfx     Uses "pfx" as the main vocab_prefix

Parses:
- ontologies (owl:Ontology, dct:created, dct:modified, $creator_props),
- classes (rdfs:Class, owl:Class);
  - EXCLUDES schema:DataTypes and $no_classes;
- class inheritance (rdfs:subClassOf). Generates concrete class and abstract superclass and patches the hierarchy;
- props (rdf:Property, owl:AnnotationProperty, owl:DatatypeProperty, owl:ObjectProperty);
- datatypes (default string; $datatypes);
  - EXCLUDES $no_datatypes
- prop relations (owl:inverseOf, schema:inverseOf; but NOT rdfs:subPropertyOf);
- prop domains (rdfs:domain, schema:domainIncludes, owl:unionOf). Multiple domains are allowed.
- prop ranges (rdfs:range, schema:rangeIncludes, owl:unionOf). Object or datatype ranges are allowed.
- labels ($label_props),
- descriptions ($descr_props).
- if a range class (eg rdf:List) is not defined in the ontology, it's defined in SOML without any props

Limitations:
- Takes metadata only from the first ("root") owl:Ontology
- Uses only labels/descriptions in "en" (including en-US, en-GB etc) or without language tag
- owl:AnnotationProperty and owl:DatatypeProperty are treated the same
- Doesn't suppport multiple superclasses (the first one is used). Enquire about the status of issue PLATFORM-360
- Doesn't support multiple prop ranges (the first one is used). Enquire about the status of issue PLATFORM-1493
- Doesn't handle owl:import. Instead, provide multiple ontologies on input
- Doesn't strip HTML tags (eg in schema.org property rdfs:comments)
- rdf:langString and rdfs:Literal are mapped to xsd:string
- Doesn't inherit domain & range from a property's ancestor(s). Enquire about the status of issue PLATFORM-1500
END
}

GetOptions ("vocab=s" => \$vocab_prefix) or usage();

sub first_ontology() {
  # get ontology metadata, and try to figure out vocab_iri and vocab_prefix

  my $base;
  my $iter = $model->subjects(IRI("rdf:type"), IRI("owl:Ontology"));
  if ($ontology_iri = $iter->next) {
    $ontology = $ontology_iri->as_string;
    $iter->next and my_warn("Found multiple ontologies, metadata only of the first one is used: $ontology");
    $base = one_value($model->objects($ontology_iri, IRI("swc:BaseUrl")))
  };
  # try to find vocab_iri and vocab_prefix in various inter-dependent ways
  if ($vocab_prefix) { # option --vocab $vocab_refix
    $vocab_iri = iri ($map->namespace_uri($vocab_prefix))
      or my_die "can't find vocab_iri of --vocab prefix $vocab_prefix";
  } elsif ($ontology_iri and $vocab_prefix = one_value($model->objects($ontology_iri, IRI("swc:identifier")))) {
    $vocab_iri = iri ($map->namespace_uri($vocab_prefix)) || do {
      $map->add_mapping ($vocab_prefix => "$ontology/");
      iri ("$ontology/");
      # my_die "can't find vocab_iri of swc:identifier '$vocab_prefix'";
      # my_die "--vocab prefix '$vocab_prefix' does not agree with swc:identifier '$vocab_prefix1'" if $vocab_prefix && $vocab_prefix1 && $vocab_prefix ne $vocab_prefix1;
    }
  } elsif ($ontology_iri and $vocab_iri = one_value($model->objects($ontology_iri, IRI("vann:preferredNamespaceUri")))) {
    my $voc1 = $map->prefix_for($vocab_iri);
    my $voc2 = one_value($model->objects($ontology_iri, IRI("vann:preferredNamespacePrefix")));
    if ($voc1 && $voc2 && $voc1 ne $voc2) {
      my $vocab2 = $map->namespace_uri($voc2);
      $vocab2 &&= $vocab2->as_string;
      if ($vocab2) {
        my_die "Namespace $vocab_iri from vann:preferredNamespaceUri (prefix $voc1) does not agree with  namespace $vocab2 (from vann:preferredNamespacePrefix $voc2)"
          if $vocab2 ne $vocab_iri;
      } else {
        $map->add_mapping ($voc2 => $vocab_iri)
      }
    };
    $voc1 || $voc2 or my_die "can't find vocab_prefix for vann:preferredNamespaceUri $vocab_iri, and vann:preferredNamespacePrefix is not specified";
    $vocab_prefix = $voc1 || $voc2;
    $vocab_iri = iri ($vocab_iri);
  } elsif ($ontology_iri) { # look for it amongst defined prefixes
    my $ontology_re = qr(^\Q$ontology\E[#/]?$); # ontology IRI, optionally followed by slash or hash
    for ($map->list_namespaces) {
      if ($_->as_string =~ m{$ontology_re}) {
        $vocab_prefix = $map->prefix_for($_);
        $vocab_iri = iri($_);
        last
      }
    };
    $vocab_iri or my_die "can't find vocab_iri for $ontology amongst these namespaces:\n".
      (join"\n", sort map $_->as_string, $map->list_namespaces);
  } else {
    my_die "can't find owl:Ontology (should be in first RDF file) and --vocab prefix not specified"
  };
  $soml{id} = "/soml/$vocab_prefix";
  $soml{specialPrefixes}{vocab_prefix} = $vocab_prefix;
  $soml{specialPrefixes}{vocab_iri}    = $vocab_iri->as_string;
  $soml{specialPrefixes}{ontology_iri} = $ontology if $ontology;
  $soml{specialPrefixes}{base_iri}     = $base if $base;
}

sub load_ontologies(@) {
  my $count = 0;
  while (my $data = shift) {
    # my $base  = Attean::IRI->new('http://example.org/');
    open(my $fh, '<:encoding(utf-8)', $data) or my_die "can't open $data: $!";
    my $pclass  = Attean->get_parser(filename => $data) // 'AtteanX::Parser::Turtle';
    my $parser  = $pclass->new(namespaces => $map); # base => $base
    my $iter    = $parser->parse_iter_from_io($fh);
    my $quads   = $iter->as_quads($graph);
    $model->add_iter($quads);
    first_ontology() unless $count++
  }
}

sub query_select ($) {
  # NOT USED yet.
  # From https://github.com/kasei/attean/blob/master/bin/attean_query
  # https://github.com/kasei/attean/issues/149 asks for an easier way

  my $q = shift;
  my $algebra = Attean->get_parser('SPARQL')->new(namespaces => $map)->parse($q); # base => $base,
  my $default_graphs = [$graph];
  my $plan = Attean::IDPQueryPlanner->new()->plan_for_algebra($algebra, $model, $default_graphs);
  my $mapper = Attean::TermMap->canonicalization_map->binding_mapper; # canonicalizes typed Attean::API::Literals
  my $iter = $plan->evaluate($model)->map($mapper);
  $iter
}

sub uniq_en_strings ($) {
  # in: iterator of Attean::API::Term
  # out: array of IRIs, or strings (have no lang), or langString "@en", skipping duplicates
  my $iter = shift;
  uniq (map $_->value,
        grep !$_->can("has_language") || !$_->has_language || $_->language =~ "^en",
        $iter->elements)
}

sub get_label ($$) {
  # get one label for a node
  my $iri = shift;     # the node whose labels we're fetching: ontology, class or property
  my $message = shift; # error message for the user
  my @labels = uniq_en_strings($model->objects($iri, [map IRI($_), @LABEL_PROPS]));
  my_warn "Found multiple labels for $message, using the first one: ".(join", ",@labels)
    if @labels > 1;
  @labels ? $labels[0] : undef # if any labels, return the 0-th one, else undef
}

sub get_descr ($) {
  # get all descriptions for a node
  my $iri = shift;  # the node whose descriptions we're fetching: ontology, class or property
  my @descr = uniq_en_strings($model->objects($iri, [map IRI($_), @DESCR_PROPS]));
  map {s{\. *$}{}} @descr; # remove trailing dot...
  join ". ", sort @descr; # ...because we add dot between values
}

sub one_value ($) {
  # return the value of the first (or only) element of iterator of Attean::API::Term
  my $term = shift->next;
  $term && $term->value
}

sub date_part ($) {
  my $dateTime = shift or return;
  $dateTime =~ s{T\d.*$}{}; # substitute: T followed by a digit and any chars; with empty
  $dateTime
}

# https://github.com/kasei/attean/issues/151
# Attean::IRI is not compatible with URI

sub iri ($) {
  # convert string or URI (returned by URI::NamespaceMap $MAP) to Attean::IRI
  my $uri = shift or return;
  Attean::IRI->new (value => ref($uri) ? $uri->as_string : $uri, lazy => 1)
}

sub uri ($) {
  my $iri = shift;
  URI->new (ref($iri) ? $iri->as_string : $iri);
}

sub IRI ($) {
  # Return Attean::IRI from prefixed name resolved through $MAP (the "service" namespace).
  my $pname = shift;
  my $iri = iri($MAP->uri($pname));
  $iri
}

sub iri_name($) {
  # given an IRI, return hash of 3 names:
  #  "gql" (GraphQL), "rdf" (RDF prefixed name), eventually "super" (gql+"Interface")
  my $iri = shift;
  $iri = $iri->as_string if ref($iri);
  return $iri_name{$iri} if $iri_name{$iri}; # memoization
  my $rdf = $map->abbreviate(uri($iri))
    or my_die("No suitable prefix for IRI $iri");
  my $gql = $rdf;
  $gql =~ s{^$vocab_prefix:}{};
  # PLATFORM-1625 Allow punctuation in local names and prefixes: replaces [-_.:] with "_" so we don't need to do it
  $gql_rdf{$gql} = $rdf;
  return $iri_name{$iri} = {gql=>$gql, rdf=>$rdf}
}

sub make_inherits($$) {
  # for each $class, pick its first superclass and make the %inherits matrix
  my ($classes, $no_classes) = @_;
  for my $class (@$classes) {
    # Ignore anonymous (blank node) super-classes
    my @inherits = map $_->as_string, grep $_->isa("Attean::IRI"),
      $model->objects ($class, IRI("rdfs:subClassOf"))->elements;
    $class = iri_name($class) and $class = $class->{gql} or next;
    @inherits = array_minus (@inherits, @$no_classes);
    @inherits = sort map $_->{gql}, grep $_, map iri_name($_), @inherits;
    $inherits{$class} = $inherits[0] if @inherits;
    my_warn("Found multiple superclasses for $class, using only the first one: ".
            join(", ",@inherits))
      if @inherits>1
  }
}

# TODO: once we implement concrete superclass, eliminate this function
sub make_super() {
  # make SOML statements to create dual pair "$concrete class - abstract $super interface"
  my %isSuper = reverse %inherits;
  for my $concrete (keys %isSuper) {
    my $super = $concrete."Interface";
    $super{$concrete} = $super;
    $soml{objects}{$super}{kind} = "abstract";
    $soml{objects}{$concrete}{type} = $gql_rdf{$concrete};
    $soml{objects}{$concrete}{inherits} = $super;
  }
}

sub lift_inherits () {
  # lift the %inherits relation to the abstract superclasses, if any
  while (my ($subClass,$superClass) = each %inherits) {
    $subClass   = $super{$subClass}   if $super{$subClass};
    $superClass = $super{$superClass} if $super{$superClass};
    $soml{objects}{$subClass}{inherits} = $superClass
  }
}

sub expand_union($); # quash "called too early to check prototype" because of recursive call
sub expand_union($) {
  # collect direct objects and union members, eg: schema:domainIncludes :x, :y, [owl:unionOf (:z :t)]
  my $iter = shift;
  my @objects;
  for my $obj ($iter->elements) {
    my $union = $model->objects($obj, IRI("owl:unionOf"))->next;
    push @objects,
      ($union ? expand_union($model->get_list(undef,$union)) : $obj)
  }
  @objects
}

sub map_range ($$) {
  # map a range of $pname to {kind, gql, rdf}
  # where kind is "datatype" or "class",
  # rdf is the prefixed name (applies only for "class")
  # gql is the prefixed name minus vocab_prefix
  my ($pname,$range) = @_;
  my $x = $MAP->abbreviate(uri($range));
  $x && $DATATYPES{$x} and return {kind=>"datatype", gql => $DATATYPES{$x}};
  $x && $NO_DATATYPES{$x} and do {my_warn("Prop $pname uses unsupported datatype $x, ignored"); return undef};
  my $y = iri_name($range);
  $y and return {kind => "class", gql => $y->{gql}, rdf => $y->{rdf}};
  return undef
}

sub map_ranges ($$) {
  my ($prop,$name) = @_;
  my @ranges = expand_union ($model->objects ($prop, [IRI("rdfs:range"), IRI("schema:rangeIncludes")]));
  sort {$a->{gql} cmp $b->{gql}}
    grep $_, map map_range($name,$_), @ranges
}

##### main

scalar(@ARGV) < 1 and usage(); # if there are no args, print usage() and die
load_ontologies(@ARGV);

# prefixes
while (my ($pfx,$iri) = $map->each_map) {
  $soml{prefixes}{$pfx} = $iri->as_string
};

# ontology metadata
if ($ontology_iri) {
  my $label = get_label ($ontology_iri,"ontology");
  $soml{label} = $label if $label;
  my @creators = uniq_en_strings($model->objects($ontology_iri, [map IRI($_), @CREATOR_PROPS]));
  $soml{creator} = join ", ", sort @creators if @creators;
  my $created = date_part (one_value($model->objects($ontology_iri, IRI("dct:created"))));
  $soml{created} = $created if $created;
  my $updated = date_part (one_value($model->objects($ontology_iri, IRI("dct:modified"))));
  $soml{updated} = $updated if $updated;
  my $versionInfo = one_value($model->objects($ontology_iri, IRI("owl:versionInfo")));
  $soml{versionInfo} = $versionInfo if $versionInfo;
}

# classes (objects)

# https://github.com/kasei/attean/issues/152: need to use uniq()
# Ignore anonymous (blank node) classes
my @classes = uniq (map $_->as_string, grep $_->isa("Attean::IRI"),
                    $model->subjects([map IRI($_), qw(rdf:type rdfs:Class owl:Class)])->elements);
# Undesirable classes. Map to as_string else array_minus may miss the same IRI instantiated from the ontology vs using IRI()
my @no_classes = map $_->as_string,
  ((map IRI($_), @NO_CLASSES),
   $model->subjects(IRI("rdf:type"), IRI("schema:DataType"))->elements);
@classes = array_minus (@classes, @no_classes);
for my $class (@classes) {
  $class = iri($class);
  my $iri_name = iri_name($class);
  my $name = $iri_name->{gql};
  my $rdf = $iri_name->{rdf};
  $soml{objects}{$name}{type} = $rdf if $name ne $rdf; # by default, "type: $name"
  my $label = get_label ($class, "class $rdf");
  $soml{objects}{$name}{label} = $label if $label;
  my $descr = get_descr ($class);
  $soml{objects}{$name}{descr} = $descr if $descr;
};

make_inherits(\@classes, \@no_classes);
make_super();
lift_inherits();

# properties
my @props = uniq (map $_->as_string,
                  $model->subjects (IRI("rdf:type"), [map IRI($_), @PROP_CLASSES]) ->elements);
my @no_props = map IRI($_)->as_string, @NO_PROPS;
@props = array_minus (@props, @no_props);
for my $prop (map iri($_), @props) {
  my $iri_name = iri_name($prop);
  my $name = $iri_name->{gql};
  my $rdf = $iri_name->{rdf};
  $soml{properties}{$name}{rdfProp} = $rdf if $name ne $rdf;
  my $label = get_label ($prop, "property $rdf");
  $soml{properties}{$name}{label} = $label if $label;
  my $descr = get_descr ($prop);
  $soml{properties}{$name}{descr} = $descr if $descr;

  # prop characteristics
  my $isObjectProp = $model->holds ($prop, IRI("rdf:type"), IRI("owl:ObjectProperty"));
  my $isDataProp   = $model->holds ($prop, IRI("rdf:type"), [IRI("owl:AnnotationProperty"), IRI("owl:DatatypeProperty")]);
  my $isSymmetric  = $model->holds ($prop, IRI("rdf:type"), IRI("owl:SymmetricProperty"));
  $soml{properties}{$name}{symmetric} = 1 if $isSymmetric;
  my $isFunctional = $model->holds ($prop, IRI("rdf:type"), IRI("owl:FunctionalProperty"));
  $soml{properties}{$name}{max} = "inf" unless $isFunctional;
  my $inverseOf = one_value ($model->objects ($prop, [IRI("owl:inverseOf"), IRI("schema:inverseOf")]));
  if ($inverseOf) { # emit bidirectionally
    $inverseOf = iri_name($inverseOf)->{gql};
    $soml{properties}{$name}{inverseOf} = $inverseOf;
    $soml{properties}{$inverseOf}{inverseOf} = $name; # hope and pray $inverseOf is defined as a prop
  };

  # domains
  my @domains = expand_union ($model->objects ($prop, [IRI("rdfs:domain"), IRI("schema:domainIncludes")]));
  for my $domain (@domains) {
    my $class = iri_name($domain);
    $class and $class = $class->{gql} or next;
    $class = $super{$class} if $super{$class};
    # fix for referenced classes that may not be defined in the ontology
    $soml{objects}{$class}{type} = iri_name($domain)->{rdf};
    $soml{objects}{$class}{props}{$name} = {};
  };

  # ranges
  my ($datatype, $class);
  my @ranges = map_ranges($prop,$name);
  if (my $range = $ranges[0]) {
    $datatype = $range->{kind} eq "datatype" && $range->{gql};
    $class = !$datatype && $range->{gql};
    my_warn("Found multiple ranges for prop $name, using only the first one: ".
            join(", ", map $_->{gql}, @ranges))
      if @ranges>1;
    # fix for referenced classes that may not be defined in the ontology
    $soml{objects}{$class}{type} = $range->{rdf} if $class;
    $isObjectProp && $datatype && $datatype ne "iri"
      and my_die("Prop $name is owl:ObjectProperty but has range datatype $datatype");
    $isDataProp && $class
      and my_die("Prop $name is owl:DatatypeProperty or owl:AnnotationProperty but has range class $class");
  };
  # defaults: "free-standing" URL vs string
  if (!$datatype && !$class) {
    if ($isObjectProp) {$class = "iri"} else {$datatype = "string"}
  };
  $class = $super{$class} if $class && $super{$class};
  $soml{properties}{$name}{range} = $datatype || $class;
  $soml{properties}{$name}{kind}  = $datatype ?  "literal" : "object";
};

# print YAML
use YAML; $YAML::UseHeader=0; print YAML::Dump(\%soml);
# use YAML::XS; print YAML::XS::Dump(\%soml); # faster for large files
# use YAML::PP; print YAML::PP::Dump(\%soml); # aims to support "YAML 1.2" and "YAML 1.1".
# use Data::YAML::Writer; Data::YAML::Writer->new->write(\%soml,*STDOUT);
# use YAML::Hobo; print YAML::Hobo::Dump(\%soml); # uses YAML::Tiny
# use YAML::Perl; print YAML::Perl::Dump(\%soml); # still alpha
# use YAML::Dump; print YAML::Dump(\%soml);

my_exit();
