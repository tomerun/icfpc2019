#!/bin/sh

rm solver.zip
zip -r solver.zip solver/* -x solver/bin/\* solver/lib/\*
aws s3 cp solver.zip s3://icfpc-2019/solver.zip --profile icfpc
