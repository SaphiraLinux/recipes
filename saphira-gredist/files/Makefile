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
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/saphira-gredist/LICENSE
	install -Dm644 man/gredist.1 $(DESTDIR)$(MANDIR)/man1/gredist.1
	install -Dm644 etc/saphira/gredist/example.conf $(DESTDIR)/etc/saphira/gredist/example.conf
	install -Dm755 tests/lab.sh $(DESTDIR)$(PREFIX)/share/saphira-gredist/lab.sh
	install -Dm755 tests/run-tests.sh $(DESTDIR)$(PREFIX)/share/saphira-gredist/run-tests.sh

test:
	tests/run-tests.sh

.PHONY: all clean install test
