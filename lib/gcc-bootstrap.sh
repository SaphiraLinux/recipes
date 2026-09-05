#!/usr/bin/env bash

GCC_BOOTSTRAP_LOCK=${GCC_BOOTSTRAP_LOCK:-$ROOT/stage2/bootstrap.lock}

gcc_bootstrap_record()
{
	local kind=$1 name=$2
	awk -F '\t' -v wanted_kind="$kind" -v wanted_name="$name" \
		'$1 == wanted_kind && $2 == wanted_name { print; exit }' \
		"$GCC_BOOTSTRAP_LOCK"
}

gcc_bootstrap_fetch_record()
{
	local kind=$1 name=$2 record version url expected archive path temporary
	record=$(gcc_bootstrap_record "$kind" "$name") ||
		die "missing GCC bootstrap lock record: $kind/$name"
	IFS=$'\t' read -r _ _ version url expected archive <<< "$record"
	path=$ROOT/pkg/$archive
	if test -f "$path"; then
		printf '%s  %s\n' "$expected" "$path" | sha256sum -c -
		return
	fi
	if ((DRY_RUN)); then
		print_command curl -fL --retry 3 --proto '=https' -o "$path" "$url"
		return
	fi
	note "fetching GCC bootstrap input: $name-$version"
	run mkdir -p "$ROOT/pkg"
	temporary=$path.part
	curl -fL --retry 3 --proto '=https' --tlsv1.2 -o "$temporary" "$url"
	printf '%s  %s\n' "$expected" "$temporary" | sha256sum -c -
	mv "$temporary" "$path"
}

gcc_bootstrap_seed_valid()
{
	test -x "$BOOTSTRAP_WORK/prefix/bin/gnatmake" &&
	test -x "$BOOTSTRAP_WORK/prefix/bin/gnatbind" &&
	test -x "$BOOTSTRAP_WORK/prefix/bin/gnatlink" &&
	test -x "$BOOTSTRAP_WORK/prefix/bin/gdc" &&
	test -f "$BOOTSTRAP_WORK/gcc-gdc.complete" &&
	test "$(cat "$BOOTSTRAP_WORK/gcc-gdc.complete" 2>/dev/null)" = \
		"$GCC_BOOTSTRAP_CONTRACT"
}

gcc_bootstrap_make_wrappers()
{
	local prefix=$BOOTSTRAP_WORK/prefix temporary tool
	run_root install -d -m 0755 "$prefix/bin"
	for tool in gnatmake gnatbind gnatlink; do
		temporary=$(mktemp "$BOOTSTRAP_WORK/.${tool}.XXXXXX")
		cat > "$temporary" <<EOF
#!/bin/sh
export PATH=/opt/akadata-bootstrap/gnat-seed/usr/bin:\$PATH
export GCC_EXEC_PREFIX=/opt/akadata-bootstrap/gnat-seed/usr/lib/gcc/
exec /opt/akadata-bootstrap/gnat-seed/usr/bin/$tool "\$@"
EOF
		run_root install -m 0755 "$temporary" "$prefix/bin/$tool"
		rm -f "$temporary"
	done
	temporary=$(mktemp "$BOOTSTRAP_WORK/.gdc.XXXXXX")
	cat > "$temporary" <<'EOF'
#!/bin/sh
exec /opt/akadata-bootstrap/gdc/bin/gdc "$@"
EOF
	run_root install -m 0755 "$temporary" "$prefix/bin/gdc"
	rm -f "$temporary"
}

ensure_gcc_bootstrap()
{
	gcc_bootstrap_seed_valid && return 0
	((DRY_RUN)) && {
		printf '+ fetch and verify locked GNAT seed packages\n'
		printf '+ build and validate private GCC 9.5 GDC/libphobos bootstrap\n'
		return 0
	}
	local archive record package seed_root gdc_source gdc_work log
	for package in gcc libgcc gcc-gnat libgnat libgnat-static; do
		gcc_bootstrap_fetch_record gnat-apk "$package"
	done
	ensure_stage4_source gcc-gdc-bootstrap
	seed_root=$BOOTSTRAP_WORK/gnat-seed
	run_root rm -rf -- "$seed_root" "$BOOTSTRAP_WORK/gdc" \
		"$BOOTSTRAP_WORK/gdc-build" "$BOOTSTRAP_WORK/gcc-gdc.complete"
	run mkdir -p "$seed_root" "$BOOTSTRAP_WORK/gdc" \
		"$BOOTSTRAP_WORK/gdc-build" "$BOOTSTRAP_WORK/prefix"
	for package in gcc libgcc gcc-gnat libgnat libgnat-static; do
		record=$(gcc_bootstrap_record gnat-apk "$package")
		IFS=$'\t' read -r _ _ _ _ _ archive <<< "$record"
		tar --warning=no-unknown-keyword -xpf "$ROOT/pkg/$archive" \
			-C "$seed_root"
	done
	gcc_bootstrap_make_wrappers
	log=$LOG_DIR/gcc-bootstrap.log
	gdc_source=/mnt/akadata-sources/$(archive_for_unit gcc-gdc-bootstrap)
	gdc_work=/var/tmp/akadata-build/gcc-gdc-bootstrap
	clear_stale_mount "$BUILD_CHROOT/opt/akadata-bootstrap"
	run_root mkdir -p "$BOOTSTRAP_WORK/prefix/gdc"
	mount_common_build_context
	mount_bind "$BOOTSTRAP_WORK/gdc" \
		"$BUILD_CHROOT/opt/akadata-bootstrap/gdc"
	mount_bind "$BOOTSTRAP_WORK/gdc-build" "$BUILD_CHROOT$gdc_work"
	phase "Building private GCC 9.5 GDC bootstrap" "$log"
	as_root chroot "$BUILD_CHROOT" /usr/bin/env -i \
		"${CHROOT_BUILD_ENV[@]}" \
		"PATH=/opt/akadata-bootstrap/bin:$AKADATA_BUILD_PATH" \
		"AKADATA_ARCHITECTURE=$AKADATA_ARCHITECTURE" \
		"CC=$CC" "CXX=$CXX" "CFLAGS=$TARGET_CFLAGS" \
		"CXXFLAGS=$TARGET_CXXFLAGS" "LDFLAGS=$TARGET_LDFLAGS" \
		"JOBS=$JOBS" "LOAD_LIMIT=$LOAD_LIMIT" \
		/bin/sh -eu -c '
		base=/var/tmp/akadata-build/gcc-gdc-bootstrap
		rm -rf "$base/source" "$base/build"
		mkdir -p "$base/source" "$base/build"
		tar -xf "/mnt/akadata-sources/'"$(archive_for_unit gcc-gdc-bootstrap)"'" \
			-C "$base/source" --strip-components=1
		cd "$base/build"
		"$base/source/configure" \
			--build=x86_64-akadata-linux-musl \
			--host=x86_64-akadata-linux-musl \
			--target=x86_64-akadata-linux-musl \
			--prefix=/opt/akadata-bootstrap/gdc \
			--with-sysroot=/ --with-native-system-header-dir=/usr/include \
			--with-arch=x86-64 --with-tune=generic \
			--with-gmp=/usr --with-mpfr=/usr --with-mpc=/usr --with-isl=/usr \
			--enable-languages=d --enable-threads=posix --enable-shared \
			--disable-bootstrap --disable-multilib --disable-nls \
			--disable-libgomp --disable-libquadmath --disable-libssp \
			--disable-libvtv --disable-libitm
		make -j"$JOBS" -l"$LOAD_LIMIT" all-gcc all-target-libphobos
		make -j"$JOBS" -l"$LOAD_LIMIT" install-gcc install-target-libphobos
		/opt/akadata-bootstrap/gdc/bin/gdc --version | sed -n "1p"
		' 2>&1 | tee "$log"
	unmount_all
	test -x "$BOOTSTRAP_WORK/gdc/bin/gdc" ||
		die "private GCC 9.5 GDC bootstrap did not produce gdc"
	printf '%s\n' "$GCC_BOOTSTRAP_CONTRACT" > "$BOOTSTRAP_WORK/gcc-gdc.complete"
}
