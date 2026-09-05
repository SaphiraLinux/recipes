CC ?= cc
ARCH ?= x86-64-v3

CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -D_DEFAULT_SOURCE -D_GNU_SOURCE
ifneq ($(strip $(ARCH)),)
CFLAGS += -march=$(ARCH)
endif
# CFLAGS += -Isrc (no subdir)
# musl compatible, no extra libs
LDFLAGS ?=
LDLIBS ?=

SRC_GREDIST = gredist.c gre.c config.c
SRC_SINK = gre-sink.c gre.c config.c
SRC_SEND = gre-send.c
OBJ_GREDIST = $(SRC_GREDIST:.c=.o)
OBJ_SINK = $(SRC_SINK:.c=.o)

BIN_GREDIST = gredist
BIN_SINK = gre-sink
BIN_SEND = gre-send

PREFIX ?= /usr
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man
SYSCONFDIR ?= /etc
DESTDIR ?=

all: $(BIN_GREDIST) $(BIN_SINK) $(BIN_SEND)

$(BIN_GREDIST): $(SRC_GREDIST) gredist.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRC_GREDIST) $(LDLIBS)

$(BIN_SINK): $(SRC_SINK) gredist.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRC_SINK) $(LDLIBS)

$(BIN_SEND): $(SRC_SEND)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)

%.o: %.c gredist.h
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(BIN_GREDIST) $(BIN_SINK) $(BIN_SEND) *.o

install: $(BIN_GREDIST) $(BIN_SINK)
	install -Dm755 $(BIN_GREDIST) $(DESTDIR)$(BINDIR)/gredist
	install -Dm755 $(BIN_SINK) $(DESTDIR)$(BINDIR)/gre-sink
	install -Dm755 $(BIN_SEND) $(DESTDIR)$(BINDIR)/gre-send
	install -Dm644 ../LICENSE $(DESTDIR)$(PREFIX)/share/licenses/saphira-gredist/LICENSE 2>/dev/null || true

.PHONY: all clean install
