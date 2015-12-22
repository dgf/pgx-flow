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

import BPMN process

    make import bpmn=examples/check.bpmn

## Development

install example processes

    make examples

run specifications

    make test

## Resources

 * [flow-based programming](https://en.wikipedia.org/wiki/Flow-based_programming) (FBP)
 * [Dataflow programming](https://en.wikipedia.org/wiki/Dataflow_programming)
 * [Business Process Model and Notation](https://en.wikipedia.org/wiki/Business_Process_Model_and_Notation) (BPMN)
