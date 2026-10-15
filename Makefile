VERSION ?= $(shell cat VERSION)
PREFIX ?= /usr
DESTDIR ?=

BINDIR = $(DESTDIR)$(PREFIX)/bin
UNITDIR = $(DESTDIR)$(PREFIX)/lib/systemd/system
SYSUSERSDIR = $(DESTDIR)$(PREFIX)/lib/sysusers.d
MODPROBEDIR = $(DESTDIR)$(PREFIX)/lib/modprobe.d
MODULESLOADDIR = $(DESTDIR)$(PREFIX)/lib/modules-load.d
MAN1DIR = $(DESTDIR)$(PREFIX)/share/man/man1
MAN8DIR = $(DESTDIR)$(PREFIX)/share/man/man8

DIST = fan-control-$(VERSION)

.PHONY: all install uninstall test lint dist

all:
	@echo 'Nothing to build. Run "make install" (as root) or "make test".'

install:
	install -d $(BINDIR)
	sed 's/@VERSION@/$(VERSION)/' cmd/fanctld.py > $(BINDIR)/fanctld
	sed 's/@VERSION@/$(VERSION)/' cmd/fanctl > $(BINDIR)/fanctl
	chmod 755 $(BINDIR)/fanctld $(BINDIR)/fanctl
	install -Dm644 systemd/fanctld.service $(UNITDIR)/fanctld.service
	install -Dm644 systemd/fanctld.socket $(UNITDIR)/fanctld.socket
	install -Dm644 sysusers.d/fanctl.conf $(SYSUSERSDIR)/fanctl.conf
	install -Dm644 modprobe.d/ec_sys.conf $(MODPROBEDIR)/ec_sys.conf
	install -Dm644 modules-load.d/ec_sys.conf $(MODULESLOADDIR)/ec_sys.conf
	install -Dm644 man/fanctl.1 $(MAN1DIR)/fanctl.1
	install -Dm644 man/fanctld.8 $(MAN8DIR)/fanctld.8

uninstall:
	rm -f $(BINDIR)/fanctld $(BINDIR)/fanctl
	rm -f $(UNITDIR)/fanctld.service $(UNITDIR)/fanctld.socket
	rm -f $(SYSUSERSDIR)/fanctl.conf
	rm -f $(MODPROBEDIR)/ec_sys.conf
	rm -f $(MODULESLOADDIR)/ec_sys.conf
	rm -f $(MAN1DIR)/fanctl.1
	rm -f $(MAN8DIR)/fanctld.8

test:
	python3 -m unittest discover -s tests -v

lint:
	ruff check cmd/fanctld.py cmd/fanctl tests
	shellcheck install.sh debian/postinst scripts/*.sh

dist:
	git archive --format=tar.gz --prefix=$(DIST)/ -o $(DIST).tar.gz HEAD
