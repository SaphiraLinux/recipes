PREFIX ?= /usr
BINDIR := $(PREFIX)/bin
SRCDIR := $(PREFIX)/src/saphira-v3-proof

CC ?= cc
CFLAGS ?= -O3 -std=c11 -march=x86-64-v3 -Wall -Wextra -Werror -pthread
LDLIBS ?= -pthread

PROG := saphira-v3-proof
SRC := saphira-v3-proof.c
HDRS :=
DOCS := README.md

all: $(PROG)

$(PROG): $(SRC) $(HDRS)
	$(CC) $(CFLAGS) $(SRC) -o $@ $(LDLIBS)

check: $(PROG)
	./$(PROG)

install: $(PROG)
	install -Dm0755 $(PROG) $(DESTDIR)$(BINDIR)/$(PROG)
	install -Dm0644 $(SRC) $(DESTDIR)$(SRCDIR)/$(SRC)
	install -Dm0644 $(DOCS) $(DESTDIR)$(SRCDIR)/$(DOCS)
	install -Dm0644 Makefile $(DESTDIR)$(SRCDIR)/Makefile

clean:
	rm -f $(PROG)

.PHONY: all check install clean
