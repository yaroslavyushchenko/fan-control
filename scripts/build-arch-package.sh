#!/bin/sh
# Build packaging/arch/PKGBUILD inside an Arch container, as an unprivileged
# user because makepkg refuses to run as root.
#   build-arch-package.sh local     build the checked-out tree
#   build-arch-package.sh release   build the GitHub tag tarball, pinning its sha256
set -eu

mode=$1
version=$(cat VERSION)
name=acer-predator-ph315-51-fan-control

git config --global --add safe.directory "$PWD"
sed -i "s/^pkgver=.*/pkgver=$version/" packaging/arch/PKGBUILD

if [ "$mode" = local ]; then
	git archive --format=tar.gz --prefix="fan-control-$version/" \
		-o "packaging/arch/$name-$version.tar.gz" HEAD
fi

id builder >/dev/null 2>&1 || useradd -m builder
chown -R builder packaging/arch

if [ "$mode" = release ]; then
	pacman -S --noconfirm --needed pacman-contrib
	su builder -c "cd packaging/arch && updpkgsums"
fi
su builder -c "cd packaging/arch && makepkg --noconfirm --cleanbuild"
