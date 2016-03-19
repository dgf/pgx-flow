# pgx-flow PostgreSQL Extension Flow

This is a prototype of a trigger based flow oriented process execution.

supports:
  * parallel conditional flow control
  * waiting task confirmation
  * asynchronous SMTP and HTTP calls

## Requirements

The flow engine requires PostgreSQL 9.4
  + contrib package

The asynchronous call execution of SMTP and HTTP requires Perl 5.14
  + DBI::Pg
  + JSON::XS
  + LWP::Protocol::https

Install on Debian or Ubuntu

    aptitude install postgresql-contrib-9.4 libclass-dbi-pg-perl libjson-xs-perl liblwp-protocol-https-perl

## Usage

create database

    make create

install extensions as PostgreSQL superuser

    make setup

import schema and default functions

    make flow

start asynchronous notification handler

    make run

## Development

install example processes

    make examples

run specifications

    make test

update documentation images

    make doc

## BPMN support

import BPMN example process

    make import bpmn=examples/check.bpmn

start process

    make cli
    flow_check=# INSERT INTO flow.input (process,data) values ('bpmnSupport', '{"confirm":"check this"}');

create flow vizualisation of the example process

    bin/viz.sh flow_check . bpmnSupport
    firefox ./bpmnSupport.svg

## Resources

 * [flow-based programming](https://en.wikipedia.org/wiki/Flow-based_programming) (FBP)
 * [Dataflow programming](https://en.wikipedia.org/wiki/Dataflow_programming)
 * [Business Process Model and Notation](https://en.wikipedia.org/wiki/Business_Process_Model_and_Notation) (BPMN)
