CC ?= cc
ARCH ?= x86-64-v3

CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -D_DEFAULT_SOURCE -D_GNU_SOURCE
ifneq ($(strip $(ARCH)),)
CFLAGS += -march=$(ARCH)
endif

LDFLAGS ?=
LDLIBS ?=

CORE = udpdist.c config.c frame.c hrw.c frag.c quic.c health.c neigh.c

BIN_MAIN = udpdist
BIN_SEND = udp-send
BIN_SINK = udp-sink

all: $(BIN_MAIN) $(BIN_SEND) $(BIN_SINK)

$(BIN_MAIN): $(CORE) udpdist.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(CORE) $(LDLIBS)

$(BIN_SEND): udp-send.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ udp-send.c $(LDLIBS)

$(BIN_SINK): udp-sink.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ udp-sink.c $(LDLIBS)

clean:
	rm -f $(BIN_MAIN) $(BIN_SEND) $(BIN_SINK) *.o

.PHONY: all clean
