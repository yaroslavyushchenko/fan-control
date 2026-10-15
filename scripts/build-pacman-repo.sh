#!/bin/sh
# Build a signed pacman repository named "fan-control" from a directory of
# packages, plus a stable "-latest" copy of the newest one for install.sh.
#   build-pacman-repo.sh <pkgs-dir> <out-dir> <gpg-key-id>
set -eu

pkgs=$1
out=$2
key=$3
name=acer-predator-ph315-51-fan-control

dir=$out/x86_64
mkdir -p "$dir"
cp "$pkgs"/*.pkg.tar.zst "$dir/"
for pkg in "$dir"/*.pkg.tar.zst; do
	gpg --batch --yes --local-user "$key" --detach-sign -o "$pkg.sig" "$pkg"
done
repo-add --sign --key "$key" "$dir/fan-control.db.tar.gz" "$dir"/*.pkg.tar.zst

newest=$(find "$dir" -maxdepth 1 -name "$name-[0-9]*.pkg.tar.zst" | sort -V | tail -n 1)
cp "$newest" "$dir/$name-latest.pkg.tar.zst"
cp "$newest.sig" "$dir/$name-latest.pkg.tar.zst.sig"

# GitHub Pages serves no symlinks; replace repo-add's links with copies.
for link in "$dir"/*.db "$dir"/*.files "$dir"/*.db.sig "$dir"/*.files.sig; do
	[ -L "$link" ] || continue
	cp --remove-destination "$(readlink -f "$link")" "$link"
done
