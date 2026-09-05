# repo-index.sh — shared repository index generation and signing.
#
# Sourced by sign-apk-repo and promote-repo so every index regeneration
# goes through the same mkndx/copy/adbsign/verify sequence with the one
# repository key. Callers resolve this file next to themselves first
# (source tree and tests) and fall back to the installed location.

repo_generate_index()
{
	apk_bin=$1 out_adb=$2 out_tar=$3 sign_key=$4 trust_dir=$5
	shift 5
	"$apk_bin" mkndx --allow-untrusted --hash sha256-160 -o "$out_adb" "$@" || return 1
	cp -- "$out_adb" "$out_tar" || return 1
	local index
	for index in "$out_adb" "$out_tar"; do
		[ -s "$index" ] || {
			printf 'repo-index: generated index is empty: %s\n' "$index" >&2
			return 1
		}
		"$apk_bin" adbsign --allow-untrusted --sign-key "$sign_key" "$index" || return 1
		"$apk_bin" verify --keys-dir "$trust_dir" "$index" || return 1
	done
}

repo_install_index()
{
	# Atomically install generated indexes into a repository directory,
	# mirroring sign-apk-repo's .publishing- temporary pattern.
	repo_dir=$1 adb=$2 tar=$3
	publication_id=$(uuidgen 2>/dev/null || date -u +%Y%m%dT%H%M%SZ)
	for pair in "Packages.adb:$adb" "APKINDEX.tar.gz:$tar"; do
		index_name=${pair%%:*}
		source_index=${pair#*:}
		temporary=$repo_dir/$index_name.publishing-$publication_id
		install -m 644 -- "$source_index" "$temporary"
		mv -f -- "$temporary" "$repo_dir/$index_name"
	done
}
