PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man
DESTDIR ?=

all:
	$(MAKE) -C src

clean:
	$(MAKE) -C src clean

install:
	$(MAKE) -C src install DESTDIR=$(DESTDIR) PREFIX=$(PREFIX) BINDIR=$(BINDIR) MANDIR=$(MANDIR)
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/saphira-udpdist/LICENSE
	install -Dm644 man/udpdist.1 $(DESTDIR)$(MANDIR)/man1/udpdist.1
	install -Dm644 etc/saphira/udpdist/example.conf $(DESTDIR)/etc/saphira/udpdist/example.conf
	install -Dm644 etc/saphira/udpdist/example-quic.conf $(DESTDIR)/etc/saphira/udpdist/example-quic.conf
	install -Dm644 accounts.d/saphira-udpdist $(DESTDIR)$(PREFIX)/share/saphira/accounts.d/saphira-udpdist
	install -Dm755 tests/regress.sh $(DESTDIR)$(PREFIX)/share/saphira/udpdist/regress.sh
	install -Dm755 tests/lab.sh $(DESTDIR)$(PREFIX)/share/saphira/udpdist/lab.sh

test:
	tests/regress.sh

.PHONY: all clean install test
