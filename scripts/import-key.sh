#!/bin/sh
# Import the repository signing key from $REPO_SIGNING_KEY and export its
# fingerprint as SIGNING_KEY for later workflow steps.
set -eu

[ -n "${REPO_SIGNING_KEY:-}" ] || {
	echo "REPO_SIGNING_KEY is empty" >&2
	exit 1
}
printf '%s\n' "$REPO_SIGNING_KEY" | gpg --batch --import
fpr=$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr/ { print $10; exit }')
echo "SIGNING_KEY=$fpr" >>"$GITHUB_ENV"
export SIGNING_KEY="$fpr"
