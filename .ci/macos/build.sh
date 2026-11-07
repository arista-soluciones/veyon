#!/usr/bin/env bash
#
# build Veyon (Master side) on macOS with dependencies from Homebrew and create the installer package
#
# usage: build.sh <source dir> <build dir> [output dir]
#

set -euo pipefail

SRC=$(cd "$1" && pwd)
BUILD=$2
OUTPUT=${3:-$SRC}

BREW_PREFIX=$(brew --prefix)

# Homebrew bottles target the macOS version of the build machine, so the
# resulting application bundles can't run on any older version either
DEPLOYMENT_TARGET=$(sw_vers -productVersion | cut -d. -f1).0

QT_TRANSLATIONS_DIR=""
for dir in "$BREW_PREFIX/share/qt/translations" "$BREW_PREFIX/opt/qttranslations/share/qt/translations" ; do
	if [ -d "$dir" ] ; then
		QT_TRANSLATIONS_DIR=$dir
		break
	fi
done

cmake -S "$SRC" -B "$BUILD" -G Ninja \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DCMAKE_PREFIX_PATH="$BREW_PREFIX" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
	-DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
	-DQT_TRANSLATIONS_DIR="$QT_TRANSLATIONS_DIR" \
	-DWITH_LTO=OFF \
	${CMAKE_FLAGS:-}

cmake --build "$BUILD"

export DEPLOY_LIBPATHS="$BREW_PREFIX/lib:$BREW_PREFIX/Frameworks"
"$SRC/macos/create-package.sh" "$BUILD" "$OUTPUT"

# smoke test: all libraries and plugins have to be loadable from within the bundle
APP="$BUILD/macos/staging/root/Applications/Veyon/Veyon Master.app"
"$APP/Contents/MacOS/veyon-cli" about

# nothing may be loaded from outside the bundle, as it wouldn't exist on other
# machines and a second copy of Qt crashes the process
SMOKE_LOG=$(mktemp)
status=0
DYLD_PRINT_LIBRARIES=1 "$APP/Contents/MacOS/veyon-cli" plugin list > "$SMOKE_LOG" 2>&1 || status=$?
grep -v '^dyld' "$SMOKE_LOG" || true
if grep -B 3 -E '^dyld.*(/opt/homebrew|/usr/local)/' "$SMOKE_LOG" ; then
	echo "Libraries were loaded from outside the bundle (see above)" >&2
	status=1
fi
exit $status
