#!/bin/bash
set -ex
cd `dirname $BASH_SOURCE`/..
rm -rf ./gen
mkdir ./gen
mkdir ./gen/lusc
mkdir ./gen/lusc/internal
mkdir ./gen/lusc/tests
tl gen src/lusc/init.tl -o gen/lusc/init.lua
tl gen src/lusc/internal/util.tl -o gen/lusc/internal/util.lua
cp src/lusc/internal/queue.lua gen/lusc/internal/queue.lua
tl gen src/lusc/tests/async_helper.tl -o gen/lusc/tests/async_helper.lua
tl gen src/lusc/tests/lusc_spec.tl -o gen/lusc/tests/lusc_spec.lua
tl gen src/lusc/tests/setup.tl -o gen/lusc/tests/setup.lua
