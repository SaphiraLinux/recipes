#!/bin/sh

pkgname=bitnet-cpp
pkgver=20260830
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Microsoft BitNet: 1.58-bit LLM inference (patched llama.cpp world, I2_S CPU kernels, x86-64-v3)'
license='MIT'
origin=bitnet-cpp
repo=saphira
url=https://github.com/microsoft/BitNet
# Vendored: microsoft/BitNet @ 0b341e5 (2026-08-30) with pinned patched
# llama.cpp submodule isHuangXin/llama.cpp @ 390c3077 included at
# 3rdparty/llama.cpp (setup_env.py already patched: huggingface-cli -> hf).
bitnet_cpp_sha256=5b196840a75c81209c47b370387f07268bf439e4ef1b194f20c5d44b321bfde3

# C++ runtime required: llama.cpp world is C++; libstdc++.so.6/libgcc_s.so.1
# currently live in the gcc package (gcc-libs split queued as its own task).
depends="gcc-libs"
makedepends="
	binutils
	cmake
	gcc
	saphira-kernel-headers=7.1.5
	ninja
	python3
"

# Compile-at-package-build decision: the i2_s quantized GGUF ships ready
# in microsoft/BitNet-b1.58-2B-4T-gguf, so users only download the model
# and run llama-cli/llama-server. setup_env.py stays in /usr/share/bitnet
# (patched to hf) for TL-kernel/other-model workflows only.
recipe_build()
{
	BITNETBALL="$RECIPE_DIR/files/bitnet-20260830.tar.gz"
	echo "$bitnet_cpp_sha256  $BITNETBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" -xf "$BITNETBALL"
	patch -d "$SRC/bitnet-20260830" -Np1 \
		-i "$RECIPE_DIR/files/0001-saphira-build-banner.patch"
	patch -d "$SRC/bitnet-20260830" -Np1 \
		-i "$RECIPE_DIR/files/0002-saphira-helper-entrypoints.patch"
	cd "$SRC/bitnet-20260830"
	cmake -B build -S . \
		-G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DBITNET_X86_TL2=OFF \
		-DLLAMA_BUILD_TOOLS=ON \
		-DLLAMA_BUILD_EXAMPLES=ON \
		-DLLAMA_BUILD_COMMON=ON \
		-DLLAMA_BUILD_SERVER=ON \
		-DCMAKE_C_FLAGS="-march=x86-64-v3 -O2" \
		-DCMAKE_CXX_FLAGS="-march=x86-64-v3 -O2"
	cmake --build build --target llama-cli llama-server llama-quantize
}

recipe_install()
{
	cd "$SRC/bitnet-20260830"
	install -d "$PKGDEST/usr/bin"
	for b in llama-cli llama-server llama-quantize; do
		install -m 0755 "build/bin/$b" "$PKGDEST/usr/bin/$b"
	done
	# Tools link their impl/common libs with $ORIGIN rpath; ship the
	# shared objects into /usr/lib so the runtime closure resolves.
	install -d "$PKGDEST/usr/lib"
	for so in build/bin/*.so*; do
		install -m 0755 "$so" "$PKGDEST/usr/lib/"
	done
	install -d "$PKGDEST/usr/share/bitnet"
	install -m 0644 README.md "$PKGDEST/usr/share/bitnet/README.md"
	install -m 0755 setup_env.py run_inference.py run_inference_server.py \
		"$PKGDEST/usr/share/bitnet/"
	cp -r utils "$PKGDEST/usr/share/bitnet/utils"
	chmod 0755 "$PKGDEST/usr/share/bitnet/utils"/*.py
	# Entry points: PATH-resolved packaged binaries (see
	# 0002-saphira-helper-entrypoints.patch). Conversion utilities that
	# need torch/gguf-py stay in /usr/share/bitnet/utils (optional,
	# explicitly not packaged as deps).
	install -d "$PKGDEST/usr/bin"
	cat > "$PKGDEST/usr/bin/bitnet-run" <<'EOF'
#!/usr/bin/python3
import runpy
runpy.run_path("/usr/share/bitnet/run_inference.py", run_name="__main__")
EOF
	cat > "$PKGDEST/usr/bin/bitnet-serve" <<'EOF'
#!/usr/bin/python3
import runpy
runpy.run_path("/usr/share/bitnet/run_inference_server.py", run_name="__main__")
EOF
	chmod 0755 "$PKGDEST/usr/bin/bitnet-run" "$PKGDEST/usr/bin/bitnet-serve"
}
