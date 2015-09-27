# configuration
dbName = flow_check

#:
help: # list all targets
	grep '^[^: ]*:' Makefile | sed -e 's/^\(\w*\):.*# \(.*\)/\1\t\2/'

#:
#: setup
#:

clean: # drop flow schema
	psql $(dbName) -f clean.sql

create: # create database
	createdb $(dbName)

setup: # install extensions
	psql $(dbName) -f setup.sql

#:
#: core components
#:

schema: clean # create schema, tables and types
	psql $(dbName) -f schema.sql

act: schema # install default activities
	psql $(dbName) -f act.sql

flow: act # install flow triggers and functions
	psql $(dbName) -f flow.sql

#:
#: DEV environment
#:

cli: # open psql terminal
	psql $(dbName)

processes = log task mail http parallel condition

examples: flow # install example processes
	$(foreach process, $(processes), psql $(dbName) -f examples/$(process).process.sql;)

test: examples # run specifications
	$(foreach process, $(processes), psql $(dbName) -f specs/$(process).spec.sql 2>&1 | ./reporter.awk;)

viz: # install dependency analyzer and flow vizualisation
	psql $(dbName) -f doc/deps.sql
	psql $(dbName) -f doc/viz.sql

doc: viz # export ERD and flow diagrams
	bin/deps.sh $(dbName) $(shell pwd)/doc/img/deps
	$(foreach process, $(processes), bin/viz.sh $(dbName) $(shell pwd)/doc/img $(process).process;)

