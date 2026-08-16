# acer-predator-ph315-51-fan-control

Manual fan control (`auto` / `full`) for the Acer Predator PH315-51, via
direct embedded-controller (EC) register writes on Linux. Ships a root
daemon (`fanctld`) and an unprivileged CLI client (`fanctl`).

Acer's own fan curve on this model is conservative enough that the CPU/GPU
throttle under sustained load before the fans ramp up. This bypasses that
by writing the same EC registers the vendor's own "turbo" profile uses,
without needing Windows or any vendor utility.

## Why a daemon instead of sudoers

The EC is only writable as root (`/sys/kernel/debug/ec/ec0/io`). The usual
shortcut is a passwordless `sudo` rule for a fan-control script, but that
hands the calling user arbitrary root execution of whatever that script
becomes over time. Instead, `fanctld` runs as a long-lived root daemon that
knows exactly two commands (`full`, `auto`) and exposes them over a Unix
socket. The socket is `chown`'d to one UID/GID and mode `0660`, so only
that local user can talk to it — the daemon's attack surface is fixed and
small, instead of growing with the client.

## Hardware warning

The register offsets and values in `cmd/fanctld.py` were observed
specifically on the **Acer Predator PH315-51** EC by diffing its state
across the vendor's own fan profiles. They are not guaranteed to be
correct, or even safe, on other Predator models or other EC firmware.
Writing the wrong offset/value to an EC register is not guaranteed to
fail safely. Do not run this on hardware you haven't confirmed the
register map for.

## Architecture

```
fanctl (unprivileged CLI client)
   |
   | unix socket /run/fanctld.sock, mode 0660, owned by one UID/GID
   v
fanctld (root daemon, systemd unit)
   |
   v
/sys/kernel/debug/ec/ec0/io  (ec_sys kernel module, write_support=1)
```

`fanctl` prints a single line of JSON, so it composes fine with `jq`,
status bars, or anything else that wants machine-readable fan state — the
program itself has no opinion on what consumes it.

## Requirements

- Linux with the `ec_sys` kernel module available (`modinfo ec_sys`)
- `systemd`
- Python 3, no external packages

## Install

### Arch Linux

```sh
git clone https://github.com/<you>/acer-predator-ph315-51-fan-control.git
cd acer-predator-ph315-51-fan-control
makepkg -si
```

### Debian / Ubuntu

```sh
git clone https://github.com/<you>/acer-predator-ph315-51-fan-control.git
cd acer-predator-ph315-51-fan-control
dpkg-buildpackage -us -uc -b
sudo apt install ../acer-predator-ph315-51-fan-control_*.deb
```

### From source

```sh
sudo make install
```

Any of the three installs the `ec_sys` module config, `fanctld` +
its systemd unit, the `fanctl` client, and both man pages
(`man fanctl`, `man fanctld`). Then:

```sh
sudo systemctl enable --now fanctld.service
```

`fanctld` defaults to allowing UID/GID `1000` to connect. If that isn't
your user, override it before starting the service:

```sh
sudo systemctl edit fanctld.service
```

```ini
[Service]
Environment=FANCTLD_UID=<your-uid>
Environment=FANCTLD_GID=<your-gid>
```

## Usage

```sh
fanctl status   # {"ok": true, "mode": "auto"}
fanctl full     # force fans to max
fanctl auto     # back to the vendor curve
```

See `man fanctl` and `man fanctld` for details.

## Uninstall

- Arch: `sudo pacman -R acer-predator-ph315-51-fan-control-git`
- Debian: `sudo apt remove acer-predator-ph315-51-fan-control`
- From source: `sudo make uninstall`

## License

MIT — see [LICENSE](LICENSE).
