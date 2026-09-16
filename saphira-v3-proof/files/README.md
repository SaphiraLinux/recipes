# saphira-v3-proof

Saphira Genesis validation proof: a single-file C program that compiles,
links and executes only on a working x86-64-v3 (AVX2/FMA/BMI2/F16C/LZCNT)
Saphira toolchain and host. It is used as a benchmark/stress proof that
the compiler, musl libc, pthreads and the CPU feature baseline all work
together.

## What it validates

- compile-time x86-64-v3 ISA baseline (the build fails without it)
- an AVX2/FMA/BMI2/F16C/LZCNT inline-assembly probe with a fixed signature
- a 5000-digit pi stress computation with an FNV-1a/64 checksum
- a multi-threaded AVX2/FMA memory/ALU stress pass
- end-to-end: "compiler + libc + pthreads + x86-64-v3 execution validated"

## Build and run

    make            # builds ./saphira-v3-proof (cc, -O3, -march=x86-64-v3)
    make check      # runs the proof, expect "RESULT : PASS"
    make install    # DESTDIR/PREFIX aware; installs binary + sources

Installed layout:

- `/usr/bin/saphira-v3-proof` — compiled proof
- `/usr/src/saphira-v3-proof/` — this README, the Makefile and
  `saphira-v3-proof.c`, so consumers can inspect or rebuild the proof:

        cc -O3 -std=c11 -march=x86-64-v3 -pthread \
            saphira-v3-proof.c -o saphira-v3-proof -pthread

## Provenance

Written as the Saphira v3 validation program used to prove the Saphira
GCC 16.2.0 (x86_64-akadata-linux-musl, -march=x86-64-v3) toolchain on the
Hatchling and Egg hosts. Source is vendored byte-pinned under
`files/` in the recipe tree; there is no upstream download.
