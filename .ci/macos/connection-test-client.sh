#!/usr/bin/env bash
#
# connect from Veyon Master on macOS to a Veyon Server using key file authentication
#
# usage: connection-test-client.sh <package> <private key> <server address>
#

set -euo pipefail

PACKAGE=$1
PRIVATE_KEY=$2
SERVER=$3
PORT=11100
HERE=$(cd "$(dirname "$0")" && pwd)

fail() { echo "::error::$*"; exit 1; }

echo "::group::Install and configure Veyon Master"
sudo installer -pkg "$PACKAGE" -target /
sudo veyon-cli config import "$HERE/test-config.json"
sudo veyon-cli authkeys import teacher/private "$PRIVATE_KEY"
sudo veyon-cli authkeys setaccessgroup teacher/private staff
veyon-cli authkeys list details
echo "::endgroup::"

echo "::group::Wait for Veyon Server at $SERVER:$PORT"
for i in $(seq 120) ; do
	nc -z -G 5 "$SERVER" $PORT && break
	[ $i -eq 120 ] && fail "Veyon Server at $SERVER:$PORT not reachable"
	sleep 5
done
echo "::endgroup::"

echo "::group::Connect with the matching key"
veyon-cli feature start "$SERVER" ScreenLock || fail "connection/authentication with valid key failed"
sleep 2
veyon-cli feature stop "$SERVER" ScreenLock || fail "second connection with valid key failed"
echo "::endgroup::"

# must be the last test as the server temporarily blocks hosts after failed authentication attempts
echo "::group::Connect with a key unknown to the server"
sudo veyon-cli authkeys delete teacher/private
sudo veyon-cli authkeys create teacher
sudo veyon-cli authkeys setaccessgroup teacher/private staff
if veyon-cli feature start "$SERVER" ScreenLock ; then
	fail "connection succeeded with a key not known to the server"
fi
echo "Connection with unknown key was rejected as expected"
echo "::endgroup::"

echo
echo "Connection tests passed"
