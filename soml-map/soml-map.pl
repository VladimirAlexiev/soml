#!perl -wp
# perl soml-map.pl < file.(tarql|ttl) > file-mapped.(tarql|ttl)
# First run soml-gen.pl to create soml-map.tsv

our (%map_class, %map_prop_class, $class);

BEGIN {
  open (MAP, "soml-map.tsv") or die "First run soml-gen.pl to create soml-map.tsv\n";
  <MAP>; # skip header
  while (<MAP>) {
    chomp;
    my ($class,$prop,$rdf) = split /\t/;
    if ($prop) {
      $map_class_prop{$class}{$prop} = $rdf
    } else {
      $map_class{$class} = $rdf
    }
  };
  close(MAP)
}

s{(^| ):(\w+)}{
  my $space = $1;
  my $name = $2;
  my $isClass = $name eq ucfirst($name);
  $class = $name if $isClass;
  my $rdf = $isClass ? $map_class{$class} :
    $class ?  $map_class_prop{$class}{$name} :
    (warn("class not yet set at $.\n"), "");
  $rdf or warn "$name not mapped at $.\n";
  $space . ($rdf || ":$name")
}ge;
