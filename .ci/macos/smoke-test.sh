#!/usr/bin/env bash
#
# smoke test for the Veyon Master application bundle: veyon-cli has to run and load
# all plugins without loading any library from outside the bundle or the system, as
# these wouldn't exist on other machines (and a second copy of Qt crashes the process)
#
# usage: smoke-test.sh <path to Veyon Master.app>
#

set -euo pipefail

APP=$(cd "$1" && pwd -P)

# set by Qt installations (e.g. on CI machines) but not on the users' machines
unset QT_PLUGIN_PATH QT_QPA_PLATFORM_PLUGIN_PATH QML2_IMPORT_PATH
CLI="$APP/Contents/MacOS/veyon-cli"

"$CLI" about

LOG=$(mktemp)
status=0
DYLD_PRINT_LIBRARIES=1 "$CLI" plugin list > "$LOG" 2>&1 || status=$?
grep -v '^dyld' "$LOG" || true

if ! grep -q '^MacPlatformPlugin' "$LOG" ; then
	echo "The macOS platform plugin has not been loaded" >&2
	status=1
fi

foreign=$(sed -nE 's/^dyld\[[0-9]+\]: <[^>]*> //p' "$LOG" |
		  grep -v -E '^(/usr/lib/|/System/)' | grep -v -F "$APP/" || true)
if [ -n "$foreign" ] ; then
	echo "Libraries loaded from outside the bundle:" >&2
	echo "$foreign" >&2
	status=1
fi

rm -f "$LOG"
exit $status
