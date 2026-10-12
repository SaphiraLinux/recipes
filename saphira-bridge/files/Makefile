PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man
DESTDIR ?=

all:
	$(MAKE) -C src

clean:
	$(MAKE) -C src clean

install:
	install -Dm755 src/saphira-bridge $(DESTDIR)$(BINDIR)/saphira-bridge
	install -Dm644 man/saphira-bridge.1 $(DESTDIR)$(MANDIR)/man1/saphira-bridge.1
	install -Dm644 etc/saphira/saphira-bridge.example.conf \
		$(DESTDIR)/etc/saphira/saphira-bridge.example.conf
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/saphira-bridge/LICENSE
	install -Dm644 accounts.d/saphira-bridge \
		$(DESTDIR)$(PREFIX)/share/saphira/accounts.d/saphira-bridge
	install -Dm755 tests/regress.sh $(DESTDIR)$(PREFIX)/share/saphira-bridge/regress.sh
	install -Dm755 tests/bridge-lab.sh $(DESTDIR)$(PREFIX)/share/saphira-bridge/bridge-lab.sh

test:
	tests/regress.sh

.PHONY: all clean install test
