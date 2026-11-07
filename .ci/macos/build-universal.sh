#!/usr/bin/env bash
#
# build Veyon (Master side) as universal binaries (arm64 + x86_64) for macOS 12 and
# newer and create the installer package - in contrast to build.sh no libraries from
# Homebrew are used as Homebrew only provides them for Apple Silicon and recent macOS
#
# usage: build-universal.sh <source dir> <build dir> [output dir]
#
# required environment variables:
#   QT_ROOT_DIR               official Qt installation, e.g. ~/Qt/6.8.3/macos
# optional environment variables:
#   DEPS_PREFIX               where to build the other dependencies (default: ~/veyon-deps)
#   MACOSX_DEPLOYMENT_TARGET  oldest supported macOS version (default: 12.0)
#
# required tools: cmake, ninja and rsvg-convert (e.g. from Homebrew - only used at build time)
#

set -euo pipefail

SRC=$(cd "$1" && pwd)
BUILD=$2
OUTPUT=${3:-$SRC}

: "${QT_ROOT_DIR:?QT_ROOT_DIR has to point to an official (universal) Qt installation}"
export DEPS_PREFIX=${DEPS_PREFIX:-$HOME/veyon-deps}
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0}

"$SRC/.ci/macos/build-deps.sh" "$DEPS_PREFIX"

# Homebrew is ignored so that only universal libraries end up in the build
cmake -S "$SRC" -B "$BUILD" -G Ninja \
	-DCMAKE_MAKE_PROGRAM="$(command -v ninja)" \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DCMAKE_PREFIX_PATH="$QT_ROOT_DIR;$DEPS_PREFIX" \
	-DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" \
	-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
	-DOPENSSL_ROOT_DIR="$DEPS_PREFIX" \
	-DQT_TRANSLATIONS_DIR="$QT_ROOT_DIR/translations" \
	-DWITH_BUNDLED_LIBVNC=ON \
	-DWITH_LTO=OFF \
	${CMAKE_FLAGS:-}

cmake --build "$BUILD"

MACDEPLOYQT="$QT_ROOT_DIR/bin/macdeployqt" \
DEPLOY_LIBPATHS="$DEPS_PREFIX/lib:$QT_ROOT_DIR/lib" \
QCA_OSSL_PLUGIN=$(find "$DEPS_PREFIX/lib" -name "libqca-ossl*.dylib" | head -n 1) \
	"$SRC/macos/create-package.sh" "$BUILD" "$OUTPUT"

APP="$BUILD/macos/staging/root/Applications/Veyon/Veyon Master.app"

# every binary in the bundle has to run on both architectures
not_universal=0
while IFS= read -r -d '' file ; do
	case "$(file -b "$file")" in
		*Mach-O*)
			archs=" $(lipo -archs "$file") "
			if [[ "$archs" != *" arm64 "* || "$archs" != *" x86_64 "* ]] ; then
				echo "Not a universal binary:$archs ${file#"$APP/"}" >&2
				not_universal=1
			fi
			;;
	esac
done < <(find "$APP/Contents" -type f -print0)
[ "$not_universal" = 0 ] || exit 1

# QCA and OpenSSL have paths in DEPS_PREFIX compiled in, which don't exist on the
# users' machines - hide it during the smoke test to check the bundle on its own
mv "$DEPS_PREFIX" "$DEPS_PREFIX.hidden"
trap 'mv "$DEPS_PREFIX.hidden" "$DEPS_PREFIX"' EXIT
"$SRC/.ci/macos/smoke-test.sh" "$APP"
