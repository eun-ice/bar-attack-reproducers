#!/usr/bin/env bash
# Builds master and the stacked #3241 branch (full install) and copies each install dir aside.
set -uo pipefail
cd /home/aron/Projects/bar/RecoilEngine
eng=/home/aron/Projects/bar/aimfrom-estimate/engines
git checkout -q --detach origin/master || { echo "CHECKOUT master failed"; exit 1; }
echo "== master $(git rev-parse --short HEAD) $(date +%H:%M:%S)"
docker-build-v2/build.sh linux > "$eng/build-master.log" 2>&1; echo "master build exit $?"
rm -rf "$eng/master" && cp -r build-amd64-linux/install "$eng/master"
git checkout -q fix/3242-close-in-static-blockers || { echo "CHECKOUT stacked failed"; exit 1; }
echo "== stacked $(git rev-parse --short HEAD) $(date +%H:%M:%S)"
docker-build-v2/build.sh linux > "$eng/build-pr3242.log" 2>&1; echo "stacked build exit $?"
rm -rf "$eng/pr3242" && cp -r build-amd64-linux/install "$eng/pr3242"
echo "BUILDS DONE $(date +%H:%M:%S)"
