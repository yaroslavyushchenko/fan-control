PREFIX ?= /usr
DESTDIR ?=

BINDIR = $(DESTDIR)$(PREFIX)/bin
UNITDIR = $(DESTDIR)$(PREFIX)/lib/systemd/system
MODPROBEDIR = $(DESTDIR)$(PREFIX)/lib/modprobe.d
MODULESLOADDIR = $(DESTDIR)$(PREFIX)/lib/modules-load.d
MAN1DIR = $(DESTDIR)$(PREFIX)/share/man/man1
MAN8DIR = $(DESTDIR)$(PREFIX)/share/man/man8

.PHONY: install uninstall

install:
	install -Dm755 cmd/fanctld.py $(BINDIR)/fanctld
	install -Dm755 cmd/fanctl $(BINDIR)/fanctl
	install -Dm644 systemd/fanctld.service $(UNITDIR)/fanctld.service
	install -Dm644 modprobe.d/ec_sys.conf $(MODPROBEDIR)/ec_sys.conf
	install -Dm644 modules-load.d/ec_sys.conf $(MODULESLOADDIR)/ec_sys.conf
	install -Dm644 man/fanctl.1 $(MAN1DIR)/fanctl.1
	install -Dm644 man/fanctld.8 $(MAN8DIR)/fanctld.8

uninstall:
	rm -f $(BINDIR)/fanctld $(BINDIR)/fanctl
	rm -f $(UNITDIR)/fanctld.service
	rm -f $(MODPROBEDIR)/ec_sys.conf
	rm -f $(MODULESLOADDIR)/ec_sys.conf
	rm -f $(MAN1DIR)/fanctl.1
	rm -f $(MAN8DIR)/fanctld.8
