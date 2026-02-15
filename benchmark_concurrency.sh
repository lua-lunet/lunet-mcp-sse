#!/bin/bash
# MCP Server Concurrency Benchmark
#
# Compares concurrency handling across different MCP implementations:
# - lunet-mcp-sse (Lua + libuv)
# - Node.js tavily-mcp
# - Python FastMCP
# - Bun tavily-mcp
#
# Prerequisites:
# - hey (HTTP load testing tool): brew install hey
# - jq
# - Mock Tavily server running on MOCK_PORT
#
# Usage:
#   ./benchmark_concurrency.sh [implementation] [concurrency] [total_requests]

set -e

# Configuration
MOCK_PORT=${MOCK_PORT:-19999}
CONCURRENCY=${2:-50}
TOTAL_REQUESTS=${3:-500}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[BENCH]${NC} $*"; }
success() { echo -e "${GREEN}[BENCH]${NC} $*"; }
warn() { echo -e "${YELLOW}[BENCH]${NC} $*"; }
error() { echo -e "${RED}[BENCH]${NC} $*"; }

# Check prerequisites
check_prereqs() {
	log "Checking prerequisites..."

	if ! command -v hey &>/dev/null; then
		error "'hey' not found. Install with: brew install hey"
		exit 1
	fi

	if ! command -v jq &>/dev/null; then
		error "'jq' not found. Install with: brew install jq"
		exit 1
	fi

	# Check mock server
	if ! curl -s "http://localhost:$MOCK_PORT/health" &>/dev/null; then
		error "Mock Tavily server not running on port $MOCK_PORT"
		echo "Start it with: nginx -c \"\$(pwd)/.tmp/mock-tavily/nginx.conf\""
		exit 1
	fi

	success "Prerequisites OK"
}

# Get process memory (RSS in KB)
get_rss() {
	local pid=$1
	if [[ "$(uname)" == "Darwin" ]]; then
		ps -o rss= -p "$pid" 2>/dev/null | tr -d ' '
	else
		cat /proc/"$pid"/status 2>/dev/null | grep VmRSS | awk '{print $2}'
	fi
}

# Establish SSE session and return session ID
get_session() {
	local port=$1
	local timeout=${2:-2}

	# Connect to SSE endpoint and extract session ID
	# Use -m for timeout, SSE will hang until timeout but we get first event
	local response
	response=$(curl -s -m "$timeout" "http://localhost:$port/sse" 2>&1) || true

	echo "$response" | grep -o 'session=[a-zA-Z0-9]*' | head -1 | cut -d= -f2
}

# Send MCP initialize
mcp_initialize() {
	local port=$1
	local session=$2

	curl -s -X POST "http://localhost:$port/message?session=$session" \
		-H "Content-Type: application/json" \
		-d '{
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "benchmark", "version": "1.0"}
            }
        }' 2>/dev/null
}

# Run benchmark against a running MCP server
benchmark_server() {
	local name=$1
	local port=$2
	local pid=$3

	log "Benchmarking $name on port $port (PID: $pid)"

	# Get baseline memory
	local mem_before
	mem_before=$(get_rss "$pid")

	# Get a session
	local session
	session=$(get_session "$port")
	if [[ -z "$session" ]]; then
		error "Failed to get session from $name"
		return 1
	fi
	log "Session: $session"

	# Initialize the session
	mcp_initialize "$port" "$session" >/dev/null

	# Prepare the request body (tools/call tavily-search)
	local body='{"jsonrpc":"2.0","id":999,"method":"tools/call","params":{"name":"tavily-search","arguments":{"query":"test query"}}}'

	# Create temp file for body
	local body_file
	body_file=$(mktemp)
	echo "$body" >"$body_file"

	log "Running: $TOTAL_REQUESTS requests, $CONCURRENCY concurrent"

	# Run hey benchmark
	local result
	result=$(hey -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" \
		-m POST \
		-H "Content-Type: application/json" \
		-D "$body_file" \
		"http://localhost:$port/message?session=$session" 2>&1)

	rm -f "$body_file"

	# Get memory after
	local mem_after
	mem_after=$(get_rss "$pid")

	# Parse results from hey output
	local rps latency_avg latency_p99 errors
	rps=$(echo "$result" | grep "Requests/sec:" | awk '{print $2}')
	latency_avg=$(echo "$result" | grep -A1 "Latency" | tail -1 | awk '{print $2}')
	latency_p99=$(echo "$result" | grep "99% in" | awk '{print $3}')

	# Count errors from Status code distribution
	local status_200
	status_200=$(echo "$result" | grep "200" | awk '{print $2}' | head -1)
	if [[ -n "$status_200" ]]; then
		errors=$((TOTAL_REQUESTS - status_200))
	else
		errors=$(echo "$result" | grep -c "Error\|error" || echo 0)
	fi

	# Calculate memory delta
	local mem_delta=0
	if [[ -n "$mem_before" && -n "$mem_after" ]]; then
		mem_delta=$((mem_after - mem_before))
	fi

	# Output results
	echo ""
	echo "═══════════════════════════════════════════════════════════"
	echo "  $name Results"
	echo "═══════════════════════════════════════════════════════════"
	echo "  Requests/sec:     $rps"
	echo "  Avg Latency:      $latency_avg"
	echo "  P99 Latency:      $latency_p99"
	echo "  Errors:           $errors"
	echo "  Memory Before:    ${mem_before:-N/A} KB"
	echo "  Memory After:     ${mem_after:-N/A} KB"
	echo "  Memory Delta:     ${mem_delta} KB"
	echo "═══════════════════════════════════════════════════════════"
	echo ""

	# Return as JSON for comparison
	echo "{\"name\":\"$name\",\"rps\":$rps,\"latency_avg\":\"$latency_avg\",\"latency_p99\":\"$latency_p99\",\"errors\":$errors,\"mem_before\":${mem_before:-0},\"mem_after\":${mem_after:-0}}"
}

# Start lunet server
start_lunet() {
	local port=${1:-8080}
	log "Starting lunet-mcp-sse on port $port..."

	cd "$(dirname "$0")"

	# Prefer release bundle binary; otherwise resolve/build lunet-run via xmake.
	local lunet_bin
	if [[ -x ".tmp/macos-app/bin/lunet" ]]; then
		lunet_bin=".tmp/macos-app/bin/lunet"
	else
		lunet_bin=$(LUNET_DIR="${LUNET_DIR:-../lunet}" LUNET_VERSION="${LUNET_VERSION:-v0.2.3}" ./scripts/lunet_bin.sh --build 2>/dev/null || true)
	fi
	if [[ -z "$lunet_bin" ]]; then
		error "No lunet binary found (.tmp bundle or xmake-built lunet-run)"
		return 1
	fi

	TAVILY_API_URL="http://localhost:$MOCK_PORT/search" \
		PORT=$port \
		"$lunet_bin" app/main.lua &
	local pid=$!

	sleep 1

	if ! kill -0 "$pid" 2>/dev/null; then
		error "lunet failed to start"
		return 1
	fi

	echo "$pid"
}

# Start Node.js tavily-mcp (requires npx)
start_nodejs() {
	local port=${1:-8081}
	log "Starting Node.js tavily-mcp on port $port..."

	# Check if we have a wrapper that supports mock URL
	# The official tavily-mcp doesn't support custom API URL, so we need to mock differently
	# For now, skip if not available

	warn "Node.js tavily-mcp doesn't support custom API URL"
	warn "Skipping Node.js benchmark (would need to patch the package)"
	return 1
}

# Benchmark all implementations
benchmark_all() {
	check_prereqs

	local results=()

	# Benchmark lunet
	log "=== Testing lunet-mcp-sse ==="
	local lunet_pid
	lunet_pid=$(start_lunet 8080)
	if [[ -n "$lunet_pid" ]]; then
		sleep 2 # Let server stabilize
		local result
		result=$(benchmark_server "lunet-mcp-sse" 8080 "$lunet_pid")
		results+=("$result")
		kill "$lunet_pid" 2>/dev/null || true
		wait "$lunet_pid" 2>/dev/null || true
	fi

	# Summary
	echo ""
	echo "╔═══════════════════════════════════════════════════════════╗"
	echo "║              CONCURRENCY BENCHMARK SUMMARY                ║"
	echo "╠═══════════════════════════════════════════════════════════╣"
	echo "║  Concurrency: $CONCURRENCY concurrent connections"
	echo "║  Total:       $TOTAL_REQUESTS requests"
	echo "║  Mock Server: localhost:$MOCK_PORT"
	echo "╚═══════════════════════════════════════════════════════════╝"
}

# Benchmark a single running server
benchmark_single() {
	local port=${1:-8080}
	local name=${2:-"MCP Server"}

	check_prereqs

	# Find the server PID
	local pid
	pid=$(lsof -ti :"$port" 2>/dev/null | head -1)

	if [[ -z "$pid" ]]; then
		error "No server running on port $port"
		exit 1
	fi

	benchmark_server "$name" "$port" "$pid"
}

# Main
case "${1:-all}" in
all)
	benchmark_all
	;;
lunet)
	benchmark_single 8080 "lunet-mcp-sse"
	;;
single)
	benchmark_single "${2:-8080}" "${3:-MCP Server}"
	;;
*)
	echo "Usage: $0 [all|lunet|single <port> <name>]"
	echo ""
	echo "Commands:"
	echo "  all              - Benchmark all implementations"
	echo "  lunet            - Benchmark running lunet server on port 8080"
	echo "  single <port>    - Benchmark any server on specified port"
	echo ""
	echo "Environment:"
	echo "  MOCK_PORT        - Mock Tavily server port (default: 19999)"
	echo "  CONCURRENCY      - Concurrent connections (default: 50)"
	echo "  TOTAL_REQUESTS   - Total requests to send (default: 500)"
	;;
esac
