#!/bin/sh
# Download the assets matching a pattern from every published release, so the
# rebuilt repositories keep older versions available.
#   download-releases.sh <pattern> <dir>
set -eu

pattern=$1
dir=$2
mkdir -p "$dir"
gh release list --limit 200 --json tagName --jq '.[].tagName' | while read -r tag; do
	gh release download "$tag" --pattern "$pattern" --dir "$dir" --skip-existing || true
done
ls "$dir"
