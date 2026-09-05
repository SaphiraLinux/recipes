#!/bin/sh

phase_hash_file()
{
	sha256sum "$1" | awk '{print $1}'
}

phase_contract_fingerprint()
{
	unit_contract_emit | sha256sum | awk '{print $1}'
}

phase_source_contract_fingerprint()
{
	{
		printf 'source.provenance=%s\n' "$AKADATA_PHASE_SOURCE_PROVENANCE"
		printf 'source.preparation=%s\n' "$AKADATA_PHASE_SOURCE_PREPARATION"
		printf 'source.patches=%s\n' "$AKADATA_PHASE_SOURCE_PATCHES"
		printf 'source.generation=%s\n' "$AKADATA_PHASE_SOURCE_GENERATION"
		printf 'phase.source=%s\n' "$AKADATA_PHASE_PHASE_SOURCE"
		printf 'common.prepare=%s\n' "$(phase_file_function_fingerprint \
			"$AKADATA_PHASE_COMMON_FILE" prepare_source)"
		printf 'recipe.prepare=%s\n' "$(phase_recipe_source_semantics)"
	} | sha256sum | awk '{print $1}'
}

phase_build_contract_fingerprint()
{
	{
		printf 'phase.configure=%s\n' "$AKADATA_PHASE_PHASE_CONFIGURE"
		printf 'phase.build=%s\n' "$AKADATA_PHASE_PHASE_BUILD"
		printf 'build.system=%s\n' "${AKADATA_PHASE_BUILD_SYSTEM:-custom}"
		printf 'build.locations=%s\n' "$AKADATA_PHASE_BUILD_LOCATIONS"
		printf 'build.dependencies=%s\n' "${AKADATA_PHASE_BUILD_DEPENDENCIES:-none}"
	} | sha256sum | awk '{print $1}'
}

phase_semantic_common_fingerprint()
{
	awk '
		BEGIN {
			wanted["gnu_configure"] = 1
			wanted["out_of_tree_configure"] = 1
			wanted["make_build"] = 1
			wanted["make_install"] = 1
			wanted["meson_setup"] = 1
			wanted["meson_build_install"] = 1
			wanted["run_ninja"] = 1
			wanted["strip_runtime"] = 1
		}
		function braces(line,    opens, closes) {
			opens = line; closes = line
			gsub(/[^\{]/, "", opens); gsub(/[^\}]/, "", closes)
			return length(opens) - length(closes)
		}
		/^[[:alnum:]_]+[[:space:]]*\(\)[[:space:]]*$/ {
			name = $1; sub(/\(\)$/, "", name)
			active = (name in wanted); depth = 0
		}
		active {
			if ($0 !~ /^[[:space:]]*printf([[:space:]]|$)/ &&
				$0 !~ /akadata_log_policy/) print
			depth += braces($0)
			if (depth == 0 && $0 ~ /^[[:space:]]*}[[:space:]]*$/)
				active = 0
		}
	' "$AKADATA_PHASE_COMMON_FILE" | sha256sum | awk '{print $1}'
}

phase_source_inputs()
{
	local recipe_dir input relative path
	unit_contract_detect
	recipe_dir=$(dirname "$AKADATA_PHASE_RECIPE")
	{
		printf 'contract=%s\n' "$(phase_source_contract_fingerprint)"
	if test "${AKADATA_PHASE_SOURCE_PROVENANCE:-archive}" = virtual; then
		printf 'provenance=virtual\n'
	else
		printf 'archive=%s\n' "$(phase_hash_file "$AKADATA_PHASE_ARCHIVE")"
	fi
		find "$recipe_dir" -type f \( -name '*.patch' -o -name '*.diff' \) \
			-print 2>/dev/null | sort | while IFS= read -r path; do
			printf 'patch=%s\n' "$(phase_hash_file "$path")"
		done
		if test -f "$AKADATA_PHASE_RECIPE"; then
			grep -Eo '/mnt/akadata-stage4/[A-Za-z0-9._/-]+' \
				"$AKADATA_PHASE_RECIPE" | sort -u | while IFS= read -r input; do
				relative=${input#/mnt/akadata-stage4/}
				path=$AKADATA_PHASE_STAGE4_ROOT/$relative
				test -f "$path" || continue
				printf 'input=%s\n' "$(phase_hash_file "$path")"
			done
		fi
		for input in ${AKADATA_PHASE_EXTRA_INPUTS:-}; do
			test -f "$input" || continue
			printf 'extra=%s\n' "$(phase_hash_file "$input")"
		done
	} | sha256sum | awk '{print $1}'
}

phase_recipe_source_semantics()
{
	awk '
		function braces(line,    opens, closes) {
			opens = line; closes = line
			gsub(/[^\{]/, "", opens); gsub(/[^\}]/, "", closes)
			return length(opens) - length(closes)
		}
		/^recipe_build\(\)/ { active = 1; depth = 0 }
		active {
			if ($0 ~ /prepare_source|patch[[:space:]]|tar[[:space:]]+-xf|mkdir[[:space:]]+-p.*source_dir|cat[[:space:]]*>.*source_dir|sed[[:space:]].*source_dir|install[[:space:]].*source_dir|cp[[:space:]].*source_dir|sources\.lock|modules\.lock|submodules\.lock|crates\.lock|npm\.lock|bootstrap\.lock|GRUB_PATCH|grub_prepare_build/)
				print
			depth += braces($0)
			if (depth == 0 && $0 ~ /^[[:space:]]*}[[:space:]]*$/)
				active = 0
		}
	' "$AKADATA_PHASE_RECIPE" | sha256sum | awk '{print $1}'
}

phase_build_inputs()
{
	local source_fingerprint=${1:-}
	unit_contract_detect
	test -n "$source_fingerprint" || source_fingerprint=$(phase_source_inputs)
	{
		printf 'source=%s\n' "$source_fingerprint"
		printf 'contract=%s\n' "$(phase_build_contract_fingerprint)"
		printf 'recipe=%s\n' "$(phase_hash_file "$AKADATA_PHASE_RECIPE")"
		printf 'environment=%s\n' "$(phase_hash_file "$AKADATA_PHASE_CONFIG_FILE")"
		printf 'common=%s\n' "$(phase_semantic_common_fingerprint)"
		printf 'CPPFLAGS=%s\nCFLAGS=%s\nCXXFLAGS=%s\nLDFLAGS=%s\n' \
			"${AKADATA_PHASE_CPPFLAGS:-}" "${AKADATA_PHASE_CFLAGS:-}" \
			"${AKADATA_PHASE_CXXFLAGS:-}" "${AKADATA_PHASE_LDFLAGS:-}"
	} | sha256sum | awk '{print $1}'
}

phase_file_function_fingerprint()
{
	local file=$1 function=$2
	awk -v wanted="$function" '
		function braces(line,    opens, closes) {
			opens = line; closes = line
			gsub(/[^\{]/, "", opens); gsub(/[^\}]/, "", closes)
			return length(opens) - length(closes)
		}
		/^[[:alnum:]_]+[[:space:]]*\(\)[[:space:]]*$/ {
			name = $1; sub(/\(\)$/, "", name)
			active = (name == wanted); depth = 0
		}
		active {
			print
			depth += braces($0)
			if (depth == 0 && $0 ~ /^[[:space:]]*}[[:space:]]*$/)
				active = 0
		}
	' "$file" | sha256sum | awk '{print $1}'
}

phase_function_fingerprint()
{
	phase_file_function_fingerprint "$AKADATA_PHASE_RECIPE" "$1"
}

phase_package_inputs()
{
	local build_fingerprint=${1:-}
	unit_contract_detect
	test -n "$build_fingerprint" || build_fingerprint=$(phase_build_inputs)
	{
		printf 'build=%s\n' "$build_fingerprint"
		printf 'install=%s\n' "$(phase_function_fingerprint recipe_install)"
		printf 'outputs=%s\n' "${AKADATA_PHASE_OUTPUTS:-none}"
		if test -n "${AKADATA_PHASE_SPLIT_FILE:-}"; then
			printf 'split=%s\n' "$(phase_file_function_fingerprint \
				"$AKADATA_PHASE_SPLIT_FILE" split_payload_policy)"
		else
			printf 'split=%s\n' "${AKADATA_PHASE_SPLIT_POLICY:-none}"
		fi
	} | sha256sum | awk '{print $1}'
}
