#!/bin/sh

cd ~
aws s3 cp s3://icfpc-2019/solver.zip solver.zip
unzip solver.zip
cd solver
./run.sh

