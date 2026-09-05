#!/bin/sh

unit_contract_append_location()
{
	local location=$1
	if test -n "${AKADATA_PHASE_BUILD_LOCATIONS:-}"; then
		AKADATA_PHASE_BUILD_LOCATIONS=$AKADATA_PHASE_BUILD_LOCATIONS,$location
	else
		AKADATA_PHASE_BUILD_LOCATIONS=$location
	fi
}

unit_contract_validate_locations()
{
	local location path
	test -n "${AKADATA_PHASE_BUILD_LOCATIONS:-}" || return 1
	case ,$AKADATA_PHASE_BUILD_LOCATIONS, in
		*,none,* ) test "$AKADATA_PHASE_BUILD_LOCATIONS" = none || return 1; return 0 ;;
	esac
	old_ifs=$IFS
	IFS=,
	for location in $AKADATA_PHASE_BUILD_LOCATIONS; do
		case $location in
			source|build) ;;
			custom:*)
				path=${location#custom:}
				case $path in
					''|/*|..|../*|*/../*|*/..|*'//'*) return 1 ;;
					esac
				;;
			*) return 1 ;;
		 esac
	done
	IFS=$old_ifs
}

unit_contract_tree_valid()
{
	local work=$1 location path old_ifs
	unit_contract_validate_locations || return 1
	[ "$AKADATA_PHASE_BUILD_LOCATIONS" = none ] && return 0
	old_ifs=$IFS
	IFS=,
	for location in $AKADATA_PHASE_BUILD_LOCATIONS; do
		case $location in
			source) path=$work/source ;;
			build) path=$work/build ;;
			custom:*) path=$work/${location#custom:} ;;
			*) IFS=$old_ifs; return 1 ;;
		esac
		test -d "$path" || { IFS=$old_ifs; return 1; }
		test -n "$(find "$path" -mindepth 1 -print -quit 2>/dev/null)" || {
			IFS=$old_ifs
			return 1
		}
	done
	IFS=$old_ifs
}

unit_contract_detect()
{
	local body=$(_unit_contract_recipe_body) path declared
	if test "${AKADATA_PHASE_CONTRACT_FIXED:-0}" = 1; then
		unit_contract_validate_locations
		return
	fi
	AKADATA_PHASE_SOURCE_PROVENANCE=${AKADATA_PHASE_SOURCE_PROVENANCE:-archive}
	AKADATA_PHASE_SOURCE_PREPARATION=${AKADATA_PHASE_SOURCE_PREPARATION:-prepare}
	AKADATA_PHASE_SOURCE_PATCHES=${AKADATA_PHASE_SOURCE_PATCHES:-absent}
	AKADATA_PHASE_SOURCE_GENERATION=${AKADATA_PHASE_SOURCE_GENERATION:-absent}
	AKADATA_PHASE_PHASE_SOURCE=present
	AKADATA_PHASE_PHASE_CONFIGURE=absent
	AKADATA_PHASE_PHASE_BUILD=absent
	AKADATA_PHASE_PHASE_INSTALL=present
	AKADATA_PHASE_BUILD_LOCATIONS=
	AKADATA_PHASE_RECOVERY=rebuild-required
	declared=$(grep -Eo 'AKADATA_PHASE_RECOVERY=(install-only|rebuild-required)' \
		"$AKADATA_PHASE_RECIPE" | tail -n 1 || true)
	test -z "$declared" || AKADATA_PHASE_RECOVERY=${declared#*=}

	if test "$AKADATA_PHASE_SOURCE_PROVENANCE" = virtual; then
		AKADATA_PHASE_PHASE_SOURCE=absent
		AKADATA_PHASE_SOURCE_PREPARATION=none
	fi

	if grep -Eq 'patch[[:space:]]|GRUB_PATCH' "$AKADATA_PHASE_RECIPE"; then
		AKADATA_PHASE_SOURCE_PATCHES=present
	fi
	if printf '%s\n' "$body" | grep -Eq 'mkdir -p "\$source_dir|tar -xf .*\$source_dir|cat > "\$source_dir|sources\.lock|modules\.lock|submodules\.lock|crates\.lock|npm\.lock|bootstrap\.lock'; then
		AKADATA_PHASE_SOURCE_GENERATION=present
	fi
	if printf '%s\n' "$body" | grep -Eq 'gnu_configure|out_of_tree_configure|(^|[[:space:];])cmake([[:space:]]|$)|meson_setup|grub_prepare_build|(^|[^[:alnum:]_])configure([[:space:]]|$)|(^|[[:space:]])\./bootstrap([[:space:]]|$)'; then
		AKADATA_PHASE_PHASE_CONFIGURE=present
	fi
	if printf '%s\n' "$body" | grep -Eq 'make_build|meson_build_install|run_ninja|cargo[[:space:]]+build|go[[:space:]]+build|make\.bash|x\.py[[:space:]].*build|embuilder.*build|\$CC .* -o ' ||
		grep -Eq 'meson_build_install|grub_prepare_build' "$AKADATA_PHASE_RECIPE"; then
		AKADATA_PHASE_PHASE_BUILD=present
	fi

	declared=$(sed -n 's/.*AKADATA_PHASE_BUILD_LOCATIONS=\([^[:space:]]*\).*/\1/p' \
		"$AKADATA_PHASE_RECIPE" | tail -n 1 || true)
	if test -n "$declared"; then
		AKADATA_PHASE_BUILD_LOCATIONS=${declared#*=}
	fi
	if test "$AKADATA_PHASE_PHASE_BUILD" = absent; then
		AKADATA_PHASE_BUILD_LOCATIONS=none
	elif test -n "$declared"; then
		:
	else
		location_body=$(printf '%s\n' "$body" | sed -E \
			'/rm -rf.*\$build_dir/d;/mkdir[^\n]*\$build_dir/d')
		if grep -Eq '\$source_dir/target' "$AKADATA_PHASE_RECIPE"; then
			unit_contract_append_location custom:source/target
		fi
		if grep -Eq '\$source_dir/out' "$AKADATA_PHASE_RECIPE"; then
			unit_contract_append_location custom:source/out/Release
		fi
		if grep -Eq 'cd "\$source_dir/src"|make\.bash' "$AKADATA_PHASE_RECIPE"; then
			unit_contract_append_location custom:source/src
		fi
		if printf '%s\n' "$location_body" | grep -Eq 'cd "\$build_dir"|-[Cc][[:space:]]*"\$build_dir"|\$build_dir/|out_of_tree_configure|(^|[[:space:];])cmake([[:space:]]|$)|meson_setup|grub_prepare_build'; then
			unit_contract_append_location build
		fi
		if test -z "$AKADATA_PHASE_BUILD_LOCATIONS"; then
			if printf '%s\n' "$body" | grep -Eq 'cd "\$source_dir"|make_build[[:space:]]+-C[[:space:]]*"\$source_dir"|run_ninja[[:space:]]+-C[[:space:]]*"\$source_dir"'; then
				unit_contract_append_location source
			elif printf '%s\n' "$body" | grep -Eq 'make_build|run_ninja|cargo[[:space:]]+build|go[[:space:]]+build|make\.bash|x\.py[[:space:]].*build|embuilder.*build|\$CC .* -o '; then
				unit_contract_append_location custom:.
			else
				unit_contract_append_location custom:source
			fi
		fi
	fi
	unit_contract_validate_locations || return 1
}

_unit_contract_recipe_body()
{
	awk '
		/^recipe_build\(\)/ { inside=1; next }
		/^recipe_install\(\)/ { exit }
		inside { print }
	' "$AKADATA_PHASE_RECIPE"
}

unit_contract_emit()
{
	unit_contract_detect || return 1
	printf 'source.provenance=%s\n' "$AKADATA_PHASE_SOURCE_PROVENANCE"
	printf 'source.preparation=%s\n' "$AKADATA_PHASE_SOURCE_PREPARATION"
	printf 'source.patches=%s\n' "$AKADATA_PHASE_SOURCE_PATCHES"
	printf 'source.generation=%s\n' "$AKADATA_PHASE_SOURCE_GENERATION"
	printf 'phase.source=%s\n' "$AKADATA_PHASE_PHASE_SOURCE"
	printf 'phase.configure=%s\n' "$AKADATA_PHASE_PHASE_CONFIGURE"
	printf 'phase.build=%s\n' "$AKADATA_PHASE_PHASE_BUILD"
	printf 'phase.install=%s\n' "$AKADATA_PHASE_PHASE_INSTALL"
	printf 'build.system=%s\n' "${AKADATA_PHASE_BUILD_SYSTEM:-custom}"
	printf 'build.locations=%s\n' "$AKADATA_PHASE_BUILD_LOCATIONS"
	printf 'recovery=%s\n' "$AKADATA_PHASE_RECOVERY"
}
