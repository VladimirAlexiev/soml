#!perl -wn
# curl -s "https://docs.google.com/spreadsheets/d/1_-bn9Y-9rtysnvKiVus6BkFKXqHhiV4vCjYeiRmb6XU/export?format=tsv" | perl tsv2soml.pl | cat CG-preamble.yaml - > CG.yaml
# Also writes out soml-map.tsv with cols "class, prop (optional), rdf" to map from SOML names to RDF classes/props.
# For props without rdf, uses the rdf name from the shared first occurrence of the same prop name
# Options:
#  -p: don't emit "pattern/regex"
#  -l: downgrade Literals (stringOrLangString, langString -> string, dateOrYearOrMonth -> date)

use strict;
our ($opt_p, $opt_l);
our %DOWNGRADE_LITERAL = (stringOrLangString=>"string", langString=>"string", dateOrYearOrMonth=>"date");
our (%properties, %propUse, %map_class, %map_class_prop, %map_prop, $class);
use DateTime; # now, ymd
our $HEADER = "Class/prop\tlabel\tInherits/range\tchar\tRDF\t(pattern|regex)\tdescr";
our $use_regex; # whether to use "regex:" or "pattern:"
use Getopt::Std;

BEGIN {
  binmode(STDOUT); # output \n not \r\n
  getopts("pl");
  print "\nobjects:\n"
}

sub chars ($@) {
  # Format an array of @chars (characteristics): either {...} separated by commas, or multiline indented by $spaces
  my $spaces = shift;
  my @chars = grep($_, @_); # filter out empty characteristics
  $spaces ? join("\n$spaces", "", @chars) : # multiline
    join("", " {", join(", ", @chars), "}") # inline
}

sub char ($$) {
  # Return $char (characteristic): either as is (comma-separted), or multiline indented by spaces
  my $spaces = shift;
  my $char = shift;
  $char =~ s{, ?}{\n$spaces}g if $spaces;
  $char
}

chomp;
if ($. == 1) {
  m{$HEADER} or die "expect header: |", $HEADER, "|\nfound  header: |$_|\nDid you remember to make the gsheet public?\n";
  $use_regex = m{\tregex\t}; # else use "pattern:"
  next
}

my ($name,$label,$range,$char,$rdf,$pattern,$descr) = split/\t/;
if (!$name) {next};
if ($name =~ m{^\s*# }) {print "\n$name\n"; next}; # print "# HEADER" first cell surrounded by newlines
if ($name =~ m{^\s*#}) {next}; # skip "#commented out" line
$label &&= qq{label: "$label"};

$descr &&= qq{descr: "$descr"}; # TODO handle newlines in $descr:
# Instead of `/export?format=tsv` use `/gviz/tq?tqx=out:csv&headers=0`
# Use a proper CSV parser: the above quotes each field and doesn't support TSV
# Use """ or "\n" or better the YAML | notation

if ($name =~ m{^([a-z]+:)?[A-Z]}) {
  # Uppercase: Class
  $class = $name;
  if ($range) {
    # inherit RDF type and props from parent class
    $map_class{$class} = $map_class{$range} || "";
    while (my ($prop,$rdf) = each %{$map_class_prop{$range}}) {
      $map_class_prop{$class}{$prop} = $rdf
    }
  }
  $map_class{$name} = $rdf if $rdf
    && $rdf =~ m{:} # discard nomenclatures: organization/status, position
    && $rdf !~ m{[,.]}; # discard gn:P.PPL, gn:P.PPLC
  $range &&= qq{inherits: $range};
  $rdf &&= qq{type: [$rdf]};
  $pattern = undef if $opt_p;
  $pattern &&= ($use_regex ? "regex" : "pattern") . ": '" . $pattern . "'";
  my $spaces = " "x4;
  print "  $name:", chars ($spaces, $label, $range, char($spaces,$char), $rdf, $pattern, $descr, "props:"),"\n";
  # we always print "props:" even when the class has none, SOML allows that
} else {
  # lowercase: prop
  $map_prop{$name} //= $rdf;
  $map_class_prop{$class}{$name} = $rdf || $map_prop{$name} unless $char =~ m{inverseAlias};
  $range = $DOWNGRADE_LITERAL{$range} if $opt_l && $range && exists $DOWNGRADE_LITERAL{$range};
  $range &&= qq{range: $range};
  $rdf &&= qq{rdfProp: $rdf};
  $pattern = undef if $opt_p;
  $pattern &&= qq{pattern: '$pattern'};
  # if $descr then use identation and newlines, else use inline
  my $spaces1 = $descr && " "x8;
  my $spaces2 = $descr && " "x4;
  my $property1 = "  $name:" . chars ($spaces1, $label, $range, char($spaces1,$char), $rdf, $pattern, $descr) . "\n";
  my $property2 = "  $name:" . chars ($spaces2, $label, $range, char($spaces2,$char), $rdf, $pattern, $descr) . "\n";
  print "    $property1";
  $properties{$name} //= $property2;
  $propUse{$name}++;
}

END {
  # print reused props and updated datestamp
  my @props = grep {$propUse{$_} > 1} sort keys %properties;
  print "\n", "properties: # reused props\n", join("", @properties{@props}) if @props;
  print "\n", "updated:     ", DateTime->now->ymd, "\n";
  # print map of classes and props to rdf
  open (MAP, ">soml-map.tsv");
  print MAP "class\tprop\trdf\t-*- tab-width: 32 -*-\n";
  map {print  MAP "$_\t\t$map_class{$_}\n"} sort keys %map_class;
  map {
    my $c = $_;
    map {print  MAP "$c\t$_\t$map_class_prop{$c}{$_}\n"} sort keys %{$map_class_prop{$c}};
  } sort keys %map_class_prop;
  close (MAP);
}
