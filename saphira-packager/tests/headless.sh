#!/bin/sh

# Headless distribution policy (no X, no desktop): static assertions that
# no graphical stack enters the package universe or a package's
# dependency closure. No build required.
#
# Policy encoded (see RECIPE_RULES.md "Headless distribution policy"):
# - no X11, Wayland, GTK, Qt, desktop environment, display manager or
#   graphical helper stack may be depended upon;
# - no recipe may ENABLE a graphical stack at build time.
#
# Why the denylist is by package NAME and never by substring:
# a substring scan for GUI vocabulary produced eight false positives
# because "ibus" is a substring of "libusb" (gpsd, qemu, usbredir and
# usbutils all legitimately depend on libusb). A denylist of whole
# package names is safe precisely because libusb is not on it.
#
# The legitimate near-misses are named in RECIPE_RULES.md and must never
# be added to the denylist by overreach: libxkbcommon (console
# keymaps), fontconfig/freetype (headless rasterising is legitimate),
# ffmpeg (a headless transcode server is exactly what Saphira wants) and
# libglib (a support library used headlessly by qemu, usbredir, gpsd,
# lldpd, libvirt and spice-server).
#
# This gate exists because the tree is currently CLEAN, and a clean tree
# with no gate is one `apk add xorg-server` away from not being clean.
#
# usage: headless.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

fail()
{
	printf '%s\n' "headless: $*" >&2
	exit 1
}

failures=0
violations=$(mktemp "${SAPHIRA_TMPDIR:-/build/tmp}/headless-violations.XXXXXX")
trap 'rm -f -- "$violations"' EXIT HUP INT TERM
: > "$violations"

report()
{
	printf '%s\n' "headless: $*" >&2
	printf '%s\n' "$*" >> "$violations"
}

# --- 1. The denylist ---------------------------------------------------
#
# Whole package names only. Grouped by tier so the reason a name is
# forbidden stays legible. Names under "weaker tier" are NOT checked
# here: they have legitimate headless uses and are policy, not a gate.

tier1_forbidden='
xorg-server
xorg-server-common
xorg-x11-server
xorg-xorgctl
xorg-xinit
xorg-xrandr
xorg-xrdb
xorg-xsetroot
xorg-xkbcomp
xorg-xauth
xorg-xdpyinfo
xorg-fonts
x11vnc
tigervnc
xterm
Xvfb
libx11
libx11-xcb
libxcb
libxshmfence
libxext
libxi
libxrender
libxtst
libxss
libxfixes
libxdamage
libxcomposite
libxrandr
libxinerama
libxcursor
libxkbcommon-x11
libxxf86vm
libglvnd
libgl
libegl
libgles
mesa
libgbm
libdrm
libvulkan
libepoxy
libglx
wayland
libwayland
libwayland-client
libwayland-server
libwayland-egl
libwayland-cursor
weston
wlroots
sway
qtwayland
gtk2
gtk3
gtk4
libgtk
gdk-pixbuf
pango
cairo
at-spi2
libadwaita
qt5-qtbase
qt6-qtbase
libqt5
libqt6
sdl2
libSDL
xfwm4
xfdesktop
pcmanfm
gdm
lightdm
sddm
ly
dconf
gsettings-desktop-schemas
xdg-desktop-portal
'

# The denylist above is written one-name-per-line for legibility, but the
# membership test below is a space-delimited word match. Normalise once.
#
# This was a SILENTLY VACUOUS GATE in the first draft: matching
# " $base " against a newline-separated list never matches, because the
# character before each name is \n, not a space. The gate reported OK on a
# tree that depended on libx11. A validator that cannot fail is worse than
# no validator, so the conversion is asserted, not assumed.
tier1_list=$(printf '%s' "$tier1_forbidden" | tr '\n' ' ')
case $tier1_list in
	*'  '*) fail "denylist has a blank entry" ;;
esac
tier1_count=$(printf '%s' "$tier1_list" | wc -w)
[ "$tier1_count" -gt 50 ] || fail "denylist looks truncated ($tier1_count names)"

# --- 2. depends / makedepends token extraction -------------------------
#
# The recipe-rules.sh idiom (awk strips the VAR=" opener and the closing
# " continuation, emitting interior tokens), extended to every dependency
# field so a `-dev` split cannot smuggle a stack in through depends_dev.

dep_fields='depends makedepends depends_dev depends_runtime'

extract_deps()
{
	awk -v fields="$dep_fields" '
		BEGIN {
			n = split(fields, f, " ")
			for (i = 1; i <= n; i++) want[f[i]] = 1
			inblock = 0
		}
		{
			line = $0
			# VAR=" opener (possibly several on one line).
			if (match(line, /^(depends|makedepends|depends_dev|depends_runtime)="/)) {
				rest = substr(line, RSTART + RLENGTH)
				if (rest !~ /"$/) inblock = 1
				print rest
				next
			}
			if (inblock) {
				if ($0 ~ /^"$/) inblock = 0
				print
				next
			}
		}
	' "$1" |
		# strip version operators, quotes, and trailing backslashes
		tr -c 'A-Za-z0-9._+-' '\n' |
		grep -E '^[A-Za-z0-9]' |
		sed -e 's/[<>=].*$//' -e 's/-$//'
}

for recipe in "$source_root"/*/recipe.sh; do
	[ -f "$recipe" ] || continue
	pkg=$(basename "$(dirname "$recipe")")

	extract_deps "$recipe" | sort -u > "$violations.deps"
	[ -s "$violations.deps" ] || { rm -f -- "$violations.deps"; continue; }

	while IFS= read -r dep; do
		[ -n "$dep" ] || continue
		# Strip a -dev/-doc suffix: gtk+-dev resolves to gtk+, and
		# libx11-dev must be caught as libx11.
		base=$dep
		case $base in
			*-dev|*-doc|*-libs|*-dbg) base=${base%-*} ;;
		esac
		case " $tier1_list " in
			*" $base "*|*" $dep "*)
				if [ -d "$source_root/$dep" ] || [ -d "$source_root/$base" ]; then
					report "$pkg depends on $dep: forbidden graphical package AND a recipe for it exists in the tree"
				else
					report "$pkg depends on $dep: forbidden graphical package (no such recipe exists either; this is a dangling aspiration)"
				fi
				;;
		esac
	done < "$violations.deps"
	rm -f -- "$violations.deps"
done

# --- 3. No recipe may ENABLE a graphical stack at build time -----------
#
# Dependency metadata cannot see this. `qemu` without `--disable-gtk`
# silently builds a GTK UI if gtk3 ever lands in the closure, and
# `imagemagick` without `--without-x` silently links it. So a build-flag
# scan is required, and the negation must be EXPLICIT and matched to the
# specific toggle, mirroring RECIPE_RULES.md "Prefer explicit
# enable/disable switches over silent autodetection".
#
# The four existing correct decisions this locks in:
#   imagemagick --without-x, qemu --disable-gtk --disable-sdl
#   --disable-opengl, spice-server's server-only scope.

# Toggle -> the negation that must be present instead.
enable_flag='--with-x
--enable-x
--with-xt
--with-gtk
--enable-gtk
--with-gtkgfx
--with-qt
--enable-qt
--with-qt5
--with-qt6
--with-wayland
--enable-wayland
--with-sdl
--enable-sdl
--with-sdl2
--with-opengl
--enable-opengl
--with-gl
--enable-gl
--with-glx
--with-xcb
--with-xvfb
--with-cups
--with-pulseaudio
--with-alsa
'

for recipe in "$source_root"/*/recipe.sh; do
	[ -f "$recipe" ] || continue
	pkg=$(basename "$(dirname "$recipe")")

	# Only recipe_build bodies can enable a feature.
	sed -n '/^recipe_build()/,/^}/p' "$recipe" > "$violations.body" 2>/dev/null || :
	[ -s "$violations.body" ] || { rm -f -- "$violations.body"; continue; }
	# Drop comment lines: prose about X is not enabling X.
	grep -v '^[[:space:]]*#' "$violations.body" > "$violations.body2" || :
	mv "$violations.body2" "$violations.body"

	for flag in $enable_flag; do
		# Whole-token match, and the token boundary EXCLUDES [a-z0-9-].
		#
		# A substring match here produced five false positives on the
		# real tree, and they are the same trap as "ibus" in "libusb":
		#   libarchive   --enable-xattr  (extended attributes)
		#   libarchive   --with-xml2     (XML)
		#   php85        --enable-xml, --enable-xmlreader, --enable-xmlwriter
		#   rsync        --enable-xattr-support, --enable-xxhash
		#   strongswan   --enable-x509, --enable-pem
		# Requiring the character after the flag to not be [a-z0-9-]
		# rejects all of them with no exception list: -x509 continues
		# with '5', -xattr with 'a', -xml with 'm', -xxhash with 'x',
		# and -xml2 with 'm'.
		grep -qE -- "(^|[[:space:]'\"])${flag}([[:space:]'\"=]|$)" "$violations.body" || continue
		# The flag is present. Is an explicit negation of the same
		# feature also present?
		feature=${flag#--}
		feature=${feature#with-}
		feature=${feature#enable-}
		negated=no
		grep -qE -e "(^|[[:space:]'\"])--without-${feature}([[:space:]'\"]|=|$)" "$violations.body" && negated=yes
		grep -qE -e "(^|[[:space:]'\"])--disable-${feature}([[:space:]'\"]|=|$)" "$violations.body" && negated=yes
		case $feature in
			gtk)  grep -q -- '-Dgtk=disabled' "$violations.body" && negated=yes ;;
			qt|qt5|qt6) grep -qE -- '-D(qt|qt5|qt6|qtbase)=disabled' "$violations.body" && negated=yes ;;
			gl|glx|opengl) grep -qE -- '-D(opengl|gl|glx|gles)=disabled' "$violations.body" && negated=yes ;;
			wayland) grep -qE -- '-D(wayland|wayland-egl)=disabled' "$violations.body" && negated=yes ;;
			alsa) grep -qE -- '-D(alsa|alsa-lib)=disabled' "$violations.body" && negated=yes ;;
		esac
		[ "$negated" = yes ] && continue
		report "$pkg: recipe_build enables $flag without an explicit --without/--disable for the same feature; Saphira is headless (see RECIPE_RULES.md 'Headless distribution policy')"
	done
	rm -f -- "$violations.body"
done

# --- 4. No graphical build directory in a payload ----------------------

for payload in "$source_root"/*/files/*; do
	[ -f "$payload" ] || continue
	pkg=$(basename "$(dirname "$payload")")
	case $payload in
		*LICENSE) continue ;;
	esac
	# A shipped desktop entry is a GUI integration point by definition.
	case ${payload##*/} in
		*.desktop) report "$pkg: ships a .desktop file; Saphira has no desktop shell to register with" ;;
	esac
done

count=$(wc -l < "$violations")
if [ "$count" -gt 0 ]; then
	printf '%s\n' "headless: $count violation(s); see RECIPE_RULES.md 'Headless distribution policy'" >&2
	exit 1
fi

printf '%s\n' 'headless: OK (no X/Wayland/GTK/Qt/desktop dependency, no graphical build flag enabled, no .desktop payload)'
