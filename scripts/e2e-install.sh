#!/bin/sh
# End-to-end check of install.sh against a locally served, freshly signed
# repository: install, run fanctl, uninstall. Run as root.
#   e2e-install.sh apt <dir with .deb>
#   e2e-install.sh pacman <dir with .pkg.tar.zst>
set -eu

method=$1
pkgs=$(cd "$2" && pwd)
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
port=8765

GNUPGHOME=$work/gnupg
export GNUPGHOME
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key "fan-control e2e <e2e@example.invalid>" ed25519 sign never
key=$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr/ { print $10; exit }')

mkdir -p "$work/site"
case $method in
apt) "$root/scripts/build-apt-repo.sh" "$pkgs" "$work/site/apt" "$key" ;;
pacman) "$root/scripts/build-pacman-repo.sh" "$pkgs" "$work/site/arch" "$key" ;;
*)
	echo "unknown method $method" >&2
	exit 1
	;;
esac
gpg --armor --export "$key" >"$work/site/fan-control.asc"
echo "Predator PH315-51" >"$work/dmi"

python3 -m http.server --directory "$work/site" --bind 127.0.0.1 "$port" >/dev/null 2>&1 &
server=$!
trap 'kill "$server"; rm -rf "$work"' EXIT
sleep 1

export FANCTL_BASE_URL="http://127.0.0.1:$port" FANCTL_DMI_PATH="$work/dmi"
sh "$root/install.sh" --method "$method"
fanctl --version
sh "$root/install.sh" --method "$method" --uninstall
if [ -e /usr/bin/fanctl ]; then
	echo "fanctl is still installed after --uninstall" >&2
	exit 1
fi
echo "e2e $method: ok"
