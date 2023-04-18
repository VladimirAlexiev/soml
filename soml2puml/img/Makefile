all: bsdd-graphql-soml-diagram.png bsdd-graphql-soml-diagram.puml bsdd-graphql-soml-diagram-overview.png bsdd-graphql-soml-diagram-overview.puml sport-schema-diagram.png sport-schema-diagram.puml sport-schema-diagram-overview.png sport-schema-diagram-overview.puml

%-diagram.puml: %.yaml
	perl ../soml2puml.pl < $^ > $@
	@echo -n full: http://www.plantuml.com/plantuml/svg/
	@puml -encodeurl $@

%-diagram-overview.puml: %.yaml
	perl ../soml2puml.pl -overview < $^ > $@
	@echo -n overview: http://www.plantuml.com/plantuml/svg/
	@puml -encodeurl $@

%.png: %.puml
	puml.bat $^
