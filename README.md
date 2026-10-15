# fan-control

Manual fan control (`auto` / `full`) for the **Acer Predator PH315-51** on
Linux, via direct embedded-controller (EC) register writes. Ships a root
daemon (`fanctld`) and an unprivileged CLI client (`fanctl`).

Acer's own fan curve on this model is conservative enough that the CPU/GPU
throttle under sustained load before the fans ramp up. This bypasses that
by writing the same EC registers the vendor's own "turbo" profile uses,
without needing Windows or any vendor utility.

## Install

```sh
curl -fsSL https://yaroslavyushchenko.github.io/fan-control/install.sh | sh
```

The script checks that the machine is a PH315-51, then picks the install
path for your system:

| System | What it does | Updates |
| --- | --- | --- |
| Debian, Ubuntu and derivatives | adds the signed APT repository and runs `apt-get install` | `apt upgrade` |
| Arch, Manjaro, EndeavourOS, CachyOS | adds the signed `[fan-control]` pacman repository and installs the package | `pacman -Syu` |
| Anything else with systemd | installs the latest release tarball with `make install` | re-run the script |

It then adds you to the `fanctl` group and starts `fanctld.socket`. Log
out and back in once so the group applies.

Options (pass them after `sh -s --`): `--dry-run` prints every command
instead of running it, `--method apt|pacman|source` skips detection, and
`--uninstall` removes the package and its repository.

### Manual install

**Debian / Ubuntu**

```sh
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://yaroslavyushchenko.github.io/fan-control/fan-control.asc \
  | sudo tee /etc/apt/keyrings/fan-control.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/fan-control.asc] https://yaroslavyushchenko.github.io/fan-control/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/fan-control.list
sudo apt update && sudo apt install acer-predator-ph315-51-fan-control
```

**Arch Linux**, from the pacman repository: import the key and add the repo
to `/etc/pacman.conf`.

```sh
curl -fsSLO https://yaroslavyushchenko.github.io/fan-control/fan-control.asc
sudo pacman-key --add fan-control.asc
sudo pacman-key --lsign-key "$(gpg --with-colons --show-keys fan-control.asc | awk -F: '/^fpr/ {print $10; exit}')"
printf '\n[fan-control]\nServer = https://yaroslavyushchenko.github.io/fan-control/arch/$arch\n' | sudo tee -a /etc/pacman.conf
sudo pacman -Syu acer-predator-ph315-51-fan-control
```

Or build from source with the PKGBUILD in this repository (also works with
`yay -Bi .` from the clone):

```sh
git clone https://github.com/yaroslavyushchenko/fan-control.git
cd fan-control
makepkg -si
```

The package isn't on the AUR yet: new AUR accounts have been closed since
mid-2026. Each release attaches a ready `PKGBUILD` for when it opens.

**From source**, on any distribution with systemd and Python 3:

```sh
sudo make install
sudo systemd-sysusers fanctl.conf
sudo systemctl daemon-reload
```

After a manual install:

```sh
sudo usermod -aG fanctl "$USER"        # then log out and back in
sudo systemctl enable --now fanctld.socket
```

## Usage

```sh
fanctl status   # {"ok": true, "mode": "auto"}
fanctl full     # force fans to max
fanctl auto     # back to the vendor curve
```

`fanctl` prints exactly one line of JSON, also on errors, so it composes
with `jq`, status bars, or anything else that wants machine-readable fan
state. Exit codes: `0` success, `1` the daemon reported an error, `2` the
daemon is unreachable or you're not in the `fanctl` group, `64` bad
arguments. See `man fanctl` and `man fanctld`.

The mode is read back from the EC each time, so `status` stays correct
across daemon restarts. When the daemon stops for any reason, the fans go
back to `auto`.

## Hardware warning

The register offsets and values in `cmd/fanctld.py` were observed
specifically on the **Acer Predator PH315-51** EC by diffing its state
across the vendor's own fan profiles. They are not guaranteed to be
correct, or even safe, on other Predator models or other EC firmware.
Writing the wrong offset/value to an EC register is not guaranteed to
fail safely.

Both the installer and the daemon check `/sys/class/dmi/id/product_name`
and refuse to run on anything else. `--force` (installer) or
`FANCTLD_FORCE=1` (daemon, via `systemctl edit fanctld.service`) override
that, at your own risk.

## Secure Boot

With Secure Boot on, most distributions enable kernel lockdown, which blocks
writes through `ec_sys`. `fanctld` then fails with a clear error in
`journalctl -u fanctld`; the only fixes are disabling Secure Boot or
lockdown.

## How it works

```
fanctl (unprivileged CLI client, any member of the fanctl group)
   |
   | unix socket /run/fanctld.sock, root:fanctl 0660 (fanctld.socket)
   v
fanctld (root daemon, started on the first connection)
   |
   v
/sys/kernel/debug/ec/ec0/io  (ec_sys kernel module, write_support=1)
```

The EC is only writable as root. The usual shortcut is a passwordless
`sudo` rule for a fan-control script, but that hands the calling user
arbitrary root execution of whatever that script becomes over time.
Instead, `fanctld` knows exactly three commands (`status`, `full`, `auto`)
and listens on a socket that only the `fanctl` group can open. The
daemon's attack surface stays fixed and small. The unit is sandboxed
(read-only system, no network, no new privileges) apart from the debugfs
write it exists for.

## Uninstall

```sh
curl -fsSL https://yaroslavyushchenko.github.io/fan-control/install.sh | sh -s -- --uninstall
```

Or by hand: `sudo apt remove acer-predator-ph315-51-fan-control`,
`sudo pacman -R acer-predator-ph315-51-fan-control`, or
`sudo make uninstall`.

## Development

```sh
make test    # unit tests against a fake EC, no root needed
make lint    # ruff + shellcheck
```

CI runs both, builds the `.deb` and Arch package, and installs each one
through `install.sh` from a freshly signed local repository.

### Releasing

1. Bump `VERSION` and add a matching entry at the top of `debian/changelog`.
2. Merge, then tag: `git tag v1.2.0 && git push origin v1.2.0`.

The `Release` workflow builds both packages, publishes the GitHub Release
(with the AUR-ready `PKGBUILD`), and redeploys the signed APT and pacman
repositories and `install.sh` to GitHub Pages.

One-time setup:

- **Signing key.** Create a key without a passphrase and store it as the
  `REPO_SIGNING_KEY` secret:

  ```sh
  gpg --batch --passphrase '' --quick-gen-key "fan-control repository <you@example.com>" ed25519 sign never
  gpg --armor --export-secret-keys "fan-control repository" | gh secret set REPO_SIGNING_KEY
  ```

- **Pages.** Settings → Pages → Source: *GitHub Actions*. Then Settings →
  Environments → `github-pages` → Deployment branches and tags: add the
  tag rule `v*`.

## License

MIT — see [LICENSE](LICENSE).
