#!/bin/bash
# Simple Memory Benchmark for MCP-SSE Server
#
# Usage:
#   ./test/bench.sh [num_requests] [port]
#
# Example:
#   ./test/bench.sh 100 8080

set -e

NUM_REQUESTS=${1:-50}
PORT=${2:-8080}
HOST="127.0.0.1"
URL="http://${HOST}:${PORT}"

echo "MCP-SSE Memory Benchmark"
echo "========================"
echo "Requests: $NUM_REQUESTS"
echo "Target:   $URL"
echo ""

# Check server is running
if ! curl -s --max-time 2 "$URL/" >/dev/null 2>&1; then
	echo "ERROR: Server not running at $URL"
	echo "Start the server first: make run"
	exit 1
fi

# Get server PID (best effort)
SERVER_PID=$(lsof -i :$PORT -t 2>/dev/null | head -1 || echo "")

# Initial memory
if [ -n "$SERVER_PID" ]; then
	INITIAL_MEM=$(ps -o rss= -p $SERVER_PID 2>/dev/null | tr -d ' ')
	echo "Initial RSS: ${INITIAL_MEM:-unknown} KB"
else
	echo "Initial RSS: unknown (couldn't find server PID)"
fi

echo ""
echo "Running $NUM_REQUESTS sequential requests..."

START_TIME=$(date +%s)

for i in $(seq 1 $NUM_REQUESTS); do
	curl -s --max-time 5 "$URL/" >/dev/null
	if [ $((i % 10)) -eq 0 ]; then
		echo -n "."
	fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo ""

# Final memory
if [ -n "$SERVER_PID" ]; then
	FINAL_MEM=$(ps -o rss= -p $SERVER_PID 2>/dev/null | tr -d ' ')
	echo "Final RSS:   ${FINAL_MEM:-unknown} KB"

	if [ -n "$INITIAL_MEM" ] && [ -n "$FINAL_MEM" ]; then
		GROWTH=$((FINAL_MEM - INITIAL_MEM))
		echo "Growth:      $GROWTH KB"
	fi
else
	echo "Final RSS:   unknown"
fi

echo ""
echo "Requests:    $NUM_REQUESTS"
echo "Duration:    ${ELAPSED}s"

if [ $ELAPSED -gt 0 ]; then
	RPS=$((NUM_REQUESTS / ELAPSED))
	echo "Req/sec:     ~$RPS"
fi

echo ""
echo "Benchmark complete."
