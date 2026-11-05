#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift test --scratch-path build/core
