#!perl -w

use OptArgs;
opt overview =>
  (
   isa     => 'Bool',
   alias   => 'o',
   comment => 'omit attributes',
  );
my $opt = optargs;

# Class emoji (as suggested by GPT-4, then I added more starting with "basketball")
our @default_emoji = qw
(
  earth_americas
  file_folder
  hammer_and_wrench
  wrench
  link
  link
  label
  globe_with_meridians
  book
  books
  triangular_ruler
  basketball
  football
  rugby_football
  volleyball
  house
  office
  hospital
  atm
  hotel
  convenience_store
);

# Datatype emoji.
# Datatypes: https://platform.ontotext.com/semantic-objects/soml/datatypes.html
our %datatype_emoji = qw
(
  enum                  book
  boolean               ballot_box_with_check
  iri                   link
  string                spiral_notepad
  literal               spiral_notepad
  langString            spiral_notepad
  stringOrLangString    spiral_notepad
  int                   1234
  long                  1234
  short                 1234
  byte                  1234
  unsignedLong          1234
  unsignedInt           1234
  unsignedShort         1234
  unsignedByte          1234
  integer               1234
  positiveInteger       1234
  nonPositiveInteger    1234
  negativeInteger       1234
  nonNegativeInteger    1234
  double                eight_spoked_asterisk
  decimal               eight_spoked_asterisk
  negativeFloat         eight_spoked_asterisk
  nonNegativeFloat      eight_spoked_asterisk
  positiveFloat         eight_spoked_asterisk
  nonPositiveFloat      eight_spoked_asterisk
  dateTimeStamp         calendar
  dateTime              calendar
  time                  calendar
  date                  calendar
  year                  calendar
  yearMonth             calendar
  dateOrYearOrMonth     calendar
  duration              date
  dayTimeDuration       date
  yearMonthDuration     date
);

use YAML;
local $/ = undef;
our ($soml) = Load(<STDIN>);
our $enums = $soml->{types};
our $objects = $soml->{objects};
object_rank();
object_emoji();
attr_enum_cardinality();
orient_rels();

our $diagram = "";
$diagram .= header_str();
$diagram .= objects_str();
$diagram .= relations_str();
$diagram .= footer_str();
print $diagram;
# print_plantuml_url(); # buggy

########## subs

sub header_str {
  # return PlantUML header
  << 'EOF';
@startuml
hide empty members
hide circle
left to right direction
skinparam nodesep 50

EOF
};

sub footer_str {
  # return PlantUML footer
  << 'EOF';
@enduml
EOF
};

sub object_rank {
  # initialize {diagram}{rank} with defaults as needed
  my $default_rank = 1000;
  for my $obj (sort keys %$objects) {
    $objects->{$obj}{diagram}{rank} //= $default_rank++;
  }
}

sub object_emoji {
  # initialize {diagram}{emoji} with defaults as needed
  for my $obj (sort keys %$objects) {
  $objects->{$obj}{diagram}{emoji} //= shift @default_emoji
    or die "too many classes without emoji: default_emoji not long enough\n";
  }
}

sub attr_enum_cardinality {
  # For each {props}: fill out {isAttr}, {isEnum}, {cardinality}
  while (my ($obj,$object) = each %$objects) {
    while (my ($prop,$property) = each %{$object->{props}}) {
      my $range = $property->{range} //= "string";
      $property->{isAttr} = $property->{isEnum} = exists $enums->{$range};
      $property->{isAttr} ||= $range =~ m{^[a-z][^:]+$}; # datatype starts with lowercase, has no namespace
      $property->{min} //= "0";
      $property->{max} //= "1";
      $property->{max} = "*" if $property->{max} eq "inf";
      $property->{cardinality} = qq{$property->{min}..$property->{max}};
    }
  }
};

sub objects_str {
  # return string representing objects (classes), and optionally their attributes
  my $str = "";
  for my $obj (sort {$objects->{$a}{diagram}{rank} <=> $objects->{$b}{diagram}{rank}}
               keys %$objects) {
    my $object = $objects->{$obj};
    $str .= qq{class "<:$object->{diagram}{emoji}:> $obj" as $obj};
    unless ($opt->{overview}) {
      # print attributes
      my $has_attr = 0;
      for my $attr (sort keys %{$object->{props}}) {
        my $attribute = $object->{props}{$attr};
        next unless $attribute->{isAttr};
        my $range = $attribute->{range};
        my $datatype = $attribute->{isEnum} ? "enum" : $range;
        my $emoji = $datatype_emoji{$datatype} or die "Don't know emoji for datatype $datatype\n";
        # creole table: https://plantuml.com/creole#51c45b795d5d18a3 with transparent border and background
        $str .= " {\n<#transparent,#transparent>" if !$has_attr++;
        $str .= "|<:$emoji:>|$attr| $range| $attribute->{cardinality}|\n";
      };
      $str .= "}\n" if $has_attr;
    };
    $str .= "\n";
  };
  $str;
};

sub orient_rels {
  # Iterate objects by rank and compute for each relation obj.rel->obj2,
  # depending on the sign and magnitude of difference: obj.rank - obj2.rank
  # - {isInverted} if sign is positive
  # - $dir: "r" (going down because of "left to right direction") if small then else "d" (going right)
  # - {direction}: "-$dir->" for normal, "<-$dir-" for isInverted, "-$dir- " for pair of inverses
  # - {isDeleted} for the recessive relation in a pair of inverses (inverseOf or inverseAlias)
  # - {inverse} to hold the name of the recessive relation in a pair of inverses
  # - {cardinality2} to hold the inverse cardinality
  while (my ($obj,$object) = each %$objects) {
    while (my ($rel, $relation) = each %{$object->{props}}) {
      next if $relation->{isAttr} || $relation->{isDeleted} || $relation->{isInverted};
      my $obj2 = $relation->{range};
      my $object2 = $objects->{$obj2};
      my $rank_diff = $object->{diagram}{rank} - $object2->{diagram}{rank};
      my $dir = 0 < abs($rank_diff) && abs($rank_diff) < 1 ? "r" : "d";
      my ($rel2,$relation2); # inverse relation, if any
      if ($rel2 = $relation->{inverseOf} || $relation->{inverseAlias}) {
        my $err = "$obj.$rel has declared inverse $obj2.$rel2 but that";
        $relation2 = $object2->{props}{$rel2}
          or die "$err doesn't exist\n";
        $relation2->{range} eq $obj
          or die "$err points to $relation2->{range}\n";
      };
      if ($rank_diff <= 0) { # normal case
        if ($rel2) {
          $relation->{inverse} = $rel2;
          $relation->{cardinality2} = $relation2->{cardinality};
          $relation->{direction} = "-$dir- ";
          $relation2->{isDeleted} = 1;
        } else {
          $relation->{direction} = "-$dir->"
        }
      } else { # inverted case
        $relation->{isInverted} = 1;
        if ($rel2) {
          $relation2->{inverse} = $rel;
          $relation2->{cardinality2} = $relation->{cardinality};
          $relation2->{direction} = "-$dir- ";
          $relation->{isDeleted} = 1;
        } else {
          $relation->{direction} = "<-$dir-"
        };
      }
    }
  }
};

sub relations_str {
  # return all relations
  my $str = "";
  for my $obj (sort {$objects->{$a}{diagram}{rank} <=> $objects->{$b}{diagram}{rank}
                       || $a cmp $b} # sort by rank, else alphabetically
               keys %$objects) {
    my $object = $objects->{$obj};
    while (my ($rel, $relation) = each %{$object->{props}}) {
      next if $relation->{isAttr} || $relation->{isDeleted};
      my $obj_str  = sprintf "%-26s", $obj;
      my $obj2_str = sprintf "%-26s", $relation->{range};
      my $rel2 = $relation->{inverse};
      my $card = $relation->{cardinality};
      my $card2 = $relation->{cardinality2};
      my $dir = $relation->{direction};
      if ($relation->{isInverted}) {
        ($obj_str, $obj2_str) = ($obj2_str, $obj_str);
        ($rel, $rel2) = ($rel2, $rel) if $rel2;
        ($card, $card2) = ($card2, $card) if $card2;
      };
      $rel_str = $rel2 ? "$rel\\n $rel2" : $rel;
      $str .= $obj_str;
      $str .= $rel2 ? qq{ "$card2" } : "        ";
      $str .= qq{$dir "$card" $obj2_str : $rel_str\n}
    }
  };
  $str
};

__END__

# TODO: buggy: https://rt.cpan.org/Ticket/Display.html?id=148220
sub print_plantuml_url {
  use UML::PlantUML::Encoder qw(encode_p); # https://metacpan.org/pod/UML::PlantUML::Encoder
  print STDERR "diagram:\n  ",
    $opt->{overview} ? "overview" : "full", ": ",
    "http://www.plantuml.com/plantuml/svg/", encode_p($diagram), "\n";
}
