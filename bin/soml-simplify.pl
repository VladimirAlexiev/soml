#!perl
use strict;
use warnings;
use YAML::PP;

sub graphql_name($) {
  # replace punctuation in RDF classes and props (`:.`) with a GraphQL char (`_`)
  my $name = shift;
  $name =~ tr{:.}{_};
  $name
}

# Load YAML file
my $yaml = YAML::PP->new (indent => 2, header => 0);
my $data = $yaml->load_file(\*STDIN);
my $properties = $data->{properties} // {};
my $objects    = $data->{objects} // {};
my $simplified = {};

# Simplify the data
for my $object (keys %$objects) {
  my $props    = $objects->{$object}{props} // {};
  my $inherits = $objects->{$object}{inherits};
  $simplified->{graphql_name($object)}{ISA} = graphql_name($inherits) if $inherits;
  for my $p (keys %$props) {
    my $prop     = $props->{$p} // {};        # per-object prop definition
    my $property = $properties->{$p} // {};   # global prop definition
    my $range    = graphql_name($prop->{range} // $property->{range} // "string");
    my $max      = $prop->{max} // $property->{max} // 1;
    $simplified->{graphql_name($object)}{graphql_name($p)} = $max eq 'inf' || $max > 1 ? "[$range]" : $range;
  }
}

# Output the simplified schema
print $yaml->dump($simplified);
