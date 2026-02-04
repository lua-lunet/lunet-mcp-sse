#!/bin/bash
# Test Tavily search via MCP-SSE

set -e

HOST=${1:-localhost}
PORT=${2:-8080}

echo "Testing MCP-SSE Tavily server at $HOST:$PORT"
echo ""

# Create a temp file for SSE output
SSE_OUT=$(mktemp)
trap "rm -f $SSE_OUT; pkill -f 'curl.*sse' 2>/dev/null || true" EXIT

# Start SSE connection in background
curl -sN "http://$HOST:$PORT/sse" >"$SSE_OUT" &
SSE_PID=$!
sleep 1

# Get session ID
SESSION=$(grep -o 'session=[a-zA-Z0-9]*' "$SSE_OUT" | head -1 | cut -d= -f2)
if [ -z "$SESSION" ]; then
	echo "ERROR: No session ID received"
	exit 1
fi
echo "Session: $SESSION"

# Initialize
echo "Initializing..."
curl -sX POST "http://$HOST:$PORT/message?session=$SESSION" \
	-H "Content-Type: application/json" \
	-d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
sleep 1

# Search
echo ""
echo "Searching for 'lua programming language'..."
curl -sX POST "http://$HOST:$PORT/message?session=$SESSION" \
	-H "Content-Type: application/json" \
	-d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"tavily-search","arguments":{"query":"lua programming language"}}}'

# Wait for response
sleep 5

echo ""
echo "SSE Response:"
cat "$SSE_OUT"
