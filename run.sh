#!/bin/bash
set -e

cd "$(dirname "$0")"

if [ -f ".env" ]; then
	set -a
	source .env
	set +a
fi

PORT=${PORT:-8080}
MCP_TRACE=${MCP_TRACE:-off}

export PORT MCP_TRACE

echo "Starting lunet-mcp-sse..."
echo "Port: $PORT"
echo "Trace: $MCP_TRACE"

LUNET_BIN="./bin/lunet"
LUA_CPATH="./lib/?.so;;"

export LUA_CPATH

if [ -f "$LUNET_BIN" ]; then
	exec "$LUNET_BIN" app/main.lua
else
	echo "ERROR: lunet binary not found at $LUNET_BIN"
	ls -la bin/ 2>/dev/null || true
	exit 1
fi
