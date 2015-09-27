#!/bin/sh
dbName=$1
vizName=$2
cat << EOF > ${vizName}.gv
digraph FlowDatabase {
rankdir="LR"
EOF
psql $dbName -t -c "SELECT * FROM deps.dependency_graph" >> ${vizName}.gv
echo "}" >> ${vizName}.gv
dot -Tsvg ${vizName}.gv -o ${vizName}.svg

