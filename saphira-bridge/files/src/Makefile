CC ?= cc
ARCH ?= x86-64-v3

CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -D_DEFAULT_SOURCE -D_GNU_SOURCE
ifneq ($(strip $(ARCH)),)
CFLAGS += -march=$(ARCH)
endif

LDFLAGS ?=
LDLIBS ?=

CORE = bridge.c config.c eth.c cam.c fwd.c

all: saphira-bridge

saphira-bridge: $(CORE) bridge.h
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(CORE) $(LDLIBS)

clean:
	rm -f saphira-bridge

.PHONY: all clean
