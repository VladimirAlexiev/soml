# Converting Ontologies to SOML

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [Converting Ontologies to SOML](#converting-ontologies-to-soml)
    - [SKOS](#skos)
    - [DCTerms](#dcterms)
    - [Schema](#schema)
        - [Schema OWL (Experimental)](#schema-owl-experimental)

<!-- markdown-toc end -->

# Intro

See the owl2soml README for usage instructions.

A major shortcoming of most ontologies is that fery few props are declared `owl:FunctionalProperty`, so most of them get cardinality `max: inf` in SOML.
Such multi-valued props are considerably more expensive to query, and if used in a filter have an implicit `EXISTS` semantics.

# Ontologies

## SKOS 
`skos-fix.ttl`:
- Added domain `skos:Concept` to all label and note props. SKOS says they are universally applicable, but unless we bind them to `Concept` they won't show up.
- Added domain & range `skos:Concept` to all sub-props of `skos:semanticRelation` until issue PLATFORM-1500 (domain/range inheritance) is implemented.

```
time perl ../owl2soml.pl skos.rdf skos-fix.ttl > skos.yaml
Multiple ranges found for prop member, using only the first one: Concept
real    0m8.796s
user    0m0.015s
sys     0m0.046s
```

## DCTerms

We have to specify the vocab prefix because the `owl:Ontology` uses a different URL (this is an OWL DL rendition of DCT).

```sh
perl ../owl2soml.pl -voc dcterms dct_owldl.ttl > dct_owldl.yaml
```

This generated piece is invalid SOML because `isFormatOf/hasFormat` are not attached (they connect any Resources, mapped to `range: iri`),
but SOML wants to check that they are defined on a pair of classes (issue PLATFORM-1509).

```yaml
  isFormatOf:
    descr: 'A related resource that is substantially the same as the described resource, but in another format'
    inverseOf: hasFormat
    kind: object
    label: Is Format Of
    max: inf
    range: iri
```

## Schema.org

https://schema.org/docs/developers.html
We have to specify the `--vocab` prefix because schema.org doesn't define an `owl:Ontology`.
- Downloaded `jsonld`, `rdf` and `ttl`
- `schema.nt` is not appropriate because it doesn't define prefixes, so we can't obtain GraphQL (developer-friendly) class and prop names.
- `schemaorg.owl`: that file is missing, see next section.
- `schema.ttl`: worked fine, see [schema1.yaml](schema1.yaml). 
  This is the largest ontology I've tested (508k ttl, 730k rdf, 808k jsonld; results in 428k yaml) so it takes substantial time to process.

```sh
time perl ../owl2soml.pl -voc schema schema.ttl    > schema1.yaml
real    4m9.203s
user    0m0.000s
sys     0m0.094s
```

- `schema.jsonld`: install `cpanm AtteanX::Parser::JSONLD` (or use `cpan`).
  - Caused warning `Subroutine spacepad redefined at Debug/ShowStuff.pm`. See [attean#153](https://github.com/kasei/attean/issues/153) and [rt.cpan.org#131983](https://rt.cpan.org/Ticket/Display.html?id=131983)
  - Furthermore, this file uses a very poor context and doesn't define the `schema:` namespace, so is not usable by the tool. See [schemaorg#2477](https://github.com/schemaorg/schemaorg/issues/2477)

```sh
time perl ../owl2soml.pl -voc schema schema.jsonld > schema2.yaml
Subroutine spacepad redefined at C:/Strawberry/perl/site/lib/Debug/ShowStuff.pm line 1635.
        require Debug/ShowStuff.pm called at C:/Strawberry/perl/site/lib/JSONLD.pm line 57
        JSONLD::BEGIN() called at C:/Strawberry/perl/site/lib/Debug/ShowStuff.pm line 1635
        ...
can't find vocab_iri of --vocab prefix schema
real    1m51.283s
user    0m0.015s
sys     0m0.031s
```
  
- `schema.rdf`:
  - Caused error `Read more bytes than requested` (see [LibXML-schema.rdf.err](LibXML-schema.rdf.err)). This happens with `XML::LibXML` version 2.0132. 
  - I tried to upgrade to the latest version 2.0202 but got `Installing Alien::Build::MM failed` (see [Alien-Build-MM_build.log](Alien-Build-MM_build.log)). Posted as [rt.cpan.org#131982](https://rt.cpan.org/Ticket/Display.html?id=131982)

```sh
time perl ../owl2soml.pl -voc schema schema.rdf    > schema3.yaml
Read more bytes than requested. Do you use an encoding-related PerlIO layer? at C:/Strawberry/perl/vendor/lib/XML/LibXML.pm line 882.
      ...
```

SOML does not yet support multiple inheritance (issue PLATFORM-360), so we get a bunch of warnings:
```
Multiple superclasses found for schema:PaymentCard, using only the first one: FinancialProduct
Multiple superclasses found for schema:HowToSection, using only the first one: ListItem
Multiple superclasses found for schema:Physician, using only the first one: MedicalBusiness
Multiple superclasses found for schema:Hospital, using only the first one: CivicStructure
Multiple superclasses found for schema:LocalBusiness, using only the first one: Organization
Multiple superclasses found for schema:HowToDirection, using only the first one: ListItem
Multiple superclasses found for schema:HowToTip, using only the first one: CreativeWork
Multiple superclasses found for schema:StadiumOrArena, using only the first one: SportsActivityLocation
Multiple superclasses found for schema:VideoGame, using only the first one: Game
Multiple superclasses found for schema:CreditCard, using only the first one: LoanOrCredit
Multiple superclasses found for schema:HealthClub, using only the first one: SportsActivityLocation
Multiple superclasses found for schema:FireStation, using only the first one: CivicStructure
Multiple superclasses found for schema:PoliceStation, using only the first one: CivicStructure
Multiple superclasses found for schema:DepositAccount, using only the first one: InvestmentOrDeposit
Multiple superclasses found for schema:AutoPartsStore, using only the first one: Store
Multiple superclasses found for schema:MovieTheater, using only the first one: CivicStructure
Multiple superclasses found for schema:Dentist, using only the first one: MedicalBusiness
Multiple superclasses found for schema:TVSeason, using only the first one: CreativeWorkSeason
Multiple superclasses found for schema:CreativeWorkSeries, using only the first one: CreativeWork
Multiple superclasses found for schema:TVSeries, using only the first one: CreativeWork
Multiple superclasses found for schema:Pharmacy, using only the first one: MedicalOrganization
Multiple superclasses found for schema:Campground, using only the first one: CivicStructure
Multiple superclasses found for schema:HowToStep, using only the first one: ItemList
```

Schema.org uses multiple domains and ranges pervasively.
SOML supports the former but not the latter (issue PLATFORM-1493 to support multiple ranges),
so we get a bunch of warnings:

```
Multiple ranges found for prop interestRate, using only the first one: QuantitativeValue
Multiple ranges found for prop serviceArea, using only the first one: AdministrativeArea
Multiple ranges found for prop artEdition, using only the first one: integer
Multiple ranges found for prop educationalCredentialAwarded, using only the first one: iri
Multiple ranges found for prop gameLocation, using only the first one: Place
Multiple ranges found for prop elevation, using only the first one: string
Multiple ranges found for prop endDate, using only the first one: date
Multiple ranges found for prop tool, using only the first one: string
Multiple ranges found for prop partySize, using only the first one: QuantitativeValue
Multiple ranges found for prop awayTeam, using only the first one: SportsTeam
Multiple ranges found for prop photos, using only the first one: ImageObject
Multiple ranges found for prop valueReference, using only the first one: StructuredValue
Multiple ranges found for prop actionOption, using only the first one: Thing
Multiple ranges found for prop artMedium, using only the first one: string
Multiple ranges found for prop numChildren, using only the first one: integer
Multiple ranges found for prop softwareRequirements, using only the first one: string
Multiple ranges found for prop followee, using only the first one: Person
Multiple ranges found for prop longitude, using only the first one: decimal
Multiple ranges found for prop areaServed, using only the first one: GeoShape
Multiple ranges found for prop encodingFormat, using only the first one: string
Multiple ranges found for prop endTime, using only the first one: time
Multiple ranges found for prop performer, using only the first one: Person
Multiple ranges found for prop netWorth, using only the first one: MonetaryAmount
Multiple ranges found for prop isPartOf, using only the first one: iri
Multiple ranges found for prop dateCreated, using only the first one: dateTime
Multiple ranges found for prop steps, using only the first one: CreativeWork
Multiple ranges found for prop numberOfAirbags, using only the first one: string
Multiple ranges found for prop depth, using only the first one: Distance
Multiple ranges found for prop underName, using only the first one: Person
Multiple ranges found for prop checkoutTime, using only the first one: time
Multiple ranges found for prop validFrom, using only the first one: dateTime
Multiple ranges found for prop caption, using only the first one: string
Multiple ranges found for prop worstRating, using only the first one: decimal
Multiple ranges found for prop doorTime, using only the first one: dateTime
Multiple ranges found for prop hasMap, using only the first one: iri
Multiple ranges found for prop clipNumber, using only the first one: integer
Multiple ranges found for prop discount, using only the first one: string
Multiple ranges found for prop numberOfRooms, using only the first one: decimal
Multiple ranges found for prop amount, using only the first one: MonetaryAmount
Multiple ranges found for prop itemListElement, using only the first one: string
Multiple ranges found for prop minimumPaymentDue, using only the first one: PriceSpecification
Multiple ranges found for prop geoContains, using only the first one: GeospatialGeometry
Multiple ranges found for prop industry, using only the first one: string
Multiple ranges found for prop baseSalary, using only the first one: MonetaryAmount
Multiple ranges found for prop productSupported, using only the first one: string
Multiple ranges found for prop availableLanguage, using only the first one: string
Multiple ranges found for prop unitCode, using only the first one: string
Multiple ranges found for prop colleague, using only the first one: Person
Multiple ranges found for prop arrivalTime, using only the first one: dateTime
Multiple ranges found for prop driveWheelConfiguration, using only the first one: string
Multiple ranges found for prop version, using only the first one: decimal
Multiple ranges found for prop volumeNumber, using only the first one: integer
Multiple ranges found for prop totalPrice, using only the first one: string
Multiple ranges found for prop translator, using only the first one: Person
Multiple ranges found for prop highPrice, using only the first one: string
Multiple ranges found for prop geoDisjoint, using only the first one: Place
Multiple ranges found for prop namedPosition, using only the first one: iri
Multiple ranges found for prop startTime, using only the first one: time
Multiple ranges found for prop storageRequirements, using only the first one: iri
Multiple ranges found for prop itemOffered, using only the first one: Trip
Multiple ranges found for prop geoWithin, using only the first one: GeospatialGeometry
Multiple ranges found for prop homeLocation, using only the first one: ContactPoint
Multiple ranges found for prop width, using only the first one: Distance
Multiple ranges found for prop organizer, using only the first one: Person
Multiple ranges found for prop departureBusStop, using only the first one: BusStation
Multiple ranges found for prop flightDistance, using only the first one: Distance
Multiple ranges found for prop homeTeam, using only the first one: SportsTeam
Multiple ranges found for prop lodgingUnitType, using only the first one: QualitativeValue
Multiple ranges found for prop defaultValue, using only the first one: string
Multiple ranges found for prop creator, using only the first one: Organization
Multiple ranges found for prop temporal, using only the first one: string
Multiple ranges found for prop aircraft, using only the first one: string
Multiple ranges found for prop menu, using only the first one: iri
Multiple ranges found for prop identifier, using only the first one: iri
Multiple ranges found for prop vendor, using only the first one: Person
Multiple ranges found for prop typeOfBed, using only the first one: string
Multiple ranges found for prop courseMode, using only the first one: iri
Multiple ranges found for prop numberOfDoors, using only the first one: QuantitativeValue
Multiple ranges found for prop eligibleRegion, using only the first one: GeoShape
Multiple ranges found for prop logo, using only the first one: iri
Multiple ranges found for prop lender, using only the first one: Organization
Multiple ranges found for prop attendee, using only the first one: Person
Multiple ranges found for prop requirements, using only the first one: iri
Multiple ranges found for prop yield, using only the first one: QuantitativeValue
Multiple ranges found for prop season, using only the first one: iri
Multiple ranges found for prop grantee, using only the first one: ContactPoint
Multiple ranges found for prop provider, using only the first one: Organization
Multiple ranges found for prop recipeInstructions, using only the first one: string
Multiple ranges found for prop applicationCategory, using only the first one: string
Multiple ranges found for prop ticketToken, using only the first one: iri
Multiple ranges found for prop passengerPriorityStatus, using only the first one: QualitativeValue
Multiple ranges found for prop recipient, using only the first one: Audience
Multiple ranges found for prop availabilityStarts, using only the first one: dateTime
Multiple ranges found for prop funder, using only the first one: Person
Multiple ranges found for prop musicBy, using only the first one: Person
Multiple ranges found for prop lowPrice, using only the first one: decimal
Multiple ranges found for prop requiresSubscription, using only the first one: boolean
Multiple ranges found for prop bccRecipient, using only the first one: Person
Multiple ranges found for prop suggestedAnswer, using only the first one: Answer
Multiple ranges found for prop material, using only the first one: iri
Multiple ranges found for prop orderedItem, using only the first one: OrderItem
Multiple ranges found for prop estimatedSalary, using only the first one: MonetaryAmount
Multiple ranges found for prop citation, using only the first one: string
Multiple ranges found for prop bestRating, using only the first one: decimal
Multiple ranges found for prop publisher, using only the first one: Organization
Multiple ranges found for prop broadcastFrequencyValue, using only the first one: QuantitativeValue
Multiple ranges found for prop seller, using only the first one: Person
Multiple ranges found for prop value, using only the first one: StructuredValue
Multiple ranges found for prop workLocation, using only the first one: ContactPoint
Multiple ranges found for prop expectedArrivalUntil, using only the first one: dateTime
Multiple ranges found for prop orderDate, using only the first one: dateTime
Multiple ranges found for prop occupationalCategory, using only the first one: CategoryCode
Multiple ranges found for prop position, using only the first one: integer
Multiple ranges found for prop acceptedAnswer, using only the first one: Answer
Multiple ranges found for prop itemListOrder, using only the first one: ItemListOrderType
Multiple ranges found for prop paymentDueDate, using only the first one: date
Multiple ranges found for prop checkinTime, using only the first one: time
Multiple ranges found for prop reviewedBy, using only the first one: Organization
Multiple ranges found for prop dateDeleted, using only the first one: date
Multiple ranges found for prop acceptsReservations, using only the first one: iri
Multiple ranges found for prop artform, using only the first one: string
Multiple ranges found for prop featureList, using only the first one: iri
Multiple ranges found for prop acquiredFrom, using only the first one: Person
Multiple ranges found for prop contentRating, using only the first one: Rating
Multiple ranges found for prop dateRead, using only the first one: dateTime
Multiple ranges found for prop audio, using only the first one: AudioObject
Multiple ranges found for prop skills, using only the first one: DefinedTerm
Multiple ranges found for prop isRelatedTo, using only the first one: Service
Multiple ranges found for prop duringMedia, using only the first one: iri
Multiple ranges found for prop copyrightHolder, using only the first one: Person
Multiple ranges found for prop menuAddOn, using only the first one: MenuSection
Multiple ranges found for prop producer, using only the first one: Person
Multiple ranges found for prop agent, using only the first one: Organization
Multiple ranges found for prop bed, using only the first one: BedDetails
Multiple ranges found for prop broadcastFrequency, using only the first one: string
Multiple ranges found for prop recipeYield, using only the first one: string
Multiple ranges found for prop members, using only the first one: Organization
Multiple ranges found for prop interactionService, using only the first one: WebSite
Multiple ranges found for prop geoCoveredBy, using only the first one: Place
Multiple ranges found for prop surface, using only the first one: string
Multiple ranges found for prop issueNumber, using only the first one: string
Multiple ranges found for prop episodeNumber, using only the first one: integer
Multiple ranges found for prop attendees, using only the first one: Person
Multiple ranges found for prop departureTime, using only the first one: time
Multiple ranges found for prop isBasedOn, using only the first one: Product
Multiple ranges found for prop dateModified, using only the first one: date
```

### Schema OWL (Experimental)

schemaorg.owl
"Experimental/Unsupported: "schema:domainIncludes and schema:rangeIncludes values are converted into rdfs:domain and rdfs:range values using owl:unionOf to capture the multiplicity of values. Included in the range values are the, implicit within the vocabulary, default values of Text, URL, and Role.
As an experimental feature, there are no expectations as to its interpretation by any third party tools."
- https://schema.org/docs/schemaorg.owl gives error 404 Not Found. 
- https://webschemas.org/docs/schemaorg.owl also gives error 404 Not Found
- See [schemaorg#2472](https://github.com/schemaorg/schemaorg/issues/2472)
