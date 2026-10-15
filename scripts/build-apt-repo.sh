#!/bin/sh
# Build a signed APT repository ("stable main") from a directory of .deb files.
#   build-apt-repo.sh <debs-dir> <out-dir> <gpg-key-id>
set -eu

debs=$1
out=$2
key=$3
dist=$out/dists/stable

mkdir -p "$out/pool/main"
cp "$debs"/*.deb "$out/pool/main/"

cd "$out"
for arch in all amd64 arm64 i386; do
	mkdir -p "dists/stable/main/binary-$arch"
	apt-ftparchive packages pool >"dists/stable/main/binary-$arch/Packages"
	gzip -9kf "dists/stable/main/binary-$arch/Packages"
done

apt-ftparchive \
	-o APT::FTPArchive::Release::Origin=fan-control \
	-o APT::FTPArchive::Release::Label=fan-control \
	-o APT::FTPArchive::Release::Suite=stable \
	-o APT::FTPArchive::Release::Codename=stable \
	-o APT::FTPArchive::Release::Architectures="all amd64 arm64 i386" \
	-o APT::FTPArchive::Release::Components=main \
	release dists/stable >"$dist/Release"

gpg --batch --yes --local-user "$key" --clearsign -o "$dist/InRelease" "$dist/Release"
gpg --batch --yes --local-user "$key" --armor --detach-sign -o "$dist/Release.gpg" "$dist/Release"
