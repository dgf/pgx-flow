#!/bin/sh
dbName=$1
dirName=$2
process=$3
fName=${dirName}/${process}
echo "create ${fName}.gv file"
cat << EOF > ${fName}.gv
digraph "${process}Flow" {
  rankdir="LR"
  splines="ortho"
  node [shape="box" style="rounded"]
  start [label="" shape="circle"]
  end [label="" shape="doublecircle"]
EOF
psql ${dbName} -t -c "SELECT * FROM viz.dot_process('${process}')" >> ${fName}.gv
echo "}" >> ${fName}.gv
dot -Tsvg ${fName}.gv -o ${fName}.svg
