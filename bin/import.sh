#!/bin/sh
db=$1
file=$2
if [ ! -f "${file}" ]; then
  echo "file '${file}' not found"
elif [ ! -r "${file}" ]; then
  echo "file '${file} not readable"
else
  bpmn=$(cat ${file})
  psql ${db} -c "SELECT * FROM bpmn.import('${bpmn}')"
fi
