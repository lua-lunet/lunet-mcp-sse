#!/bin/bash
set -e

echo "=== MCP-SSE Docker Test Suite ==="
echo ""

SERVER_URL="http://localhost:8080"

echo "Test 1: Server Info"
INFO=$(curl -s "$SERVER_URL/")
if [ -n "$INFO" ]; then
	echo "  PASS: Server is responding"
	echo "  Info: $(echo "$INFO" | head -1)"
else
	echo "  FAIL: Server not responding"
	exit 1
fi

echo ""
echo "Test 2: SSE Endpoint"
SSE_CHECK=$(curl -s -I "$SERVER_URL/sse" | head -1)
if echo "$SSE_CHECK" | grep -q "200"; then
	echo "  PASS: SSE endpoint returns 200"
else
	echo "  FAIL: SSE endpoint error"
	exit 1
fi

echo ""
echo "Test 3: MCP Initialize"
INIT=$(curl -s -X POST "$SERVER_URL/message?session=test" \
	-H "Content-Type: application/json" \
	-d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
if echo "$INIT" | grep -q "jsonrpc"; then
	echo "  PASS: MCP Initialize returned valid JSON-RPC"
else
	echo "  FAIL: MCP Initialize failed"
	echo "  Response: $INIT"
fi

echo ""
echo "Test 4: Tools List"
TOOLS=$(curl -s -X POST "$SERVER_URL/message?session=test" \
	-H "Content-Type: application/json" \
	-d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')
if echo "$TOOLS" | grep -q "tools"; then
	echo "  PASS: Tools list returned valid response"
else
	echo "  FAIL: Tools list failed"
fi

echo ""
echo "Test 5: Tavily Search (if API key configured)"
if [ -n "$TAVILY_API_KEY" ]; then
	SEARCH=$(curl -s -X POST "$SERVER_URL/message?session=test" \
		-H "Content-Type: application/json" \
		-d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tavily-search","arguments":{"query":"test query","max_results":1}}}')
	echo "  Response: $(echo "$SEARCH" | head -c 200)"
else
	echo "  SKIP: TAVILY_API_KEY not set"
fi

echo ""
echo "=== All Tests Complete ==="
