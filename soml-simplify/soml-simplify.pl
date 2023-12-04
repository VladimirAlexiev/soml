#!/usr/bin/perl

use strict;
use warnings;
use YAML::PP;

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
  $simplified->{$object}{ISA} = $inherits if $inherits;
  for my $p (keys %$props) {
    my $prop     = $props->{$p} // {};        # global prop definition
    my $property = $properties->{$p} // {};   # global prop definition
    my $range    = $prop->{range} // $property->{range} // "string";
    my $max      = $prop->{max} // $property->{max} // 1;
    $simplified->{$object}{$p} = $max eq 'inf' || $max > 1 ? "[$range]" : $range;
  }
}

# Output the simplified schema
print $yaml->dump($simplified);
