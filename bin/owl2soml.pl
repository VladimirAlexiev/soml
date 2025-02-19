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
use Getopt::Long; # https://metacpan.org/pod/Getopt::Long

our $store = Attean->get_store('Memory')->new();
our $model = Attean::MutableQuadModel->new(store => $store);
our $graph = Attean::IRI->new('http://example.org/');
our $ontology_iri;                     # as Attean::IRI
our $ontology;                         # $ontology_iri as string
our $vocab_iri;                        # vocab namespace as Attean::IRI
our $vocab_prefix;                     # vocab prefix as string
our $soml_id;                          # -id: SOML id
our $soml_label;                       # -label: SOML label
our $super_opt;                        # -super: whether to generate X and XInterface
our $string_opt;                       # -string: how to handle langString, stringOrLangString, string
our $lang_opt;                         # -lang: lang spec
our $shorten_opt;                      # -shorten: shorten prop names
our %name_char;                        # -name: hash of name props
our $map   = URI::NamespaceMap->new(); # prefixes in loaded ontologies
our $MAP   = URI::NamespaceMap->new    # fixed prefixes used in mapping ("service" namespace)
  ({so     => "http://www.ontotext.com/semantic-object/",
    cims   => "http://iec.ch/TC57/1999/rdf-schema-extensions-19990926#",
    cim    => "http://iec.ch/TC57/2013/CIM-schema-cim16#",
    dbd    => "http://dbpedia.org/datatype/",
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
our @NO_CLASSES = qw(owl:Thing owl:Nothing schema:DataType);
our @NO_PROPS = qw(owl:topObjectProperty owl:bottomObjectProperty owl:topDataProperty owl:bottomDataProperty);
our @LABEL_PROPS = qw(rdfs:label skos:prefLabel dc:title dct:title);
our @DESCR_PROPS = qw(rdfs:comment skos:definition skos:description skos:scopeNote dc:description dct:description);
our @CREATOR_PROPS = qw(dc:creator dct:creator); # dc:contributor dct:contributor
our %DATATYPES =
  (# XSD datatypes
   "xsd:string"             => "string",
   "xsd:double"             => "double",
   "xsd:float"              => "double",
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
   # unbound resources
   "rdfs:Resource"          => "iri",
   "xsd:anyURI"             => "iri",
   # Schema datatypes
   "schema:Boolean"         => "boolean",
   "schema:Date"            => "date",
   "schema:DateTime"        => "dateTime",
   "schema:Float"           => "double",
   "schema:Integer"         => "integer",
   "schema:Number"          => "decimal",
   "schema:Time"            => "time",
   "schema:URL"             => "iri",
   # domain-specific datatypes
   ## FIBO
   "fibo-fnd-dt-fd:CombinedDateTime" => "dateOrYearOrMonth",
   ## CIM primitive
   "cim:Boolean"  => "boolean",
   "cim:Date"     => "date",
   "cim:DateTime" => "dateTime",
   "cim:Decimal"  => "decimal",  # infinite precision
   "cim:Float"    => "double",   # XSD "double" maps to graphql "float"; graphql has "single" as extension (non-primitive)
   "cim:Integer"  => "int",      # or maybe "integer" for infinite precision?
   "cim:String"   => "string",
   ## CIM non-primitive
   "cim:ActivePower"                          => "double",   # cim:Float
   "cim:ActivePowerPerCurrentFlow"            => "double",   # cim:Float
   "cim:ActivePowerPerFrequency"              => "double",   # cim:Float
   "cim:AngleDegrees"                         => "double",   # cim:Float
   "cim:AngleRadians"                         => "double",   # cim:Float
   "cim:ApparentPower"                        => "double",   # cim:Float
   "cim:Area"                                 => "double",   # cim:Float
   "cim:Capacitance"                          => "double",   # cim:Float
   "cim:CapacitancePerLength"                 => "double",   # cim:Float
   "cim:Conductance"                          => "double",   # cim:Float
   "cim:CurrentFlow"                          => "double",   # cim:Float
   "cim:Frequency"                            => "double",   # cim:Float
   "cim:Inductance"                           => "double",   # cim:Float
   "cim:InductancePerLength"                  => "double",   # cim:Float
   "cim:Length"                               => "double",   # cim:Float
   "cim:Money"                                => "decimal",  # cim:Decimal
   "cim:PerCent"                              => "double",   # cim:Float
   "cim:PU"                                   => "double",   # cim:Float
   "cim:Reactance"                            => "double",   # cim:Float
   "cim:ReactivePower"                        => "double",   # cim:Float
   "cim:Resistance"                           => "double",   # cim:Float
   "cim:ResistancePerLength"                  => "double",   # cim:Float
   "cim:RotationSpeed"                        => "double",   # cim:Float
   "cim:Seconds"                              => "double",   # cim:Float
   "cim:Simple_Float"                         => "double",   # cim:Float
   "cim:Susceptance"                          => "double",   # cim:Float
   "cim:Temperature"                          => "double",   # cim:Float
   "cim:Voltage"                              => "double",   # cim:Float
   "cim:VoltagePerReactivePower"              => "double",   # cim:Float
   "cim:VolumeFlowRate"                       => "double",   # cim:Float
   ## DBpedia Datatypes
   "dbd:acre"                                 => "decimal",
   "dbd:afghanAfghani"                        => "decimal",
   "dbd:albanianLek"                          => "decimal",
   "dbd:algerianDinar"                        => "decimal",
   "dbd:ampere"                               => "decimal",
   "dbd:angolanKwanza"                        => "decimal",
   "dbd:argentinePeso"                        => "decimal",
   "dbd:armenianDram"                         => "decimal",
   "dbd:arubanGuilder"                        => "decimal",
   "dbd:astronomicalUnit"                     => "decimal",
   "dbd:australianDollar"                     => "decimal",
   "dbd:azerbaijaniManat"                     => "decimal",
   "dbd:bahamianDollar"                       => "decimal",
   "dbd:bahrainiDinar"                        => "decimal",
   "dbd:bangladeshiTaka"                      => "decimal",
   "dbd:bar"                                  => "decimal",
   "dbd:barbadosDollar"                       => "decimal",
   "dbd:belarussianRuble"                     => "decimal",
   "dbd:belizeDollar"                         => "decimal",
   "dbd:bermudianDollar"                      => "decimal",
   "dbd:bhutaneseNgultrum"                    => "decimal",
   "dbd:bit"                                  => "decimal",
   "dbd:bolivianBoliviano"                    => "decimal",
   "dbd:bosniaAndHerzegovinaConvertibleMarks" => "decimal",
   "dbd:botswanaPula"                         => "decimal",
   "dbd:brakeHorsepower"                      => "decimal",
   "dbd:brazilianReal"                        => "decimal",
   "dbd:bruneiDollar"                         => "decimal",
   "dbd:bulgarianLev"                         => "decimal",
   "dbd:burundianFranc"                       => "decimal",
   "dbd:byte"                                 => "decimal",
   "dbd:calorie"                              => "decimal",
   "dbd:cambodianRiel"                        => "decimal",
   "dbd:canadianDollar"                       => "decimal",
   "dbd:capeVerdeEscudo"                      => "decimal",
   "dbd:carat"                                => "decimal",
   "dbd:caymanIslandsDollar"                  => "decimal",
   "dbd:centilitre"                           => "decimal",
   "dbd:centimetre"                           => "decimal",
   "dbd:centralAfricanCfaFranc"               => "decimal",
   "dbd:cfpFranc"                             => "decimal",
   "dbd:chain"                                => "decimal",
   "dbd:chileanPeso"                          => "decimal",
   "dbd:colombianPeso"                        => "decimal",
   "dbd:comorianFranc"                        => "decimal",
   "dbd:congoleseFranc"                       => "decimal",
   "dbd:costaRicanColon"                      => "decimal",
   "dbd:croatianKuna"                         => "decimal",
   "dbd:cubanPeso"                            => "decimal",
   "dbd:cubicCentimetre"                      => "decimal",
   "dbd:cubicDecametre"                       => "decimal",
   "dbd:cubicDecimetre"                       => "decimal",
   "dbd:cubicFeetPerSecond"                   => "decimal",
   "dbd:cubicFeetPerYear"                     => "decimal",
   "dbd:cubicFoot"                            => "decimal",
   "dbd:cubicHectometre"                      => "decimal",
   "dbd:cubicInch"                            => "decimal",
   "dbd:cubicKilometre"                       => "decimal",
   "dbd:cubicMetre"                           => "decimal",
   "dbd:cubicMetrePerSecond"                  => "decimal",
   "dbd:cubicMetrePerYear"                    => "decimal",
   "dbd:cubicMile"                            => "decimal",
   "dbd:cubicMillimetre"                      => "decimal",
   "dbd:cubicYard"                            => "decimal",
   "dbd:czechKoruna"                          => "decimal",
   "dbd:danishKrone"                          => "decimal",
   "dbd:day"                                  => "decimal",
   "dbd:decametre"                            => "decimal",
   "dbd:decibar"                              => "decimal",
   "dbd:decilitre"                            => "decimal",
   "dbd:decimetre"                            => "decimal",
   "dbd:degreeCelsius"                        => "decimal",
   "dbd:degreeFahrenheit"                     => "decimal",
   "dbd:degreeRankine"                        => "decimal",
   "dbd:djiboutianFranc"                      => "decimal",
   "dbd:dominicanPeso"                        => "decimal",
   "dbd:eastCaribbeanDollar"                  => "decimal",
   "dbd:egyptianPound"                        => "decimal",
   "dbd:engineConfiguration"                  => "string",
   "dbd:erg"                                  => "decimal",
   "dbd:eritreanNakfa"                        => "decimal",
   "dbd:estonianKroon"                        => "decimal",
   "dbd:ethiopianBirr"                        => "decimal",
   "dbd:euro"                                 => "decimal",
   "dbd:falklandIslandsPound"                 => "decimal",
   "dbd:fathom"                               => "decimal",
   "dbd:fijiDollar"                           => "decimal",
   "dbd:foot"                                 => "decimal",
   "dbd:footPerMinute"                        => "decimal",
   "dbd:footPerSecond"                        => "decimal",
   "dbd:footPound"                            => "decimal",
   "dbd:fuelType"                             => "string",
   "dbd:furlong"                              => "decimal",
   "dbd:gambianDalasi"                        => "decimal",
   "dbd:georgianLari"                         => "decimal",
   "dbd:ghanaianCedi"                         => "decimal",
   "dbd:gibraltarPound"                       => "decimal",
   "dbd:gigabyte"                             => "decimal",
   "dbd:gigahertz"                            => "decimal",
   "dbd:gigalitre"                            => "decimal",
   "dbd:gigametre"                            => "decimal",
   "dbd:giganewton"                           => "decimal",
   "dbd:gigawatt"                             => "decimal",
   "dbd:gigawattHour"                         => "decimal",
   "dbd:grain"                                => "decimal",
   "dbd:gram"                                 => "decimal",
   "dbd:gramForce"                            => "decimal",
   "dbd:gramPerCubicCentimetre"               => "decimal",
   "dbd:gramPerKilometre"                     => "decimal",
   "dbd:gramPerMillilitre"                    => "decimal",
   "dbd:guatemalanQuetzal"                    => "decimal",
   "dbd:guineaFranc"                          => "decimal",
   "dbd:guyanaDollar"                         => "decimal",
   "dbd:haitiGourde"                          => "decimal",
   "dbd:hand"                                 => "decimal",
   "dbd:hectare"                              => "decimal",
   "dbd:hectolitre"                           => "decimal",
   "dbd:hectometre"                           => "decimal",
   "dbd:hectopascal"                          => "decimal",
   "dbd:hertz"                                => "decimal",
   "dbd:honduranLempira"                      => "decimal",
   "dbd:hongKongDollar"                       => "decimal",
   "dbd:horsepower"                           => "decimal",
   "dbd:hour"                                 => "decimal",
   "dbd:hungarianForint"                      => "decimal",
   "dbd:icelandKrona"                         => "decimal",
   "dbd:imperialBarrel"                       => "decimal",
   "dbd:imperialBarrelOil"                    => "decimal",
   "dbd:imperialGallon"                       => "decimal",
   "dbd:inch"                                 => "decimal",
   "dbd:inchPound"                            => "decimal",
   "dbd:indianRupee"                          => "decimal",
   "dbd:indonesianRupiah"                     => "decimal",
   "dbd:inhabitantsPerSquareKilometre"        => "decimal",
   "dbd:inhabitantsPerSquareMile"             => "decimal",
   "dbd:iranianRial"                          => "decimal",
   "dbd:iraqiDinar"                           => "decimal",
   "dbd:israeliNewSheqel"                     => "decimal",
   "dbd:jamaicanDollar"                       => "decimal",
   "dbd:japaneseYen"                          => "decimal",
   "dbd:jordanianDinar"                       => "decimal",
   "dbd:joule"                                => "decimal",
   "dbd:kazakhstaniTenge"                     => "decimal",
   "dbd:kelvin"                               => "decimal",
   "dbd:kenyanShilling"                       => "decimal",
   "dbd:kiloampere"                           => "decimal",
   "dbd:kilobit"                              => "decimal",
   "dbd:kilobyte"                             => "decimal",
   "dbd:kilocalorie"                          => "decimal",
   "dbd:kilogram"                             => "decimal",
   "dbd:kilogramForce"                        => "decimal",
   "dbd:kilogramPerCubicMetre"                => "decimal",
   "dbd:kilogramPerLitre"                     => "decimal",
   "dbd:kilohertz"                            => "decimal",
   "dbd:kilojoule"                            => "decimal",
   "dbd:kilolightYear"                        => "decimal",
   "dbd:kilolitre"                            => "decimal",
   "dbd:kilometre"                            => "decimal",
   "dbd:kilometrePerHour"                     => "decimal",
   "dbd:kilometrePerSecond"                   => "decimal",
   "dbd:kilometresPerLitre"                   => "decimal",
   "dbd:kilonewton"                           => "decimal",
   "dbd:kilopascal"                           => "decimal",
   "dbd:kilopond"                             => "decimal",
   "dbd:kilovolt"                             => "decimal",
   "dbd:kilowatt"                             => "decimal",
   "dbd:kilowattHour"                         => "decimal",
   "dbd:knot"                                 => "decimal",
   "dbd:kuwaitiDinar"                         => "decimal",
   "dbd:kyrgyzstaniSom"                       => "decimal",
   "dbd:laoKip"                               => "decimal",
   "dbd:latvianLats"                          => "decimal",
   "dbd:lebanesePound"                        => "decimal",
   "dbd:lesothoLoti"                          => "decimal",
   "dbd:liberianDollar"                       => "decimal",
   "dbd:libyanDinar"                          => "decimal",
   "dbd:lightYear"                            => "decimal",
   "dbd:lithuanianLitas"                      => "decimal",
   "dbd:litre"                                => "decimal",
   "dbd:macanesePataca"                       => "decimal",
   "dbd:macedonianDenar"                      => "decimal",
   "dbd:malagasyAriary"                       => "decimal",
   "dbd:malawianKwacha"                       => "decimal",
   "dbd:malaysianRinggit"                     => "decimal",
   "dbd:maldivianRufiyaa"                     => "decimal",
   "dbd:mauritanianOuguiya"                   => "decimal",
   "dbd:mauritianRupee"                       => "decimal",
   "dbd:megabit"                              => "decimal",
   "dbd:megabyte"                             => "decimal",
   "dbd:megacalorie"                          => "decimal",
   "dbd:megahertz"                            => "decimal",
   "dbd:megalitre"                            => "decimal",
   "dbd:megametre"                            => "decimal",
   "dbd:meganewton"                           => "decimal",
   "dbd:megapascal"                           => "decimal",
   "dbd:megapond"                             => "decimal",
   "dbd:megavolt"                             => "decimal",
   "dbd:megawatt"                             => "decimal",
   "dbd:megawattHour"                         => "decimal",
   "dbd:metre"                                => "decimal",
   "dbd:metrePerSecond"                       => "decimal",
   "dbd:mexicanPeso"                          => "decimal",
   "dbd:microampere"                          => "decimal",
   "dbd:microlitre"                           => "decimal",
   "dbd:micrometre"                           => "decimal",
   "dbd:microsecond"                          => "decimal",
   "dbd:microvolt"                            => "decimal",
   "dbd:mile"                                 => "decimal",
   "dbd:milePerHour"                          => "decimal",
   "dbd:milliampere"                          => "decimal",
   "dbd:millibar"                             => "decimal",
   "dbd:millicalorie"                         => "decimal",
   "dbd:milligram"                            => "decimal",
   "dbd:milligramForce"                       => "decimal",
   "dbd:millihertz"                           => "decimal",
   "dbd:millilitre"                           => "decimal",
   "dbd:millimetre"                           => "decimal",
   "dbd:millinewton"                          => "decimal",
   "dbd:millipascal"                          => "decimal",
   "dbd:millipond"                            => "decimal",
   "dbd:millisecond"                          => "decimal",
   "dbd:millivolt"                            => "decimal",
   "dbd:milliwatt"                            => "decimal",
   "dbd:milliwattHour"                        => "decimal",
   "dbd:minute"                               => "decimal",
   "dbd:moldovanLeu"                          => "decimal",
   "dbd:mongolianTögrög"                      => "decimal",
   "dbd:moroccanDirham"                       => "decimal",
   "dbd:mozambicanMetical"                    => "decimal",
   "dbd:myanmaKyat"                           => "decimal",
   "dbd:namibianDollar"                       => "decimal",
   "dbd:nanometre"                            => "decimal",
   "dbd:nanonewton"                           => "decimal",
   "dbd:nanosecond"                           => "decimal",
   "dbd:nautialMile"                          => "decimal",
   "dbd:nepaleseRupee"                        => "decimal",
   "dbd:netherlandsAntilleanGuilder"          => "decimal",
   "dbd:newTaiwanDollar"                      => "decimal",
   "dbd:newZealandDollar"                     => "decimal",
   "dbd:newton"                               => "decimal",
   "dbd:newtonCentimetre"                     => "decimal",
   "dbd:newtonMetre"                          => "decimal",
   "dbd:newtonMillimetre"                     => "decimal",
   "dbd:nicaraguanCórdoba"                    => "decimal",
   "dbd:nigerianNaira"                        => "decimal",
   "dbd:northKoreanWon"                       => "decimal",
   "dbd:norwegianKrone"                       => "decimal",
   "dbd:omaniRial"                            => "decimal",
   "dbd:ounce"                                => "decimal",
   "dbd:pakistaniRupee"                       => "decimal",
   "dbd:panamanianBalboa"                     => "decimal",
   "dbd:papuaNewGuineanKina"                  => "decimal",
   "dbd:paraguayanGuarani"                    => "decimal",
   "dbd:pascal"                               => "decimal",
   "dbd:perCent"                              => "decimal",
   "dbd:perMil"                               => "decimal",
   "dbd:peruvianNuevoSol"                     => "decimal",
   "dbd:pferdestaerke"                        => "decimal",
   "dbd:philippinePeso"                       => "decimal",
   "dbd:polishZłoty"                          => "decimal",
   "dbd:pond"                                 => "decimal",
   "dbd:pound"                                => "decimal",
   "dbd:poundFoot"                            => "decimal",
   "dbd:poundPerSquareInch"                   => "decimal",
   "dbd:poundSterling"                        => "decimal",
   "dbd:poundal"                              => "decimal",
   "dbd:qatariRial"                           => "decimal",
   "dbd:renminbi"                             => "decimal",
   "dbd:rod"                                  => "decimal",
   "dbd:romanianNewLeu"                       => "decimal",
   "dbd:russianRouble"                        => "decimal",
   "dbd:rwandaFranc"                          => "decimal",
   "dbd:saintHelenaPound"                     => "decimal",
   "dbd:samoanTala"                           => "decimal",
   "dbd:saudiRiyal"                           => "decimal",
   "dbd:second"                               => "decimal",
   "dbd:serbianDinar"                         => "decimal",
   "dbd:seychellesRupee"                      => "decimal",
   "dbd:sierraLeoneanLeone"                   => "decimal",
   "dbd:singaporeDollar"                      => "decimal",
   "dbd:slovakKoruna"                         => "decimal",
   "dbd:solomonIslandsDollar"                 => "decimal",
   "dbd:somaliShilling"                       => "decimal",
   "dbd:southAfricanRand"                     => "decimal",
   "dbd:southKoreanWon"                       => "decimal",
   "dbd:squareCentimetre"                     => "decimal",
   "dbd:squareDecametre"                      => "decimal",
   "dbd:squareDecimetre"                      => "decimal",
   "dbd:squareFoot"                           => "decimal",
   "dbd:squareHectometre"                     => "decimal",
   "dbd:squareInch"                           => "decimal",
   "dbd:squareKilometre"                      => "decimal",
   "dbd:squareMetre"                          => "decimal",
   "dbd:squareMile"                           => "decimal",
   "dbd:squareMillimetre"                     => "decimal",
   "dbd:squareNauticalMile"                   => "decimal",
   "dbd:squareYard"                           => "decimal",
   "dbd:sriLankanRupee"                       => "decimal",
   "dbd:standardAtmosphere"                   => "decimal",
   "dbd:stone"                                => "decimal",
   "dbd:sudanesePound"                        => "decimal",
   "dbd:surinamDollar"                        => "decimal",
   "dbd:swaziLilangeni"                       => "decimal",
   "dbd:swedishKrona"                         => "decimal",
   "dbd:swissFranc"                           => "decimal",
   "dbd:syrianPound"                          => "decimal",
   "dbd:sãoToméAndPríncipeDobra"              => "decimal",
   "dbd:tajikistaniSomoni"                    => "decimal",
   "dbd:tanzanianShilling"                    => "decimal",
   "dbd:terabyte"                             => "decimal",
   "dbd:terahertz"                            => "decimal",
   "dbd:terawattHour"                         => "decimal",
   "dbd:thaiBaht"                             => "decimal",
   "dbd:tonganPaanga"                         => "decimal",
   "dbd:tonne"                                => "decimal",
   "dbd:tonneForce"                           => "decimal",
   "dbd:trinidadAndTobagoDollar"              => "decimal",
   "dbd:tunisianDinar"                        => "decimal",
   "dbd:turkishLira"                          => "decimal",
   "dbd:turkmenistaniManat"                   => "decimal",
   "dbd:ugandaShilling"                       => "decimal",
   "dbd:ukrainianHryvnia"                     => "decimal",
   "dbd:unitedArabEmiratesDirham"             => "decimal",
   "dbd:uruguayanPeso"                        => "decimal",
   "dbd:usBarrel"                             => "decimal",
   "dbd:usBarrelOil"                          => "decimal",
   "dbd:usDollar"                             => "decimal",
   "dbd:usGallon"                             => "decimal",
   "dbd:uzbekistanSom"                        => "decimal",
   "dbd:valvetrain"                           => "decimal",
   "dbd:vanuatuVatu"                          => "decimal",
   "dbd:venezuelanBolívar"                    => "decimal",
   "dbd:volt"                                 => "decimal",
   "dbd:watt"                                 => "decimal",
   "dbd:wattHour"                             => "decimal",
   "dbd:westAfricanCfaFranc"                  => "decimal",
   "dbd:yard"                                 => "decimal",
   "dbd:yemeniRial"                           => "decimal",
   "dbd:zambianKwacha"                        => "decimal",
   "dbd:zimbabweanDollar"                     => "decimal",
  );
our %MULTIPLICITY =
  ("cims:M:0..1" => {min => 0, max => 1},
   "cims:M:0..2" => {min => 0, max => 2},
   "cims:M:0..n" => {min => 0, max => "inf"},
   "cims:M:1"    => {min => 1, max => 1},
   "cims:M:1..1" => {min => 1, max => 1},
   "cims:M:1..n" => {min => 1, max => "inf"},
   "cims:M:2..n" => {min => 2, max => "inf"},
  );

our @STRING_MAP =
  ({"rdf:langString" => "langString", "rdfs:Literal" => "stringOrLangString", "rdf:PlainLiteral" => "stringOrLangString", "schema:Text" => "stringOrLangString", "xsd:string" => "string"},
   {"rdf:langString" => "langString", "rdfs:Literal" => "langString",         "rdf:PlainLiteral" => "langString",         "schema:Text" => "langString",         "xsd:string" => "string"},
   {"rdf:langString" => "string",     "rdfs:Literal" => "string",             "rdf:PlainLiteral" => "string",             "schema:Text" => "string",             "xsd:string" => "string"});
our @UNDEFINED_STRING_MAP = # what to map undefined datatype to
  ("stringOrLangString", "langString", "string");

# datatypes ignored with warning, not yet supported by the platform

our @NO_DATATYPES =
  qw(xsd:duration xsd:gMonthDay cim:MonthDay xsd:gDay xsd:gMonth xsd:base64Binary xsd:hexBinary xsd:QName xsd:NOTATION xsd:normalizedString xsd:token xsd:language xsd:Name xsd:NCName xsd:ID xsd:IDREF xsd:IDREFS xsd:ENTITY xsd:ENTITIES xsd:NMTOKEN xsd:NMTOKENS owl:rational owl:real);
our %NO_DATATYPES;
map {$NO_DATATYPES{$_} = 1} @NO_DATATYPES;

our @LANG_SPECS = qw(fetch validate implicit);

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
  -voc     pfx    Use "pfx" as vocab_prefix (and default SOML ID).
  -voc     NONE   Don't look for vocab_prefix in the first ontology using various heuristics.
  -id      id     Set SOML ID
  -label   label  Set SOML label
  -super   0|1    Generate X and XInterface for every superclass X (default 0: Platform 3.3 does this internally)
  -name    p1,p2  Designate these props as class "name" characteristics (eg rdfs:label,skos:prefLabel)
  -string  0      Emit rdf:langString as langString; rdf:PlainLiteral & rdfs:Literal & schema:Text & undefined datatype as stringOrLangString; xsd:string as string
           1      Emit rdf:langString & rdf:PlainLiteral & rdfs:Literal & schema:Text & undefined datatype as langString; xsd:string as string
           2      Emit rdf:langString & rdf:PlainLiteral & rdfs:Literal & schema:Text & undefined datatype & xsd:string as string
  -lang    str    Set schema-level lang spec. Doesn't make sense if "-string 2" is specified
  -shorten        Shorten CIM prop names that repeat the domain, eg entsoe2:CurrentLimit.normalValue -> entsoe2:normalValue; cim:Equipment.EquipmentContainer -> cim:equipmentContainer
                  Lowercases the prop name even for object props. Then uses only per-object "props" but not use global "properties".
           1      When the prop name matches its domain
           2      When the prop has no domain, or its name matches the domain
           3      Always

Parses:
- ontologies (owl:Ontology, dct:created, dct:modified, $creator_props),
- classes (rdfs:Class, owl:Class);
  - EXCLUDES schema:DataTypes, CIM datatypes (cims:stereotype "Primitive", "CIMDatatype"), and $no_classes;
- class inheritance (rdfs:subClassOf). If -super 1 then generates concrete class and abstract superclass and patches the hierarchy;
- props (rdf:Property, owl:AnnotationProperty, owl:DatatypeProperty, owl:ObjectProperty);
  - EXCLUDES props whose domain is a CIM datatype
- prop cardinality (owl:FunctionalProperty, cims:multiplicity; but NOT owl:InverseFunctionalProperty)
- datatypes ($datatypes);
  - EXCLUDES $no_datatypes
  - Default is stringOrLangString, langString, or string depending on option -string
- lang specs for handling langString
- prop relations (owl:inverseOf, schema:inverseOf, cims:inverseRoleName; but NOT rdfs:subPropertyOf);
- prop domains (rdfs:domain, schema:domainIncludes, owl:unionOf). Multiple domains are allowed.
- prop ranges (rdfs:range, schema:rangeIncludes, cims:dataType, owl:unionOf). Object or datatype ranges are allowed.
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
- Doesn't inherit domain & range from a property's ancestor(s). Enquire about the status of issue PLATFORM-1500
END
}

my @name_char;
GetOptions ("vocab=s"   => \$vocab_prefix,
            "id=s"      => \$soml_id,
            "label=s"   => \$soml_label,
            "super=i"   => \$super_opt,
            "name=s"    => \@name_char,
            "string=i"  => \$string_opt,
            "lang=s"    => \$lang_opt,
            "shorten=i" => \$shorten_opt,
           )
  or usage();
@name_char = split(/,/,join(',',@name_char)); # https://metacpan.org/pod/Getopt::Long#Options-with-multiple-values
map {$name_char{$_} = 1} @name_char if @name_char;
##use Data::Dumper; my_die Dumper(\@name_char,\%name_char);
$string_opt = 0 unless $string_opt;
my_die "-string must be between 0 and 2, found $string_opt\n" if $string_opt>2;

sub first_ontology() {
  # get ontology metadata, and try to figure out vocab_iri and vocab_prefix
  my $base;
  my $iter = $model->subjects(IRI("rdf:type"), IRI("owl:Ontology"));
  if ($ontology_iri = $iter->next) {
    $ontology = $ontology_iri->as_string;
    $iter->next and my_warn <<EOF;
Found multiple ontologies, metadata only of the first one is used: $ontology.
Consider using -id, -label to not treat the first ontology specially.
EOF
    $base = one_value($model->objects($ontology_iri, IRI("swc:BaseUrl")))
  };
  # try to find vocab_iri and vocab_prefix in various inter-dependent ways
  if ($vocab_prefix && $vocab_prefix eq "NONE") { # option -voc NONE
    $vocab_prefix = undef;
  } elsif ($vocab_prefix) { # option -voc
    $vocab_iri = iri ($map->namespace_uri($vocab_prefix))
      or my_die "can't find vocab_iri of -voc prefix $vocab_prefix";
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
    my_die "can't find owl:Ontology (should be in first RDF file) and neither -voc nor -id are specified"
  };
  $soml{specialPrefixes}{vocab_prefix} = $vocab_prefix if $vocab_prefix;
  $soml{specialPrefixes}{vocab_iri}    = $vocab_iri->as_string if $vocab_iri;
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
  # out: array of IRIs, or strings (have no lang), or langString "@en", skipping duplicates, sorted
  my $iter = shift;
  uniq (sort map $_->value,
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
  join ". ", @descr; # ...because we add dot between values
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

sub LIT ($) {
  my $str = shift;
  Attean::Literal->new(value => $str);
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

sub abbr($) {
  # Return abbreviated string (pname) through $map
  my $iri = shift;
  $map->abbreviate(uri($iri))
}

sub ABBR($) {
  # Return abbreviated string (pname) through $MAP
  my $iri = shift;
  $MAP->abbreviate(uri($iri))
}

sub iri_name($$) {
  # Given an IRI, return hash of 3 names:
  #  "gql" (GraphQL), "rdf" (RDF prefixed name), eventually "super" (gql+"Interface")
  # Arg "isProp" says whether the IRI is a property: the first letter (after prefix) is lowercased
  #  TODO: this assumes that a class and prop will never have the same IRI. Which is usually true but some people do crazy shit
  my $iri = shift;
  my $isProp = shift;
  $iri = ref($iri) ? $iri->as_string : $iri;
  return $iri_name{$iri} if $iri_name{$iri}; # memoization
  my $rdf = abbr($iri) or my_die("No suitable prefix for IRI $iri");
  my $gql = $rdf;
  my ($pfx,$pname) = $gql =~ m{^(.*?):(.*)$};
  $pname or my_die("Can't parse $gql into $pfx:$pname ?!");
  # https://ontotext.atlassian.net/browse/PLATFORM-3046 Allow props to start with uppercase
  $pname = lcfirst($pname) if $isProp;
  $gql = $vocab_prefix && $pfx eq $vocab_prefix ? $pname : "$pfx:$pname";
  # https://ontotext.atlassian.net/browse/PLATFORM-1625 Allow punctuation in local names and prefixes: replaces [-_.:] with "_" so we don't need to do it
  $gql_rdf{$gql} = $rdf;
  return $iri_name{$iri} = {gql=>$gql, rdf=>$rdf}
}

sub make_inherits(\@\@) {
  # for each $class, pick its first superclass and make the %inherits matrix
  my ($classes, $no_classes) = @_;
  for my $class (@$classes) {
    # Ignore anonymous (blank node) super-classes
    my @inherits = map $_->as_string, grep $_->isa("Attean::IRI"),
      $model->objects ($class, IRI("rdfs:subClassOf"))->elements;
    $class = iri_name($class,0) and $class = $class->{gql} or next;
    @inherits = array_minus (@inherits, @$no_classes);
    @inherits = sort map $_->{gql}, grep $_, map iri_name($_,0), @inherits;
    $inherits{$class} = $inherits[0] if @inherits;
    my_warn("Found multiple superclasses for $class, using only the first one: ".
            join(", ",@inherits))
      if @inherits>1
  }
}

sub make_super() {
  # make SOML statements to create dual pair "$concrete class - abstract $super interface"
  my %isSuper = reverse %inherits;
  for my $concrete (keys %isSuper) {
    my $super = $concrete."Interface";
    $super{$concrete} = $super;
    $soml{objects}{$super}{kind} = "abstract";
    $soml{objects}{$super}{descr} = "Abstract superclass of $concrete";
    $soml{objects}{$concrete}{type} = $gql_rdf{$concrete};
    $soml{objects}{$concrete}{inherits} = $super;
  }
}

sub emit_inherits () {
  # emit the %inherits relation, while lifting to the abstract superclasses, if applicable
  while (my ($subClass,$superClass) = each %inherits) {
    $subClass   = $super{$subClass}   if $super_opt && $super{$subClass};
    $superClass = $super{$superClass} if $super_opt && $super{$superClass};
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
  my $x = ABBR($range);
  $x && $STRING_MAP[$string_opt]{$x} and return {kind=>"datatype", gql => $STRING_MAP[$string_opt]{$x}};
  $x && $DATATYPES{$x} and return {kind=>"datatype", gql => $DATATYPES{$x}};
  $x && $NO_DATATYPES{$x} and do {my_warn("Prop $pname uses unsupported datatype $x, ignored"); return undef};
  my $y = iri_name($range,0);
  $y and return {kind => "class", gql => $y->{gql}, rdf => $y->{rdf}};
  return undef
}

sub map_ranges ($$) {
  my ($prop,$name) = @_;
  my @ranges = expand_union ($model->objects ($prop,
    [map IRI($_), qw(rdfs:range schema:rangeIncludes cims:dataType)]));
  sort {$a->{gql} cmp $b->{gql}}
    grep $_, map map_range($name,$_), @ranges
}

sub langSpec() {
  $lang_opt or return;
  $lang_opt && $string_opt==2 and
    my_die("-lang doesn't make sense if '-string 2' is specified");
  my $lang;
  if ($lang_opt !~ / /) {$lang = $lang_opt} # simple string
  else {
    $lang = {}; # empty hash
    my %langSpecs;
    @langSpecs{@LANG_SPECS} = 1;
    for (split(/, /, $lang_opt)) {
      my ($key,$val) = split(/: /, $_);
      exists $langSpecs{$key} or
        my_die("For -lang use either a simple string (no spaces) or 'key: val, ...' with keys '".
               join(", ",@LANG_SPECS)."'");
      $val =~ m{ } and
        my_die("Don't use spaces in value in -lang '$key: $val'");
      $lang->{$key} = $val;
    }
  };
  $soml{config}{lang} = $lang;
}

sub multiplicity($$) {
  my ($prop,$name) = @_;
  if (my $multiplicity = one_value ($model->objects ($prop, IRI("cims:multiplicity")))) {
    $multiplicity = ABBR($multiplicity);
    my $mult = $MULTIPLICITY{$multiplicity} or my_die "Unknown cims:multiplicity $multiplicity\n";
    # https://perldoc.perl.org/perlfaq4#How-do-I-merge-two-hashes?
    # @{...}{...} is a hash slice: all these keys ... get all those values
    @{$soml{properties}{$name}}{keys %$mult} = values %$mult;
    ##use Data::Dumper; my_die Dumper($soml{properties}{$name});
  } elsif (my $isFunctional = $model->holds ($prop, IRI("rdf:type"), IRI("owl:FunctionalProperty"))) {
    # $soml{properties}{$name}{max} = 1 # this is default
  } else {
    $soml{properties}{$name}{max} = "inf"
  }
}

##### main

scalar(@ARGV) < 1 and usage(); # if there are no args, print usage() and die
$vocab_prefix && $vocab_prefix eq "NONE" && !$soml_id    and my_die  "'-voc NONE' causes no processing of ontology metadata, please provide -id";
$vocab_prefix && $vocab_prefix eq "NONE" && !$soml_label and my_warn "'-voc NONE' causes no processing of ontology metadata, please provide -label";

load_ontologies(@ARGV);
langSpec();

# ontology metadata
if ($soml_id) {
  $soml{id} = "/soml/$soml_id";
} elsif ($ontology_iri) {
  my $soml_label = get_label ($ontology_iri,"ontology");
  my @creators = uniq_en_strings($model->objects($ontology_iri, [map IRI($_), @CREATOR_PROPS]));
  $soml{creator} = join ", ", sort @creators if @creators;
  my $created = date_part (one_value($model->objects($ontology_iri, IRI("dct:created"))));
  $soml{created} = $created if $created;
  my $updated = date_part (one_value($model->objects($ontology_iri, IRI("dct:modified"))));
  $soml{updated} = $updated if $updated;
  my $versionInfo = one_value($model->objects($ontology_iri, IRI("owl:versionInfo")));
  $soml{versionInfo} = $versionInfo if $versionInfo;
};
$soml{label} = $soml_label if $soml_label;

# prefixes
while (my ($pfx,$iri) = $map->each_map) {
  $soml{prefixes}{$pfx} = $iri->as_string
};

our @CIM_DATATYPES =
  $model->subjects(IRI("cims:stereotype"),
                   [map LIT($_), qw(Primitive CIMDatatype)])->elements;
map {
  my $dt = ABBR($_);
  $DATATYPES{$dt} || $NO_DATATYPES{$dt} or my_die "Datatype $dt not mapped\n";
} @CIM_DATATYPES;

# classes (objects)

# https://github.com/kasei/attean/issues/152: need to use uniq()
# Ignore anonymous (blank node) classes
my @classes = uniq (map $_->as_string, grep $_->isa("Attean::IRI"),
                    $model->subjects(IRI("rdf:type"), [IRI("rdfs:Class"), IRI("owl:Class")])->elements);
# Undesirable classes. Map to as_string else array_minus may miss the same IRI instantiated from the ontology vs using IRI()
my @no_classes = map $_->as_string,
  ((map IRI($_), @NO_CLASSES),
   $model->subjects(IRI("rdf:type"), IRI("schema:DataType"))->elements,
   @CIM_DATATYPES);
@classes = array_minus (@classes, @no_classes);
for my $class (@classes) {
  $class = iri($class);
  my $iri_name = iri_name($class,0);
  my $name = $iri_name->{gql};
  my $rdf = $iri_name->{rdf};
  next if $DATATYPES{$rdf};
  $soml{objects}{$name}{type} = $rdf; # if $name ne $rdf
  my $label = get_label ($class, "class $rdf");
  $soml{objects}{$name}{label} = $label if $label;
  my $descr = get_descr ($class);
  $soml{objects}{$name}{descr} = $descr if $descr;
};

make_inherits(@classes, @no_classes);
make_super() if $super_opt;
emit_inherits();

# properties
my @props = uniq (map $_->as_string,
                  $model->subjects (IRI("rdf:type"), [map IRI($_), @PROP_CLASSES]) ->elements);
my @no_props = map $_->as_string,
  ((map IRI($_), @NO_PROPS),
   # CIM datatype characteristics (value, unit, multiplier, denominatorUnit, denominatorMultiplier) are unused in data
   $model->subjects(IRI("rdfs:domain"),[@CIM_DATATYPES])->elements);
## my_die join ", ", map $_->as_string, @CIM_DATATYPES);
## my_die @no_props,"\n";
@props = array_minus (@props, @no_props);

for my $prop (map iri($_), @props) {
  my $iri_name = iri_name($prop,1);
  my $name = $iri_name->{gql};
  my $rdf = $iri_name->{rdf};
  $soml{properties}{$name}{rdfProp} = $rdf; # if $name ne $rdf;
  my $label = get_label ($prop, "property $rdf");
  $soml{properties}{$name}{label} = $label if $label;
  my $descr = get_descr ($prop);
  $soml{properties}{$name}{descr} = $descr if $descr;

  # prop characteristics
  my $isObjectProp = $model->holds ($prop, IRI("rdf:type"), IRI("owl:ObjectProperty"));
  my $isDataProp   = $model->holds ($prop, IRI("rdf:type"), [IRI("owl:AnnotationProperty"), IRI("owl:DatatypeProperty")]);
  my $isSymmetric  = $model->holds ($prop, IRI("rdf:type"), IRI("owl:SymmetricProperty"));
  $soml{properties}{$name}{symmetric} = "true" if $isSymmetric;
  multiplicity($prop,$name);
  my $inverseOf = one_value ($model->objects ($prop, [map IRI($_), qw(owl:inverseOf schema:inverseOf cims:inverseRoleName)]));
  if ($inverseOf) { # emit bidirectionally
    $inverseOf = iri_name($inverseOf,1)->{gql};
    $soml{properties}{$name}{inverseOf} = $inverseOf;
    $soml{properties}{$inverseOf}{inverseOf} = $name; # hope and pray $inverseOf is defined as a prop
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
    if ($isObjectProp) {$class = "iri"}
    else {$datatype = $UNDEFINED_STRING_MAP[$string_opt]}
  };
  $class = $super{$class} if $class && $super_opt && $super{$class};
  $soml{properties}{$name}{range} = $datatype || $class;
  $soml{properties}{$name}{kind}  = $datatype ?  "literal" : "object";

  # domains
  my @domains = expand_union ($model->objects ($prop, [IRI("rdfs:domain"), IRI("schema:domainIncludes")]));
  for my $domain (@domains) {
    my $class = iri_name($domain,0) or next;
    my $rdf = $class->{rdf};
    $DATATYPES{$rdf} # schema:URL was domain of category, https://github.com/schemaorg/schemaorg/issues/2536: fixed 14 Apr 2020
      and warn "$rdf is a datatype but listed as domain of $name";
    $class = $class->{gql} or next;
    # fix for referenced classes that may not be defined in the ontology
    $soml{objects}{$class}{type} = $rdf;
    $class = $super{$class} if $super_opt && $super{$class};

    if ($shorten_opt) {
      # TODO: the difficulty is that once we shorten the prop name, it's local so we must put it under {$class}{props}. But above we already put it in the global {properties}
    };
    $soml{objects}{$class}{props}{$name} = {};

    # "name" characteristic
    if (exists $name_char{$name}) {
      $soml{objects}{$class}{name} = $name;
      $soml{objects}{$class}{props}{$name}{min} = 1;
      $soml{objects}{$class}{props}{$name}{max} = 1
        if $soml{objects}{$class}{props}{$name}{range} &&
           $soml{objects}{$class}{props}{$name}{range} eq "string"
    }
  };

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
