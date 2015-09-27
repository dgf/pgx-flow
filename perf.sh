#!/bin/sh
# start instances of the simplest process
values="('sample.process', '{\"check\":\"this 0\"}')"
for run in $(seq 1 100); do
  values="${values},('parallel.process', '{\"check\":\"this ${run}\"}')"
done

time psql flow_check -c "SET search_path TO flow, public; \
    INSERT INTO input (process, data) VALUES ${values};"

