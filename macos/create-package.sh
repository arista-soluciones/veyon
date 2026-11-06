#!/usr/bin/env bash
#
# create-package.sh - assemble the Veyon application bundles from a build tree
#                     and create a macOS installer package (.pkg)
#
# usage: create-package.sh <build dir> <output dir>
#
# optional environment variables:
#   MACDEPLOYQT              path to macdeployqt (default: from PATH)
#   QCA_OSSL_PLUGIN          path to the QCA OpenSSL plugin (default: searched in Homebrew prefix)
#   DEPLOY_LIBPATHS          colon-separated list of additional library search paths for macdeployqt
#   CODESIGN_IDENTITY        identity for signing the application bundles (default: "-" = ad-hoc)
#   INSTALLER_SIGN_IDENTITY  "Developer ID Installer" identity for signing the package (default: unsigned)
#

set -euo pipefail

SRC_DIR=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR=$(cd "$1" && pwd)
mkdir -p "$2"
OUTPUT_DIR=$(cd "$2" && pwd)

MACDEPLOYQT=${MACDEPLOYQT:-$(command -v macdeployqt)}
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:--}
INSTALLER_SIGN_IDENTITY=${INSTALLER_SIGN_IDENTITY:-}

VERSION=$(cat "$BUILD_DIR/macos/version")
STAGING_DIR="$BUILD_DIR/macos/staging"
PKG_ROOT="$STAGING_DIR/root"
APPS_DIR="$PKG_ROOT/Applications/Veyon"
MASTER_APP="$APPS_DIR/Veyon Master.app"
CONFIGURATOR_APP="$APPS_DIR/Veyon Configurator.app"
PKG_IDENTIFIER="io.veyon.master.pkg"

rm -rf "$STAGING_DIR"
mkdir -p "$APPS_DIR"


echo "* Installing build into application bundle"

cmake --install "$BUILD_DIR" --prefix "$MASTER_APP/Contents"
cp "$BUILD_DIR/macos/veyon-master.plist" "$MASTER_APP/Contents/Info.plist"
printf "APPL????" > "$MASTER_APP/Contents/PkgInfo"

# Qt's own translations imported at build time are not installed by CMake
mkdir -p "$MASTER_APP/Contents/Resources/translations"
find "$BUILD_DIR/translations" -maxdepth 1 -name "qt*.qm" -exec cp {} "$MASTER_APP/Contents/Resources/translations/" \;


echo "* Creating application icons"

create_icns()
{
	local svg=$1 icns=$2
	local iconset
	iconset="$STAGING_DIR/$(basename "$icns" .icns).iconset"
	mkdir -p "$iconset"
	for size in 16 32 128 256 512 ; do
		rsvg-convert -w $size -h $size "$svg" -o "$iconset/icon_${size}x${size}.png"
		rsvg-convert -w $((size*2)) -h $((size*2)) "$svg" -o "$iconset/icon_${size}x${size}@2x.png"
	done
	iconutil -c icns "$iconset" -o "$icns"
}

create_icns "$SRC_DIR/master/data/veyon-master.svg" "$MASTER_APP/Contents/Resources/veyon-master.icns"
create_icns "$SRC_DIR/configurator/data/veyon-configurator.svg" "$MASTER_APP/Contents/Resources/veyon-configurator.icns"


echo "* Adding QCA OpenSSL plugin"

if [ -z "${QCA_OSSL_PLUGIN:-}" ] && command -v brew > /dev/null ; then
	QCA_OSSL_PLUGIN=$(find -L "$(brew --prefix qca)" -name "libqca-ossl*.dylib" | head -n 1)
fi
if [ -z "${QCA_OSSL_PLUGIN:-}" ] || [ ! -f "$QCA_OSSL_PLUGIN" ] ; then
	echo "QCA OpenSSL plugin not found - set QCA_OSSL_PLUGIN" >&2
	exit 1
fi
mkdir -p "$MASTER_APP/Contents/PlugIns/crypto"
cp "$QCA_OSSL_PLUGIN" "$MASTER_APP/Contents/PlugIns/crypto/"


echo "* Deploying Qt and third-party libraries"

DEPLOY_ARGS=(-verbose=1 -always-overwrite)
while IFS= read -r -d '' binary ; do
	DEPLOY_ARGS+=("-executable=$binary")
done < <(find "$MASTER_APP/Contents/MacOS" "$MASTER_APP/Contents/PlugIns" -type f \( -perm -u+x -o -name "*.dylib" \) ! -name veyon-master -print0)

IFS=':' read -r -a libpaths <<< "${DEPLOY_LIBPATHS:-}"
for libpath in "${libpaths[@]}" ; do
	[ -n "$libpath" ] && DEPLOY_ARGS+=("-libpath=$libpath")
done

"$MACDEPLOYQT" "$MASTER_APP" "${DEPLOY_ARGS[@]}"


echo "* Bundling libraries missed by macdeployqt"

# macdeployqt can't resolve @rpath references across Homebrew's per-module Qt kegs (e.g.
# qtsvg's plugins -> QtSvg.framework) and misses some transitive references between libraries
FRAMEWORKS_DIR="$MASTER_APP/Contents/Frameworks"
BUNDLED_LIBRARY_PREFIX="@executable_path/../Frameworks"

LIBRARY_SEARCH_DIRS=(${libpaths[@]+"${libpaths[@]}"})
if command -v brew > /dev/null ; then
	LIBRARY_SEARCH_DIRS+=("$(brew --prefix)"/opt/*/lib)
fi

find_library()
{
	local relativePath=$1 dir
	for dir in ${LIBRARY_SEARCH_DIRS[@]+"${LIBRARY_SEARCH_DIRS[@]}"} ; do
		if [ -e "$dir/$relativePath" ] ; then
			echo "$dir/$relativePath"
			return 0
		fi
	done
	return 1
}

# path of a library relative to the Frameworks directory, e.g. libfoo.1.dylib or Foo.framework/Versions/A/Foo
bundle_relative_path()
{
	local path=$1 frameworkPrefix
	case "$path" in
	*.framework/*)
		frameworkPrefix=${path%%.framework/*}
		echo "${frameworkPrefix##*/}.framework/${path#*.framework/}"
		;;
	*)
		echo "${path##*/}"
		;;
	esac
}

bundle_library()
{
	local sourcePath=$1 relativePath=$2 frameworkName sourceFramework
	local targetPath="$FRAMEWORKS_DIR/$relativePath"

	if [ -e "$targetPath" ] ; then
		return 0
	fi

	echo "Bundling $sourcePath"

	case "$relativePath" in
	*.framework/*)
		frameworkName=${relativePath%%/*}
		sourceFramework=${sourcePath%"/${relativePath#*/}"}
		ditto "$(cd -P "$sourceFramework" && pwd)" "$FRAMEWORKS_DIR/$frameworkName"
		chmod -R u+w "$FRAMEWORKS_DIR/$frameworkName"
		rm -rf "$FRAMEWORKS_DIR/$frameworkName/Headers" "$FRAMEWORKS_DIR/$frameworkName"/Versions/*/Headers
		;;
	*)
		mkdir -p "$(dirname "$targetPath")"
		cp -L "$sourcePath" "$targetPath"
		chmod u+w "$targetPath"
		;;
	esac

	install_name_tool -id "$BUNDLED_LIBRARY_PREFIX/$relativePath" "$targetPath"
}

# all files which may be Mach-O binaries - framework binaries are not marked as executable
find_bundle_binaries()
{
	find "$MASTER_APP/Contents/MacOS" "$MASTER_APP/Contents/Frameworks" "$MASTER_APP/Contents/PlugIns" \
		-type f ! -name "*.plist" ! -name "*.prl" ! -name "*.xcprivacy" -print0
}

# repeat as newly bundled libraries can have dependencies on their own
bundleChanged=1
while [ "$bundleChanged" -ne 0 ] ; do
	bundleChanged=0

	while IFS= read -r -d '' binary ; do
		# otool fails for everything that is not a Mach-O binary
		dependencies=$(otool -L "$binary" 2> /dev/null | awk 'NR > 1 { print $1 }') || continue
		libraryId=$(otool -D "$binary" 2> /dev/null | awk 'NR == 2 { print $1 }') || continue

		case "$libraryId" in
		/opt/*|/usr/local/*)
			chmod u+w "$binary"
			install_name_tool -id "$BUNDLED_LIBRARY_PREFIX/$(bundle_relative_path "$libraryId")" "$binary"
			bundleChanged=1
			;;
		esac

		for dependency in $dependencies ; do
			if [ "$dependency" = "$libraryId" ] ; then
				continue
			fi

			case "$dependency" in
			/opt/*|/usr/local/*)
				relativePath=$(bundle_relative_path "$dependency")
				sourcePath=$dependency
				;;
			@rpath/*)
				relativePath=${dependency#@rpath/}
				if [ -e "$FRAMEWORKS_DIR/$relativePath" ] ; then
					continue
				fi
				if ! sourcePath=$(find_library "$relativePath") ; then
					echo "Could not find $dependency referenced by $binary" >&2
					exit 1
				fi
				;;
			*)
				continue
				;;
			esac

			bundle_library "$sourcePath" "$relativePath"
			chmod u+w "$binary"
			install_name_tool -change "$dependency" "$BUNDLED_LIBRARY_PREFIX/$relativePath" "$binary"
			bundleChanged=1
		done
	done < <(find_bundle_binaries)
done

# make sure nothing references libraries outside the bundle or the system
unresolved=""
while IFS= read -r -d '' binary ; do
	dependencies=$(otool -L "$binary" 2> /dev/null | awk 'NR > 1 { print $1 }') || continue
	for dependency in $dependencies ; do
		case "$dependency" in
		/opt/*|/usr/local/*)
			unresolved+="$binary -> $dependency"$'\n'
			;;
		@rpath/*)
			if [ ! -e "$FRAMEWORKS_DIR/${dependency#@rpath/}" ] ; then
				unresolved+="$binary -> $dependency"$'\n'
			fi
			;;
		esac
	done
done < <(find_bundle_binaries)
if [ -n "$unresolved" ] ; then
	echo "Unresolved non-system library references:" >&2
	echo "$unresolved" >&2
	exit 1
fi


echo "* Creating Veyon Configurator application bundle"

ditto "$MASTER_APP" "$CONFIGURATOR_APP"
cp "$BUILD_DIR/macos/veyon-configurator.plist" "$CONFIGURATOR_APP/Contents/Info.plist"


echo "* Signing application bundles (identity: $CODESIGN_IDENTITY)"

CODESIGN_ARGS=(--force --sign "$CODESIGN_IDENTITY")
if [ "$CODESIGN_IDENTITY" != "-" ] ; then
	CODESIGN_ARGS+=(--options runtime --timestamp)
fi

sign_bundle()
{
	local app=$1 mainExecutable=$2

	# sign nested code first (inside-out), the bundle itself last
	find "$app/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 | xargs -0 -n 1 codesign "${CODESIGN_ARGS[@]}"
	find "$app/Contents/Frameworks" "$app/Contents/PlugIns" -type f -name "*.dylib" -print0 | xargs -0 codesign "${CODESIGN_ARGS[@]}"
	find "$app/Contents/MacOS" -type f ! -name "$mainExecutable" -print0 | xargs -0 codesign "${CODESIGN_ARGS[@]}"
	codesign "${CODESIGN_ARGS[@]}" "$app"
	codesign --verify --deep --strict --verbose=2 "$app"
}

sign_bundle "$MASTER_APP" veyon-master
sign_bundle "$CONFIGURATOR_APP" veyon-configurator


echo "* Building installer package"

ARCHITECTURES=$(lipo -archs "$MASTER_APP/Contents/MacOS/veyon-master")
MIN_OS_VERSION=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$MASTER_APP/Contents/Info.plist")

COMPONENT_PLIST="$STAGING_DIR/components.plist"
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENT_PLIST"
# always install to /Applications/Veyon instead of updating copies of the bundles found elsewhere
i=0
while /usr/libexec/PlistBuddy -c "Set :$i:BundleIsRelocatable false" "$COMPONENT_PLIST" 2> /dev/null ; do
	i=$((i+1))
done

pkgbuild --root "$PKG_ROOT" \
	--component-plist "$COMPONENT_PLIST" \
	--scripts "$SRC_DIR/macos/pkg/scripts" \
	--identifier "$PKG_IDENTIFIER" \
	--version "$VERSION" \
	--install-location / \
	"$STAGING_DIR/veyon-master.pkg"

RESOURCES_DIR="$STAGING_DIR/resources"
mkdir -p "$RESOURCES_DIR"
cp "$SRC_DIR/COPYING" "$RESOURCES_DIR/license.txt"

cat > "$STAGING_DIR/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
	<title>Veyon Master $VERSION</title>
	<license file="license.txt"/>
	<options customize="never" require-scripts="false" hostArchitectures="${ARCHITECTURES// /,}"/>
	<domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
	<volume-check>
		<allowed-os-versions>
			<os-version min="$MIN_OS_VERSION"/>
		</allowed-os-versions>
	</volume-check>
	<choices-outline>
		<line choice="default">
			<line choice="$PKG_IDENTIFIER"/>
		</line>
	</choices-outline>
	<choice id="default"/>
	<choice id="$PKG_IDENTIFIER" visible="false">
		<pkg-ref id="$PKG_IDENTIFIER"/>
	</choice>
	<pkg-ref id="$PKG_IDENTIFIER" version="$VERSION" onConclusion="none">veyon-master.pkg</pkg-ref>
</installer-gui-script>
EOF

PRODUCTBUILD_ARGS=(--distribution "$STAGING_DIR/distribution.xml" --resources "$RESOURCES_DIR" --package-path "$STAGING_DIR")
if [ -n "$INSTALLER_SIGN_IDENTITY" ] ; then
	PRODUCTBUILD_ARGS+=(--sign "$INSTALLER_SIGN_IDENTITY" --timestamp)
fi

PACKAGE="$OUTPUT_DIR/veyon-master-$VERSION-macos-${ARCHITECTURES// /-}.pkg"
productbuild "${PRODUCTBUILD_ARGS[@]}" "$PACKAGE"

echo "* Created $PACKAGE"
