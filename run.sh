#!/bin/bash
set -e

cd "$(dirname "$0")"

VERBOSE=0
APP_ARGS=()
PASS_ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
		-v|--verbose)
			VERBOSE=1
			APP_ARGS+=("-v")
			shift
			;;
		*)
			PASS_ARGS+=("$1")
			shift
			;;
	esac
done

if [ -f ".env" ]; then
	set -a
	source .env
	set +a
fi

PORT=${PORT:-8080}
MCP_TRACE=${MCP_TRACE:-off}

export PORT MCP_TRACE

if [ "$VERBOSE" -eq 1 ]; then
	echo "Starting lunet-mcp-sse..."
	echo "Port: $PORT"
	echo "Trace: $MCP_TRACE"
fi

LUNET_BIN="./bin/lunet"
LUA_CPATH="./lib/?.so;;"

export LUA_CPATH

if [ -f "$LUNET_BIN" ]; then
	exec "$LUNET_BIN" app/main.lua "${APP_ARGS[@]}" "${PASS_ARGS[@]}"
else
	echo "ERROR: lunet binary not found at $LUNET_BIN"
	ls -la bin/ 2>/dev/null || true
	exit 1
fi
