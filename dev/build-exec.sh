#!/bin/bash

what="$1"; shift

set -e
cd "$(dirname "$0")/.."
shards build "$what"
exec "bin/${what}" "$@" | tee "${what}.out"

