#!/bin/sh

shards build solver --release

if [ -n "$TASK_START" ] ; then
	for tn in $(seq "$TASK_START" "$TASK_END")
	do
		name=$(printf "prob-%03d" "$tn")
		aws s3 cp "s3://icfpc-2019/input/${name}.desc" input.desc
		TASKNAME="$name" bin/solver < input.desc
	done
else
	aws s3 cp "s3://icfpc-2019/input/${TASKNAME}.desc" input.desc
	bin/solver < input.desc
fi
