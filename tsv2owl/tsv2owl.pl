#!perl -w
# See Makefile for examples.

use strict;
use Getopt::Std;
use Carp;                       # https://perldoc.perl.org/Carp
our ($opt_v, $opt_o, $opt_l);   # vocab, ontology, downgrade literals
our %MAP_LITERAL =              # from SOML literal ranges to rdf/xsd
  qw(langString            rdf:langString
     stringOrLangString    rdf:langString
     literal               rdf:Literal
     dateOrYearOrMonth     xsd:date
     dateOrTimeOrTimeStamp xsd:dateTimeStamp
  );
our %DOWNGRADE_LITERAL =        # further mapping if option "downgrade literals"
  qw(rdf:langString xsd:string
     rdf:Literal    xsd:string
   );
our %rdf_replaced;              # map from unmapped class name to final (replaced) RDF class: fill it as we go through the sheet
our (%inherits);                # map from unmapped class to array of its unmapped superclasses
our (%range);                   # map from mapped prop to array of its unmapped class ranges
our ($class,$rdf_class);        # current unmapped and rdf_replaced class, to which to attach the following properties
our $use_replacement;           # whether the last header col is "RDF replacement"
use DateTime;                   # now, ymd
our $HEADER = "Class/prop\tlabel\tInherits/range\tchar\tRDF\t(regex|pattern)\tdescr(\tRDF replacement)?";

sub rdf_name($) {
  my ($name) = @_;
  # Resolve $name to RDF by prepending $opt_v if needed
  $name =~ m{:} ? $name : # already is rdf name
    "$opt_v$name"; # prepend $opt_v as prefix
}

sub chars ($$$) {
  my ($chars,$prop,$rdf_class) = @_;
  # Process $chars (characteristics) of $prop attached to $rdf_class.
  # Chars are separated by commas. Handles:
  # - cardinalities (only min: 1, max: inf).
  # - inverseOf (prop with or without namespace)
  # - symmetric (only "true")
  # - subPropertyOf (only prop without namespace)
  # - transitiveOver (prop with or without namespace, can be multiple)
  # Ignored chars: kind (abstract), name, typeProp, search: {...}
  my ($min,$max,$inv) = ("","");
  $min = "owl:minCardinality $1" if          $chars =~ s{min: +(\d+),? ?}{}; # mandatory
  $max = "owl:maxCardinality $1" if          $chars =~ s{max: +(\d+),? ?}{};
  $max = "owl:maxCardinality 1"  if !$max && $chars !~ s{max: +inf,? ?}{}; # single-valued
  print "$rdf_class rdfs:subClassOf [a owl:Restriction; owl:onProperty $prop; $min; $max]."
    if $min || $max;
  # print "$prop a owl:FunctionalProperty." # single-valued: only works if all prop uses conform
  $chars =~ s{inverseOf: (\w+),? ?}{$inv = rdf_name($1); "owl:inverseOf $inv; "}e;
  $chars =~ s{symmetric: true,? ?}{a owl:SymmetricProperty; };
  $chars =~ s{subPropertyOf: (\w+),? ?}{rdfs:subPropertyOf :$1; };
  $chars =~ s{transitiveOver: ((\w+:)?\w+),? ?}{my $colon = $2 ? "" : ":"; "psys:transitiveOver $colon$1; "}ge;
  $chars =~ s{search: \{.*?\},? ?}{};
  print "$prop $chars.\n" if $chars
}

sub range_kind($$) {
  my ($range) = @_;
  # Compute kind (Datatype vs ObjectProperty) from range, prepend xsd: to range if needed
  my $kind;
  if ($range eq "iri") {
    $kind = "owl:ObjectProperty";
    $range = undef; # free URL: unbound range
  } elsif ($range =~ m{^[a-z][a-zA-Z]+$}) {
    $kind = "owl:DatatypeProperty";
    $range = $MAP_LITERAL{$range}       if exists $MAP_LITERAL{$range};
    $range = $DOWNGRADE_LITERAL{$range} if exists $DOWNGRADE_LITERAL{$range} && $opt_l;
    $range = "xsd:$range" unless $range =~ m{:};
    $rdf_replaced{$range} = $range;
  } else {
    $kind = "owl:ObjectProperty";
  };
  return ($range,$kind)
}

########## main

binmode(STDOUT); # output \n not \r\n
$\ = "\n"; # each print outputs a newline

getopts("v:o:l"); # -v and -o get argument, -l is just a flag
$opt_v ||= ":";

$_ = <>; # get first row
m{$HEADER} or die << "EOF";
expect header: |$HEADER|
found  header: |$_|
Did you remember to make the gsheet public?

EOF
$use_replacement = m{RDF replacement};
print "\n"; # extra newline, to better separate from preamble

while (<>) {
  chomp;
  my ($name,$label,$range,$char,$rdf,$regex,$descr,$replacement) = split(/\t/, $_);
  $replacement = $use_replacement && $replacement; # only use the last col if it's in the header

  if (!$name) {next};                              # blank line
  if ($name =~ m{^\s*#}) {print "\n$name"; next};  # comment; will be lost by riot reformatting. Oh well.
  $label ||= $name;
  $label = qq{rdfs:label "$label"};
  $descr &&= qq{rdfs:comment "$descr"};

  if ($name =~ m{^([a-z]+:)?[A-Z]}) { # Uppercase: Class
    $class = $name;
    if ($replacement) {
      $replacement = $replacement eq "none" ? "" : rdf_name($replacement);
      $rdf_class = $rdf_replaced{$class} = $replacement
    } else {
      $rdf_class = $rdf_replaced{$class} = $rdf || rdf_name($class);
    };
    next unless $rdf_class;
    if ($range) {
      # TODO: not sure why I allow multiple superclasses, they are not supported by SOML but are present in STRAT-ontology sheet
      $inherits{$class} = [split/,/, $range]
    };
    print "$rdf_class a rdfs:Class; $label; $descr.";
    print "$rdf_class rdfs:isDefinedBy $opt_o." if $opt_o
  } else {                            # lowercase: prop
    my $prop = $rdf || rdf_name($name);
    die "line $.: do you really need RDF replacement for $prop? Not supported yet\n"
      if $replacement;
    warn "line $.: $class has $prop but replacement=none: ignoring this prop\n" and next
      if !$rdf_class;
    next if $char =~ m{inverseAlias}; # virtual property, don't emit in RDF
    my $kind;
    ($range,$kind) = range_kind($range,$kind);
    if ($range) {
      # remember the range for later printing since that class may not be rdf_replaced yet
      $range{$prop} ||= []; # intialize empty array of ranges for that prop
      push @{$range{$prop}}, $range
    };
    print "$prop a $kind; $label; $descr; schema:domainIncludes $rdf_class.";
    print "$prop rdfs:isDefinedBy $opt_o." if $opt_o;
    chars($char,$prop,$rdf_class);
  };
};

print "\n## Class hierarchy";
while (my ($sub,$super) = each %inherits) {
  $sub = $rdf_replaced{$sub} or croak "$sub has no rdf_replaced";
  map {croak "$_ has no rdf_replaced" unless defined $rdf_replaced{$_}} @$super;
  $super = join ',', grep $_, map $rdf_replaced{$_}, @$super;
  print "$sub rdfs:subClassOf $super." if $super; # at least one non-empty superclass
};
print "\n## Property ranges";
while (my ($prop,$range) = each %range) {
  map {croak "Prop $prop: range $_ has no rdf_replaced" unless defined $rdf_replaced{$_}} @$range;
  $range = join ',', grep $_, map $rdf_replaced{$_}, @$range;
  print "$prop schema:rangeIncludes $range." if $range; # at least one non-empty range
};
# print ontology updated datestamp
print "$opt_o dct:updated '", DateTime->now->ymd, "'^^xsd:date."
  if $opt_o;

