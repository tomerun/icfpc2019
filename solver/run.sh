#!/bin/sh

aws s3 cp "s3://icfpc-2019/input/${TASKNAME}.desc" input.desc
shards build --release
bin/solver < input.desc
