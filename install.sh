#!/bin/sh
# Installer for fan-control (fanctld + fanctl) on the Acer Predator PH315-51.
#
#   curl -fsSL https://yaroslavyushchenko.github.io/fan-control/install.sh | sh
#   curl -fsSL https://yaroslavyushchenko.github.io/fan-control/install.sh | sh -s -- --uninstall
#
# Debian/Ubuntu get a signed APT repository, Arch-based systems a signed
# pacman repository, so later updates come through the normal package
# manager. Anything else installs from the latest release tarball.

set -eu

BASE_URL=${FANCTL_BASE_URL:-https://yaroslavyushchenko.github.io/fan-control}
RELEASE_URL=${FANCTL_RELEASE_URL:-https://github.com/yaroslavyushchenko/fan-control/releases/latest/download}
DMI_PATH=${FANCTL_DMI_PATH:-/sys/class/dmi/id/product_name}
PKG=acer-predator-ph315-51-fan-control
REPO=fan-control
APT_KEY=/etc/apt/keyrings/fan-control.asc
APT_LIST=/etc/apt/sources.list.d/fan-control.list
PACMAN_CONF=/etc/pacman.conf

ACTION=install
FORCE=0
DRY_RUN=0
METHOD=

usage() {
	cat <<EOF
Usage: install.sh [--uninstall] [--method apt|pacman|source] [--force] [--dry-run]

  --uninstall   remove fan-control and its package repository
  --method      skip OS detection and use this install path
  --force       install on a model other than the PH315-51 (dangerous)
  --dry-run     print the commands instead of running them
EOF
}

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case $1 in
	--uninstall) ACTION=uninstall ;;
	--force) FORCE=1 ;;
	--dry-run) DRY_RUN=1 ;;
	--method)
		[ $# -ge 2 ] || die "--method needs a value"
		METHOD=$2
		shift
		;;
	--method=*) METHOD=${1#--method=} ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		die "unknown option: $1"
		;;
	esac
	shift
done

if [ "$(id -u)" -eq 0 ]; then
	SUDO=
elif command -v sudo >/dev/null 2>&1; then
	SUDO=sudo
elif [ "$DRY_RUN" -eq 1 ]; then
	SUDO=sudo
else
	die "run as root or install sudo"
fi

# Run a command as root, or print it in --dry-run mode.
run() {
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '+ %s\n' "$*"
	else
		$SUDO "$@"
	fi
}

# Write stdin to a root-owned file.
write_file() {
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '+ write %s:\n' "$1"
		sed 's/^/    /'
	else
		$SUDO tee "$1" >/dev/null
	fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Download a URL into a file in $TMP and print the file's path.
download() {
	file="$TMP/$2"
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '+ download %s\n' "$1" >&2
		: >"$file"
	else
		curl -fsSL --retry 3 -o "$file" "$1" || die "could not download $1"
	fi
	echo "$file"
}

need() {
	command -v "$1" >/dev/null 2>&1 && return
	if [ "$DRY_RUN" -eq 1 ]; then
		warn "'$1' is not installed (ignored in --dry-run)"
	else
		die "'$1' is required but not installed"
	fi
}

check_model() {
	model=$(cat "$DMI_PATH" 2>/dev/null || true)
	case $model in
	*PH315-51*) return ;;
	esac
	if [ "$FORCE" -eq 1 ]; then
		warn "unsupported model '${model:-unknown}', continuing because of --force"
		return
	fi
	die "this machine is '${model:-unknown}', not an Acer Predator PH315-51.
The fan register map is only known for that model; writing it elsewhere
may be unsafe. Re-run with --force if you are sure."
}

detect_method() {
	[ -n "$METHOD" ] && return
	ID='' ID_LIKE=''
	# shellcheck disable=SC1091
	[ -r /etc/os-release ] && . /etc/os-release
	case " $ID $ID_LIKE " in
	*" debian "* | *" ubuntu "*) METHOD=apt ;;
	*" arch "*) METHOD=pacman ;;
	*) METHOD=source ;;
	esac
}

target_user() {
	if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
		echo "$SUDO_USER"
	elif [ "$(id -u)" -ne 0 ]; then
		id -un
	fi
}

install_apt() {
	need apt-get
	say "Adding the APT repository $BASE_URL/apt"
	run install -d -m 0755 /etc/apt/keyrings
	key=$(download "$BASE_URL/fan-control.asc" fan-control.asc)
	run install -m 0644 "$key" "$APT_KEY"
	echo "deb [signed-by=$APT_KEY] $BASE_URL/apt stable main" | write_file "$APT_LIST"
	run apt-get update -o Dir::Etc::sourcelist="$APT_LIST" \
		-o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
	run apt-get install -y "$PKG"
}

uninstall_apt() {
	run apt-get remove -y "$PKG"
	run rm -f "$APT_LIST" "$APT_KEY"
}

install_pacman() {
	need pacman
	need pacman-key
	need gpg
	say "Adding the pacman repository $BASE_URL/arch"
	key=$(download "$BASE_URL/fan-control.asc" fan-control.asc)
	if [ "$DRY_RUN" -eq 1 ]; then
		fpr=KEY-FINGERPRINT
	else
		fpr=$(gpg --batch --with-colons --show-keys "$key" | awk -F: '/^fpr/ { print $10; exit }')
		[ -n "$fpr" ] || die "could not read the repository signing key"
	fi
	run pacman-key --add "$key"
	run pacman-key --lsign-key "$fpr"
	if ! grep -qs "^\[$REPO\]" "$PACMAN_CONF"; then
		# shellcheck disable=SC2016
		printf '\n[%s]\nServer = %s/arch/$arch\n' "$REPO" "$BASE_URL" |
			if [ "$DRY_RUN" -eq 1 ]; then
				sed 's/^/    append to pacman.conf: /'
			else
				$SUDO tee -a "$PACMAN_CONF" >/dev/null
			fi
	fi
	# Install the package file directly so this doesn't sync the system
	# databases (a partial upgrade). Future updates come with pacman -Syu.
	run pacman -U --needed --noconfirm "$BASE_URL/arch/$(uname -m)/$PKG-latest.pkg.tar.zst"
}

uninstall_pacman() {
	run pacman -R --noconfirm "$PKG"
	if grep -qs "^\[$REPO\]" "$PACMAN_CONF"; then
		run sed -i "/^\[$REPO\]\$/,/^Server = .*\/arch\/\$arch\$/d" "$PACMAN_CONF"
	fi
}

install_source() {
	need curl
	need make
	need python3
	need systemctl
	say "Installing from the latest release tarball"
	tarball=$(download "$RELEASE_URL/fan-control.tar.gz" fan-control.tar.gz)
	dir="$TMP/src"
	mkdir -p "$dir"
	if [ "$DRY_RUN" -eq 0 ]; then
		tar -xzf "$tarball" -C "$dir" --strip-components=1
	fi
	run make -C "$dir" PREFIX=/usr install
	run systemd-sysusers fanctl.conf
	run systemctl daemon-reload
}

uninstall_source() {
	run systemctl disable --now fanctld.socket fanctld.service || true
	run rm -f /usr/bin/fanctld /usr/bin/fanctl \
		/usr/lib/systemd/system/fanctld.service /usr/lib/systemd/system/fanctld.socket \
		/usr/lib/sysusers.d/fanctl.conf /usr/lib/modprobe.d/ec_sys.conf \
		/usr/lib/modules-load.d/ec_sys.conf \
		/usr/share/man/man1/fanctl.1 /usr/share/man/man8/fanctld.8
	run systemctl daemon-reload
}

finish_install() {
	user=$(target_user)
	if [ -n "$user" ]; then
		say "Adding $user to the fanctl group"
		run usermod -aG fanctl "$user"
	else
		warn "add your user to the fanctl group: usermod -aG fanctl <user>"
	fi
	if [ "$DRY_RUN" -eq 0 ] && [ ! -d /run/systemd/system ]; then
		warn "systemd is not running here; enable fanctld.socket on the real system"
		return
	fi
	say "Starting fanctld.socket"
	run systemctl enable --now fanctld.socket
	if [ "$DRY_RUN" -eq 0 ]; then
		$SUDO fanctl status || warn "fanctld did not answer; see 'journalctl -u fanctld'"
	fi
	say "Done. Log out and back in once, then run 'fanctl full' or 'fanctl auto'."
}

need curl
detect_method
case $METHOD in
apt | pacman | source) ;;
*) die "unknown method '$METHOD' (use apt, pacman or source)" ;;
esac

if [ "$ACTION" = uninstall ]; then
	say "Removing fan-control ($METHOD)"
	"uninstall_$METHOD"
	say "Removed. The fanctl group is left in place; delete it with 'groupdel fanctl'."
	exit 0
fi

check_model
say "Installing fan-control ($METHOD)"
"install_$METHOD"
finish_install
