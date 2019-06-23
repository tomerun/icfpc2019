#!/bin/sh -ev

zip -r solver.zip solver/* -x solver/bin/\* solver/lib/\* solver/*.txt
aws s3 cp solver.zip s3://icfpc-2019/solver.zip --profile icfpc
rm solver.zip
