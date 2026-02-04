#!/bin/bash
set -e

echo "=== Testing MCP-SSE Server ==="

echo ""
echo "1. Testing server info endpoint..."
INFO=$(curl -s http://localhost:8080/)
echo "$INFO" | head -20

echo ""
echo "2. Starting SSE session in background..."
curl -N http://localhost:8080/sse >/tmp/sse_output.txt 2>&1 &
SSE_PID=$!
sleep 1

echo ""
echo "3. Sending initialize request..."
INIT_RESP=$(curl -s -X POST "http://localhost:8080/message?session=test-session" \
	-H "Content-Type: application/json" \
	-d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"docker-test","version":"1.0"}}}')
echo "$INIT_RESP"

kill $SSE_PID 2>/dev/null || true

echo ""
echo "=== Test Complete ==="
