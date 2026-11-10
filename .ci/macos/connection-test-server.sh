#!/usr/bin/env bash
#
# set up and run a Veyon Server on Linux for the macOS connection test
#
# usage: connection-test-server.sh start <veyon .deb> <public key> <log dir>
#        connection-test-server.sh wait-for-client <timeout seconds>
#        connection-test-server.sh stop <log dir>
#

set -euo pipefail

PORT=11100
SIGNAL_PORT=8000
HEADLESS_VNC_SERVER="{f626f759-7691-45c0-bd4a-37171d98d219}"
PID_FILE=/tmp/veyon-server.pid

case "$1" in
start)
	DEB=$2
	PUBLIC_KEY=$3
	LOGS=$4
	mkdir -p "$LOGS"

	echo "::group::Install Veyon"
	sudo apt-get update -q
	sudo apt-get install -y -q "$(realpath "$DEB")"
	# the server is started manually without a graphical session
	sudo systemctl disable --now veyon.service || true
	sudo pkill -f veyon-server || true
	veyon-cli about
	echo "::endgroup::"

	echo "::group::Configure Veyon Server"
	cat > /tmp/server-config.json <<EOF
{
	"Authentication": { "Method": 1 },
	"Logging": { "LogLevel": 5, "LogToStdErr": true, "LogFileDirectory": "$LOGS" },
	"Network": { "VeyonServerPort": $PORT, "FirewallExceptionEnabled": false },
	"VncServer": { "Plugin": "$HEADLESS_VNC_SERVER" }
}
EOF
	sudo veyon-cli config import /tmp/server-config.json
	sudo veyon-cli config list
	sudo veyon-cli authkeys import teacher/public "$PUBLIC_KEY"
	sudo veyon-cli authkeys list details
	echo "::endgroup::"

	echo "::group::Start Veyon Server"
	sudo env QT_QPA_PLATFORM=offscreen VEYON_SESSION_ID=0 \
		nohup veyon-server > "$LOGS/veyon-server-stdout.log" 2>&1 &
	echo $! > $PID_FILE
	for i in $(seq 60) ; do
		if ss -ltn | grep -q ":$PORT " ; then
			echo "Veyon Server listening on port $PORT"
			ss -ltnp | grep ":$PORT " || true
			echo "::endgroup::"
			exit 0
		fi
		sleep 1
	done
	cat "$LOGS"/*.log || true
	echo "::error::Veyon Server did not start listening on port $PORT"
	exit 1
	;;

wait-for-client)
	# the macOS job requests /done once it has finished its tests
	timeout "$2" python3 - $SIGNAL_PORT <<'EOF' || { echo "::error::client did not finish in time" ; exit 1 ; }
import http.server, sys
class Handler(http.server.BaseHTTPRequestHandler):
	def do_GET(self):
		self.send_response(200)
		self.end_headers()
		self.wfile.write(b"ok\n")
		if self.path == "/done":
			print(f"client {self.client_address[0]} finished")
			raise SystemExit(0)
http.server.HTTPServer(("0.0.0.0", int(sys.argv[1])), Handler).serve_forever()
EOF
	;;

stop)
	LOGS=$2
	sudo pkill -f veyon-server || true
	sudo chmod -R a+r "$LOGS" || true
	echo "::group::Veyon Server logs"
	cat "$LOGS"/*.log || true
	echo "::endgroup::"
	;;
esac
