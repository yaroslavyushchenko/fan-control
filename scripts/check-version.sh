#!/bin/sh
# Fail unless VERSION, the top debian/changelog entry and (when given) the
# release tag all name the same version.
#   check-version.sh [tag]
set -eu

version=$(cat VERSION)
changelog=$(sed -n '1s/.*(\(.*\)).*/\1/p' debian/changelog)

if [ "$changelog" != "$version" ]; then
	echo "debian/changelog is at $changelog but VERSION is $version" >&2
	exit 1
fi
if [ $# -gt 0 ] && [ "$1" != "v$version" ]; then
	echo "tag $1 does not match VERSION $version" >&2
	exit 1
fi
echo "version $version"
