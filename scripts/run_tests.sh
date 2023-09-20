#!/bin/bash
set -ex
cd `dirname $BASH_SOURCE`/..
cyan build
cd gen
busted . --config-file=../busted_config.lua
