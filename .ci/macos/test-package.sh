#!/usr/bin/env bash
#
# install the Veyon Master package and test its basic functionality
#
# usage: test-package.sh <package> [artifacts dir]
#

set -euo pipefail

PACKAGE=$1
ARTIFACTS=${2:-$PWD/test-artifacts}
HERE=$(cd "$(dirname "$0")" && pwd)

MASTER_APP="/Applications/Veyon/Veyon Master.app"
CONFIGURATOR_APP="/Applications/Veyon/Veyon Configurator.app"
KEYS_DIR="/Library/Application Support/Veyon/keys"
WORK=$(mktemp -d)

mkdir -p "$ARTIFACTS"

step() { echo; echo "::group::$*"; }
endstep() { echo "::endgroup::"; }
fail() { echo "::error::$*"; exit 1; }


step "Install package"
sudo installer -pkg "$PACKAGE" -target /
for path in "$MASTER_APP/Contents/MacOS/veyon-master" \
			"$MASTER_APP/Contents/MacOS/veyon-cli" \
			"$CONFIGURATOR_APP/Contents/MacOS/veyon-configurator" \
			/usr/local/bin/veyon-cli ; do
	[ -x "$path" ] || fail "missing executable: $path"
done
pkgutil --pkgs | grep -i veyon || fail "package receipt not found"
codesign --verify --deep --strict "$MASTER_APP" || fail "code signature of $MASTER_APP is invalid"
codesign --verify --deep --strict "$CONFIGURATOR_APP" || fail "code signature of $CONFIGURATOR_APP is invalid"
veyon-cli about
"$HERE/smoke-test.sh" "$MASTER_APP"
endstep


step "Plugins"
veyon-cli plugin list | tee "$WORK/plugins.txt"
# plugins every Master installation needs
for plugin in MacPlatformPlugin BuiltinDirectory AuthKeys RemoteAccess ScreenLock ; do
	grep -qx "$plugin" "$WORK/plugins.txt" || fail "plugin \"$plugin\" not loaded"
done
endstep


step "Configuration import"
sudo veyon-cli config clear
sudo veyon-cli config import "$HERE/test-config.json"
ls -l /Library/Preferences/ | grep -i veyon || fail "system configuration file not created"

# imported values have to be readable by both root and regular users
for runas in "sudo" "" ; do
	for keyvalue in Authentication/Method=1 Master/ComputerMonitoringUpdateInterval=2500 Network/VeyonServerPort=11100 ; do
		key=${keyvalue%=*}
		value=$($runas veyon-cli config get $key 2>&1 | tail -n 1)
		echo "$key (${runas:-user}): $value"
		[ "$value" = "${keyvalue#*=}" ] || fail "config get $key returned \"$value\" instead of ${keyvalue#*=}"
	done
	# loading the configuration must not produce any warnings
	if $runas veyon-cli config list 2>&1 | grep -i "cannot replace\|doesn't point" ; then
		fail "warnings while loading the configuration"
	fi
	$runas veyon-cli config export "$WORK/export-${runas:-user}.json"
	python3 - "$HERE/test-config.json" "$WORK/export-${runas:-user}.json" <<'EOF'
import json, sys
expected = json.load(open(sys.argv[1]))
exported = json.load(open(sys.argv[2]))
norm = lambda v: str(v).lower()
errors = []
for group, values in expected.items():
	for key, value in values.items():
		actual = exported.get(group, {}).get(key)
		if norm(actual) != norm(value):
			errors.append(f"{group}/{key}: expected {value!r}, got {actual!r}")
if errors:
	print("\n".join(errors))
	sys.exit(1)
print(f"all imported values found in {sys.argv[2]}")
EOF
done
cp "$WORK/export-user.json" "$ARTIFACTS/exported-config.json"
endstep


step "Authentication keys"
sudo veyon-cli authkeys create teacher
sudo veyon-cli authkeys setaccessgroup teacher/private staff
veyon-cli authkeys list details
veyon-cli authkeys list | tee "$WORK/keys.txt"
grep -qx "teacher/private" "$WORK/keys.txt" || fail "private key not listed"
grep -qx "teacher/public" "$WORK/keys.txt" || fail "public key not listed"
sudo ls -lR "$KEYS_DIR"

# the private key must only be readable by root and the access group
PERMS=$(sudo stat -f "%Sp %Sg" "$KEYS_DIR/private/teacher/key")
echo "private key permissions: $PERMS"
[[ "$PERMS" == -??????---* ]] || fail "private key is readable by others: $PERMS"
[[ "$PERMS" == *" staff" ]] || fail "private key not owned by access group staff: $PERMS"

# export/delete/import round trip of the public key
veyon-cli authkeys export teacher/public "$WORK/teacher_public_key.pem"
sudo veyon-cli authkeys delete teacher/public
veyon-cli authkeys list | grep -q "teacher/public" && fail "public key still listed after deletion"
sudo veyon-cli authkeys import teacher/public "$WORK/teacher_public_key.pem"
veyon-cli authkeys list | grep -q "teacher/public" || fail "public key not listed after import"

# the public key extracted from the private key has to match the original one
sudo veyon-cli authkeys delete teacher/public
sudo veyon-cli authkeys extract teacher
veyon-cli authkeys export teacher/public "$WORK/teacher_public_key_extracted.pem"
diff "$WORK/teacher_public_key.pem" "$WORK/teacher_public_key_extracted.pem" || fail "extracted public key differs"

# import of an externally created private key (e.g. exported on Windows/Linux)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$WORK/external_private_key.pem" 2>/dev/null
sudo veyon-cli authkeys import external/private "$WORK/external_private_key.pem"
sudo veyon-cli authkeys extract external
veyon-cli authkeys list | grep -q "external/public" || fail "imported external key not usable"
sudo veyon-cli authkeys delete external/private
sudo veyon-cli authkeys delete external/public
endstep


step "Veyon Master GUI"
"$MASTER_APP/Contents/MacOS/veyon-master" > "$ARTIFACTS/veyon-master.log" 2>&1 &
MASTER_PID=$!
sleep 15
screencapture -x "$ARTIFACTS/veyon-master.png" || echo "::warning::could not take screenshot"
if ! kill -0 $MASTER_PID 2>/dev/null ; then
	cat "$ARTIFACTS/veyon-master.log"
	wait $MASTER_PID && STATUS=0 || STATUS=$?
	fail "Veyon Master exited prematurely with status $STATUS"
fi
kill $MASTER_PID
wait $MASTER_PID || true
tail -n 50 "$ARTIFACTS/veyon-master.log"
endstep

echo
echo "All package tests passed"
