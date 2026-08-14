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
LUNET_VERSION=${LUNET_VERSION:-v0.9.2}

export PORT MCP_TRACE

echo "Starting lunet-mcp-sse..."
echo "Port: $PORT"
echo "Trace: $MCP_TRACE"

LUNET_BIN=".lunet/${LUNET_VERSION}/lunet-run"
if [ ! -f "$LUNET_BIN" ] && [ -f "./bin/lunet" ]; then
	LUNET_BIN="./bin/lunet"
fi

if [ ! -f "$LUNET_BIN" ]; then
	echo "Lunet binary not found at $LUNET_BIN. Building/fetching runtime..."
	make build
fi

if [ -f "$LUNET_BIN" ]; then
	exec "$LUNET_BIN" app/main.lua "$@"
else
	echo "ERROR: lunet binary not found at $LUNET_BIN"
	exit 1
fi
