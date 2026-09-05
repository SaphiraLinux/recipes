#!/bin/sh

set -eu
umask 022

die()
{
	printf 'recipe: %s\n' "$*" >&2
	exit 1
}

. /mnt/akadata-stage4/config/build-environment.conf
LC_ALL=$AKADATA_BUILD_LC_ALL
LANG=$AKADATA_BUILD_LANG
TZ=$AKADATA_BUILD_TZ
SOURCE_DATE_EPOCH=$AKADATA_BUILD_SOURCE_DATE_EPOCH
export LC_ALL LANG TZ SOURCE_DATE_EPOCH
export AKADATA_BUILD_PATH CC CXX CPP AR AS LD NM RANLIB READELF STRIP \
	OBJCOPY PKG_CONFIG AKADATA_REQUIRED_BUILD_COMMANDS \
	AKADATA_RECIPE_COMMON_COMMANDS AKADATA_CONFIGURE_COMMANDS \
	AKADATA_LIBDIR_NAME
lib=$AKADATA_LIBDIR_NAME
export lib
PATH=$AKADATA_BUILD_PATH
export PATH

: "${AKADATA_SOURCE:?source archive path is required}"
: "${AKADATA_WORK:?writable build path is required}"
: "${AKADATA_DEST:?writable package staging path is required}"
JOBS=${JOBS:-2}
LOAD_LIMIT=${LOAD_LIMIT:-2}
TARGET_CPPFLAGS=${TARGET_CPPFLAGS:-}
TARGET_CFLAGS=${TARGET_CFLAGS:-'-march=x86-64-v3 -O3 -pipe'}
TARGET_CXXFLAGS=${TARGET_CXXFLAGS:-$TARGET_CFLAGS}
TARGET_LDFLAGS=${TARGET_LDFLAGS:-'-Wl,--build-id=sha1'}
export CPPFLAGS="$TARGET_CPPFLAGS"
export CFLAGS="$TARGET_CFLAGS"
export CXXFLAGS="$TARGET_CXXFLAGS"
export LDFLAGS="$TARGET_LDFLAGS"

source_dir=$AKADATA_WORK/source
build_dir=$AKADATA_WORK/build
phase_dir=$AKADATA_WORK/.akadata-phases
timing_file=${AKADATA_TIMING_FILE:-$AKADATA_WORK/.akadata-timing.tsv}

timing_event()
{
	local phase=$1 start=$2 finish=$3 status=$4
	printf '%s\t%s\t%s\t%s\t%s\n' "$phase" "$start" "$finish" \
		$((finish - start)) "$status" >> "$timing_file"
}

. /mnt/akadata-stage4/lib/unit-contract.sh
. /mnt/akadata-stage4/lib/phase-fingerprint.sh
AKADATA_PHASE_ARCHIVE=$AKADATA_SOURCE
AKADATA_PHASE_RECIPE=$AKADATA_RECIPE
AKADATA_PHASE_COMMON_FILE=/mnt/akadata-stage4/lib/recipe-common.sh
AKADATA_PHASE_CONFIG_FILE=/mnt/akadata-stage4/config/build-environment.conf
AKADATA_PHASE_STAGE4_ROOT=/mnt/akadata-stage4
AKADATA_PHASE_CPPFLAGS=$TARGET_CPPFLAGS
AKADATA_PHASE_CFLAGS=$TARGET_CFLAGS
AKADATA_PHASE_CXXFLAGS=$TARGET_CXXFLAGS
AKADATA_PHASE_LDFLAGS=$TARGET_LDFLAGS
export AKADATA_PHASE_ARCHIVE AKADATA_PHASE_RECIPE \
	AKADATA_PHASE_COMMON_FILE AKADATA_PHASE_CONFIG_FILE \
	AKADATA_PHASE_STAGE4_ROOT AKADATA_PHASE_CPPFLAGS AKADATA_PHASE_CFLAGS \
	AKADATA_PHASE_CXXFLAGS AKADATA_PHASE_LDFLAGS

phase_tree_location()
{
	unit_contract_detect
	printf '%s\n' "$AKADATA_PHASE_BUILD_LOCATIONS"
}

phase_tree_paths_valid()
{
	local location path old_ifs
	unit_contract_detect || return 1
	old_ifs=$IFS
	IFS=,
	for location in $AKADATA_PHASE_BUILD_LOCATIONS; do
		case $location in
			source) path=$source_dir ;;
			build) path=$build_dir ;;
			custom:*) path=$AKADATA_WORK/${location#custom:} ;;
			none) return 0 ;;
			*) return 1 ;;
		 esac
		test -d "$path" || { IFS=$old_ifs; return 1; }
		test -n "$(find "$path" -mindepth 1 -print -quit 2>/dev/null)" || {
			IFS=$old_ifs
			return 1
		}
	done
	IFS=$old_ifs
}

phase_tree_valid()
{
	local phase=$1
	unit_contract_detect
	case $phase in
		source) test "$AKADATA_PHASE_PHASE_SOURCE" = absent || {
			test -d "$source_dir" &&
			test -n "$(find "$source_dir" -mindepth 1 -print -quit 2>/dev/null)"
		} ;;
		configure) test "$AKADATA_PHASE_PHASE_CONFIGURE" = absent || unit_contract_tree_valid "$AKADATA_WORK" ;;
		build) test "$AKADATA_PHASE_PHASE_BUILD" = absent || unit_contract_tree_valid "$AKADATA_WORK" ;;
		*) return 1 ;;
	esac
}

phase_fingerprint()
{
	unit_contract_detect
	case $1 in
		source) test "$AKADATA_PHASE_PHASE_SOURCE" = absent && printf 'absent\n' || phase_source_inputs ;;
		configure) test "$AKADATA_PHASE_PHASE_CONFIGURE" = absent && printf 'absent\n' || phase_build_inputs ;;
		build) test "$AKADATA_PHASE_PHASE_BUILD" = absent && printf 'absent\n' || phase_build_inputs ;;
		*) die "unknown phase: $1" ;;
	esac
}

phase_record_valid()
{
	phase_tree_valid "$1" || return 1
	test -s "$phase_dir/$1" || return 1
	test "$(cat "$phase_dir/$1")" = "$(phase_fingerprint "$1")"
}

write_phase_record()
{
	local phase=$1 temporary
	mkdir -p "$phase_dir"
	temporary=$phase_dir/$phase.new
	phase_fingerprint "$phase" > "$temporary"
	mv -f "$temporary" "$phase_dir/$phase"
}

write_contract_record()
{
	local temporary
	unit_contract_detect
	mkdir -p "$phase_dir"
	temporary=$phase_dir/contract.new
	unit_contract_emit > "$temporary"
	mv -f "$temporary" "$phase_dir/contract"
}

prepare_source()
{
	top=$1
	mkdir -p "$AKADATA_WORK" "$AKADATA_DEST"
	if phase_record_valid source && test -d "$source_dir"; then
		# A missing build tree is disposable acceleration state. Recreate it
		# without throwing away a valid prepared source tree.
		mkdir -p "$build_dir"
		return 0
	fi
	rm -rf -- "$source_dir" "$build_dir" "$phase_dir"
	_extract_start=$(date +%s)
	tar -xf "$AKADATA_SOURCE" -C "$AKADATA_WORK"
	if test "$AKADATA_WORK/$top" != "$source_dir"; then
		mv "$AKADATA_WORK/$top" "$source_dir"
	fi
	mkdir -p "$build_dir"
	write_phase_record source
	timing_event source "$_extract_start" "$(date +%s)" success
}

gnu_configure()
{
	"$source_dir/configure" --prefix=/usr --sysconfdir=/etc \
		--localstatedir=/var "$@"
}

out_of_tree_configure()
{
	(
		cd "$build_dir"
		"$source_dir/configure" --prefix=/usr --sysconfdir=/etc \
			--localstatedir=/var "$@"
	)
}

make_build()
{
	printf 'effective_jobs=%s\neffective_load_limit=%s\nbuild_system=make\n' \
		"$JOBS" "$LOAD_LIMIT"
	printf 'build_command=make -j%s -l%s' "$JOBS" "$LOAD_LIMIT"
	printf ' %s' "$@"
	printf '\nMAKEFLAGS=%s\n' "${MAKEFLAGS-}"
	make "-j$JOBS" "-l$LOAD_LIMIT" "$@"
}

make_install()
{
	make "-j$JOBS" "-l$LOAD_LIMIT" DESTDIR="$AKADATA_DEST" "$@" install
}

meson_setup()
{
	meson setup "$build_dir" "$source_dir" --prefix=/usr \
		--sysconfdir=/etc --localstatedir=/var --buildtype=release "$@"
}

meson_build_install()
{
	printf 'effective_jobs=%s\neffective_load_limit=%s\nbuild_system=ninja\n' \
		"$JOBS" "$LOAD_LIMIT"
	ninja "-j$JOBS" "-l$LOAD_LIMIT" -C "$build_dir"
	DESTDIR="$AKADATA_DEST" ninja "-j$JOBS" "-l$LOAD_LIMIT" \
		-C "$build_dir" install
}

run_ninja()
{
	printf 'effective_jobs=%s\neffective_load_limit=%s\nbuild_system=ninja\n' \
		"$JOBS" "$LOAD_LIMIT"
	printf 'build_command=ninja -j%s -l%s' "$JOBS" "$LOAD_LIMIT"
	printf ' %s' "$@"
	printf '\n'
	ninja "-j$JOBS" "-l$LOAD_LIMIT" "$@"
}

strip_runtime()
{
	find "$AKADATA_DEST" -type f -print0 |
	while IFS= read -r -d '' file; do
		case $file in
			*.a|*.o|*.ko) continue ;;
		esac
		if file "$file" | grep -q 'ELF.*\\(executable\\|shared object\\)'; then
			strip --strip-unneeded "$file"
		fi
	done
	find "$AKADATA_DEST" -type f \
		\( -name '*.o' -o -name '*.ko' -o -name '*.a' \) -print0 |
	while IFS= read -r -d '' file; do
		case $file in
			*.a) strip --strip-debug "$file" ;;
			*)
				if file "$file" | grep -q 'ELF.*relocatable'; then
					strip --strip-debug "$file"
				fi
				;;
		esac
	done
}

run_recipe()
{
	case ${1:-} in
	build)
		_build_start=$(date +%s)
		recipe_build
		write_contract_record
		write_phase_record source
		timing_event build "$_build_start" "$(date +%s)" success
		write_phase_record configure
		write_phase_record build
		unit_contract_detect
		phase_tree_location > "$phase_dir/build.tree.new"
		mv -f "$phase_dir/build.tree.new" "$phase_dir/build.tree"
		;;
	install)
		phase_record_valid source && phase_record_valid configure && \
			phase_record_valid build ||
			die "cannot install without valid source/configure/build phases"
		_install_start=$(date +%s)
		recipe_install
		rm -f "$AKADATA_DEST/usr/share/info/dir"
		strip_runtime
		timing_event install "$_install_start" "$(date +%s)" success
		;;
	*) printf 'recipe: usage: %s {build|install}\n' "$0" >&2; exit 2 ;;
	esac
}
