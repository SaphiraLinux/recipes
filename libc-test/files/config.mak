# Saphira libc-test build config (augments the Makefile defaults;
# must append with += so the upstream -Isrc/common include paths stay).
# No glibc-only libraries: musl provides crypt/dns/dl/util inside libc.
CC = gcc
CFLAGS += -std=c99 -Os -fno-builtin -D_XOPEN_SOURCE=700
CFLAGS += -D_POSIX_C_SOURCE=200809L -Wall -Wno-unused-function -Wno-missing-braces -Wno-unused -Wno-overflow
CFLAGS += -Wno-unknown-pragmas -frounding-math
CFLAGS += -Werror=implicit-function-declaration -Werror=implicit-int -Werror=pointer-sign -Werror=pointer-arith
LDFLAGS =
LDLIBS += -lpthread -lm -lrt
