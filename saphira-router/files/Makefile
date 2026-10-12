# saphira-router -- Makefile
#
# C11, musl, small dependency set (D1 9.1): sqlite3, ncursesw, libargon2,
# json-c, openssl. dlopen lives in musl's libc, so no -ldl (D1 9).

CC      ?= gcc
PREFIX  ?= /usr
ARCH    ?= $(shell uname -m)

# Deps: .deps/include is a development shim for headers not installed on the
# dev host (see .gitignore). In a real build these come from the packaged
# -dev packages via makedepends.
DEPS_INC := -I.deps/include
INCS     := -Iinclude $(DEPS_INC)
CFLAGS   ?= -std=c11 -O2 -g
CFLAGS   += -Wall -Wextra -Wpedantic -Wshadow -Wvla \
            -Wno-unused-parameter -D_GNU_SOURCE -fPIC
LDFLAGS  ?=
LDLIBS   := -lsqlite3 -lncursesw -ljson-c -lcrypto

# libargon2 ships only a versioned .so on hosts without the -dev package, so
# link the SONAME directly rather than a bare -largon2. `-l:NAME` asks the
# linker for that exact file, which records the SONAME in NEEDED without
# needing a development symlink.
#
# There is deliberately NO -rpath here. The previous rpath was computed by
# stripping a filename suffix with a two-% substitution reference, which make
# does not accept the way it was written: the result baked
# "/usr/lib/libargon2.so.1" -- a FILE -- into RPATH. A path naming a file is
# no search path at all, so it never helped; it only looked like it did, on the
# one machine where the library happened to sit in the default search path too.
# A build-host path in a shipped binary is also exactly the kind of thing that
# silently binds one machine's layout to another's. libargon2 is a real runtime
# dependency and is declared as one; the loader's normal search order resolves
# it.
ARGON2_LIB := -l:libargon2.so.1

# Object and binary output. Overridable so the recipe can direct both into a
# single build tree. It MUST be defined before any := line that uses it:
# immediate expansion would otherwise expand it as empty.
BINDIR   ?= build

  CORE_SRC := src/util.c src/db.c src/auth.c src/rbac.c src/api.c \
              src/module.c src/provider.c src/enroll.c src/audit.c src/tui.c src/cli.c src/main.c
CORE_OBJ := $(CORE_SRC:src/%.c=$(BINDIR)/%.o)

DAEMON   := $(BINDIR)/saphira-router
FIXTURE  := $(BINDIR)/mod_fixture.so
BADABI   := $(BINDIR)/mod_badabi.so
IPVS     := $(BINDIR)/mod_ipvs.so

# `daemon` is the only target a production build needs.
.PHONY: all daemon clean test modules install
daemon: $(DAEMON)

all: $(DAEMON) modules

$(BINDIR):
	@mkdir -p $(BINDIR)

$(BINDIR)/%.o: src/%.c | $(BINDIR)
	$(CC) $(CFLAGS) $(INCS) -c $< -o $@

$(DAEMON): $(CORE_OBJ) | $(BINDIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(CORE_OBJ) \
	    $(ARGON2_LIB) \
	    $(LDLIBS)

# --- modules -------------------------------------------------------------
# Modules are built against the public ABI header only. They never link the
# core: the core dlopen()s them and resolves the one exported symbol
# (D2 3, D2 7).
# These are TEST FIXTURES, not product. mod_fixture.so is a valid module used
# to prove the registry drives the interface; mod_badabi.so is deliberately
# broken so the refusal path stays permanently testable.
#
# Neither is part of the production package. The recipe builds the daemon
# target alone, and recipe_install refuses to package any module .so, so a
# production build never even compiles the broken one.
modules: $(FIXTURE) $(BADABI) $(IPVS)

$(FIXTURE): modules/mod_fixture.c include/sr_module.h | $(BINDIR)
	$(CC) $(CFLAGS) -fPIC $(INCS) -shared -o $@ $<

# Deliberately declares an ABI the core does not implement, to prove
# incompatible modules are refused with a diagnostic and never loaded
# optimistically (D2 6).
$(BADABI): modules/mod_badabi.c include/sr_module.h | $(BINDIR)
	$(CC) $(CFLAGS) -fPIC $(INCS) -shared -o $@ $<


# mod_ipvs.so is the first REAL provider: it implements the whole lifecycle
# against a real kernel subsystem through the ipvsadm backend. Still a
# test-side artefact rather than product -- the recipe builds the daemon
# target alone, and recipe_install refuses to package any module .so.
$(IPVS): modules/mod_ipvs.c include/sr_module.h | $(BINDIR)
	$(CC) $(CFLAGS) -fPIC $(INCS) -shared -o $@ $<
test: all
	@tests/run.sh

clean:
	rm -rf $(BINDIR)

install: all
	install -d $(DESTDIR)$(PREFIX)/bin $(DESTDIR)$(PREFIX)/lib/saphira-router/modules
	install -m 0755 $(DAEMON) $(DESTDIR)$(PREFIX)/bin/saphira-router
	install -m 0755 $(FIXTURE) $(DESTDIR)$(PREFIX)/lib/saphira-router/modules/
