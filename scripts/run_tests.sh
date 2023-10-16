#!/bin/bash
set -ex
cd `dirname $BASH_SOURCE`/..
cd gen
busted . --config-file=../busted_config.lua -v
