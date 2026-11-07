#!/usr/bin/env bash
#
# build the libraries required by Veyon (except Qt) from source as universal
# binaries (arm64 + x86_64) for the universal macOS package
#
# usage: build-deps.sh <install prefix>
#
# required environment variables:
#   QT_ROOT_DIR               Qt installation to build QCA against
# optional environment variables:
#   MACOSX_DEPLOYMENT_TARGET  oldest supported macOS version (default: 12.0)
#   DEPS_WORK_DIR             directory for downloads and builds (default: /tmp/veyon-deps-build)
#
# The prefix is reused as long as it has been built by the same version of this script.
#

set -euo pipefail

PREFIX=$1
WORK_DIR=${DEPS_WORK_DIR:-/tmp/veyon-deps-build}
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0}
: "${QT_ROOT_DIR:?QT_ROOT_DIR has to point to a Qt installation}"

SCRIPT_HASH=$( (shasum -a 256 "$0"; echo "$MACOSX_DEPLOYMENT_TARGET $QT_ROOT_DIR") | shasum -a 256 | cut -d' ' -f1)
if [ "$(cat "$PREFIX/.build-hash" 2> /dev/null)" = "$SCRIPT_HASH" ] ; then
	echo "* Using existing dependencies in $PREFIX"
	exit 0
fi

rm -rf "$PREFIX" "$WORK_DIR"
mkdir -p "$PREFIX" "$WORK_DIR"

SRC_DIR="$WORK_DIR/src"
JOBS=$(sysctl -n hw.ncpu)

# download, verify and extract a source archive to $SRC_DIR
fetch()
{
	local url=$1 sha256=$2
	local archive
	archive="$WORK_DIR/$(basename "$url")"
	echo "* Fetching $url"
	curl -fsSL --retry 3 -o "$archive" "$url"
	echo "$sha256  $archive" | shasum -a 256 -c - > /dev/null
	rm -rf "$SRC_DIR"
	mkdir -p "$SRC_DIR"
	tar -xf "$archive" -C "$SRC_DIR" --strip-components 1
}

cmake_build()
{
	cmake -S "$SRC_DIR" -B "$SRC_DIR/build" -G Ninja \
		-DCMAKE_MAKE_PROGRAM="$(command -v ninja)" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_PREFIX_PATH="$PREFIX;$QT_ROOT_DIR" \
		-DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" \
		-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
		-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		"$@"
	cmake --build "$SRC_DIR/build"
	cmake --install "$SRC_DIR/build"
}


# image and compression libraries for LibVNCClient - linked statically

fetch https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.1/libjpeg-turbo-3.2.1.tar.gz \
	c27ad72a68da151177929aa969ae773a2da5ac2af9ce946079314fdac8cece7f
# the SIMD extensions can only be built for one architecture at a time
cmake_build -DENABLE_SHARED=OFF -DWITH_SIMD=OFF -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF

fetch https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.xz \
	d80dd2a38a37f803cb9b6ac7b14bd6e74ddc3b654780a8380bdf93523fdb4389
cmake_build -DPNG_SHARED=OFF -DPNG_FRAMEWORK=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_HARDWARE_OPTIMIZATIONS=OFF

fetch https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz \
	c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072
cmake_build -DENABLE_STATIC=ON -DENABLE_SHARED=OFF


# OpenSSL - built once per architecture and merged as its build system doesn't support universal builds

fetch https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz \
	603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
for arch in arm64 x86_64 ; do
	echo "* Building OpenSSL for $arch"
	rm -rf "$WORK_DIR/openssl-$arch"
	cp -R "$SRC_DIR" "$WORK_DIR/openssl-$arch"
	(
		cd "$WORK_DIR/openssl-$arch"
		./Configure "darwin64-$arch-cc" shared no-tests no-docs no-apps no-module no-legacy \
			--prefix="$PREFIX" --libdir=lib "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" > /dev/null
		make -j"$JOBS" > /dev/null
	)
done
make -C "$WORK_DIR/openssl-arm64" install_sw > /dev/null
for lib in libcrypto.3.dylib libssl.3.dylib ; do
	lipo -create "$WORK_DIR/openssl-arm64/$lib" "$WORK_DIR/openssl-x86_64/$lib" -output "$PREFIX/lib/$lib"
done
# the static libraries contain arm64 code only
rm -f "$PREFIX/lib/libcrypto.a" "$PREFIX/lib/libssl.a"


# QCA with the OpenSSL plugin only

fetch https://download.kde.org/stable/qca/2.3.12/qca-2.3.12.tar.xz \
	d4a2b3aa0272d73ea0c4cd2140960177fa34ddc2030e59a48ecfb80c757572c3
cmake_build -DBUILD_WITH_QT6=ON -DBUILD_TESTS=OFF -DBUILD_TOOLS=OFF -DBUILD_PLUGINS=ossl \
	-DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_USE_STATIC_LIBS=OFF


# all binaries have to contain both architectures
while IFS= read -r -d '' file ; do
	case "$(file -b "$file")" in
		*Mach-O*|*"ar archive"*)
			archs=" $(lipo -archs "$file") "
			if [[ "$archs" != *" arm64 "* || "$archs" != *" x86_64 "* ]] ; then
				echo "$file is not a universal binary (architectures:$archs)" >&2
				exit 1
			fi
			;;
	esac
done < <(find "$PREFIX/lib" -type f -print0)

rm -rf "$WORK_DIR"
echo "$SCRIPT_HASH" > "$PREFIX/.build-hash"
echo "* Dependencies installed to $PREFIX"
