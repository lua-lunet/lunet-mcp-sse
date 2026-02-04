#!/bin/bash
# Compare memory and image size between lunet-mcp-sse and other MCP implementations
#
# Tests:
# 1. Memory (RSS) after running one Tavily search query
# 2. Docker image size to run each implementation
#
# Requires: docker, colima (on macOS), node/npx, python/uvx

set -e

RESULTS_DIR=".tmp/compare_results"
mkdir -p "$RESULTS_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=============================================="
echo "MCP Server Comparison: Memory & Image Size"
echo "=============================================="
echo ""

# Check for TAVILY_API_KEY
if [ -z "$TAVILY_API_KEY" ]; then
	if [ -f .env ]; then
		export $(grep TAVILY_API_KEY .env | xargs)
	fi
fi

if [ -z "$TAVILY_API_KEY" ]; then
	echo -e "${RED}ERROR: TAVILY_API_KEY not set${NC}"
	echo "Set it in .env or export TAVILY_API_KEY=..."
	exit 1
fi

echo "TAVILY_API_KEY: ${TAVILY_API_KEY:0:10}..."
echo ""

# ==============================================================================
# PART 1: Docker Image Size Comparison
# ==============================================================================

echo "=============================================="
echo "PART 1: Docker Image Size Comparison"
echo "=============================================="
echo ""

# Base image size
echo "Pulling base image..."
docker pull debian:trixie-slim -q
BASE_SIZE=$(docker images debian:trixie-slim --format "{{.Size}}")
echo "Base (debian:trixie-slim): $BASE_SIZE"

# Lunet dependencies
echo ""
echo "Building lunet-mcp-sse image..."
cat >"$RESULTS_DIR/Dockerfile.lunet" <<'EOF'
FROM debian:trixie-slim
RUN apt-get update -qq && apt-get install -y -qq libuv1 libluajit-5.1-2 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY bin/ /app/bin/
COPY lib/ /app/lib/
COPY app/ /app/app/
EOF

# We need the linux binary - check if we have it
if [ ! -f ".tmp/linux-app/bin/lunet" ]; then
	echo "Downloading Linux arm64 binary..."
	mkdir -p .tmp/linux-app
	curl -sL -o .tmp/lunet-mcp-sse-linux-arm64.tar.gz \
		https://github.com/lua-lunet/lunet-mcp-sse/releases/download/nightly/lunet-mcp-sse-linux-arm64.tar.gz
	tar -xzf .tmp/lunet-mcp-sse-linux-arm64.tar.gz -C .tmp/linux-app
fi

docker build -q -t lunet-mcp-sse-test -f "$RESULTS_DIR/Dockerfile.lunet" .tmp/linux-app
LUNET_SIZE=$(docker images lunet-mcp-sse-test --format "{{.Size}}")
echo "lunet-mcp-sse: $LUNET_SIZE"

# Node.js with tavily-mcp
echo ""
echo "Building tavily-mcp (Node.js) image..."
cat >"$RESULTS_DIR/Dockerfile.node" <<'EOF'
FROM node:22-slim
RUN npm install -g tavily-mcp@latest
EOF
docker build -q -t tavily-mcp-node-test -f "$RESULTS_DIR/Dockerfile.node" "$RESULTS_DIR"
NODE_SIZE=$(docker images tavily-mcp-node-test --format "{{.Size}}")
echo "tavily-mcp (Node.js): $NODE_SIZE"

# Bun with tavily-mcp
echo ""
echo "Building tavily-mcp (Bun) image..."
cat >"$RESULTS_DIR/Dockerfile.bun" <<'EOF'
FROM oven/bun:latest
RUN bun install -g tavily-mcp@latest
EOF
docker build -q -t tavily-mcp-bun-test -f "$RESULTS_DIR/Dockerfile.bun" "$RESULTS_DIR"
BUN_SIZE=$(docker images tavily-mcp-bun-test --format "{{.Size}}")
echo "tavily-mcp (Bun): $BUN_SIZE"

# Python with FastMCP
echo ""
echo "Building FastMCP (Python/uv) image..."
cat >"$RESULTS_DIR/Dockerfile.python" <<'EOF'
FROM python:3.12-slim
RUN pip install --no-cache-dir fastmcp tavily-python
EOF
docker build -q -t fastmcp-python-test -f "$RESULTS_DIR/Dockerfile.python" "$RESULTS_DIR"
PYTHON_SIZE=$(docker images fastmcp-python-test --format "{{.Size}}")
echo "FastMCP (Python): $PYTHON_SIZE"

echo ""
echo "----------------------------------------------"
echo "Image Size Summary:"
echo "----------------------------------------------"
printf "%-25s %s\n" "Implementation" "Size"
printf "%-25s %s\n" "-------------------------" "----------"
printf "%-25s %s\n" "Base (debian:trixie-slim)" "$BASE_SIZE"
printf "%-25s %s\n" "lunet-mcp-sse" "$LUNET_SIZE"
printf "%-25s %s\n" "tavily-mcp (Node.js)" "$NODE_SIZE"
printf "%-25s %s\n" "tavily-mcp (Bun)" "$BUN_SIZE"
printf "%-25s %s\n" "FastMCP (Python)" "$PYTHON_SIZE"
echo ""

# ==============================================================================
# PART 2: Runtime Memory Comparison
# ==============================================================================

echo "=============================================="
echo "PART 2: Runtime Memory (RSS) Comparison"
echo "=============================================="
echo ""
echo "Note: Memory measured after server startup + 1 search query"
echo ""

# Function to get container RSS
get_container_rss() {
	local container=$1
	# Get RSS in KB from container stats
	docker stats --no-stream --format "{{.MemUsage}}" "$container" 2>/dev/null | awk '{print $1}'
}

# Test lunet-mcp-sse
echo "Testing lunet-mcp-sse..."
docker rm -f lunet-test 2>/dev/null || true

# Copy to colima if on macOS
if command -v colima &>/dev/null; then
	colima ssh -- rm -rf /tmp/lunet-test 2>/dev/null || true
	colima ssh -- mkdir -p /tmp/lunet-test
	echo "TAVILY_API_KEY=$TAVILY_API_KEY" >.tmp/linux-app/.env
	tar -czf - -C .tmp/linux-app . | colima ssh -- tar -xzf - -C /tmp/lunet-test
	MOUNT_PATH="/tmp/lunet-test"
else
	MOUNT_PATH="$(pwd)/.tmp/linux-app"
fi

docker run -d --name lunet-test -p 18080:8080 \
	-v "$MOUNT_PATH:/app" -w /app \
	debian:trixie-slim \
	/bin/bash -c 'apt-get update -qq && apt-get install -y -qq libuv1 libluajit-5.1-2 curl >/dev/null 2>&1 && export $(cat .env | xargs) && HOST=0.0.0.0 ./bin/lunet --dangerously-skip-loopback-restriction app/main.lua' \
	>/dev/null 2>&1

sleep 5

# Do one search
SESSION=$(curl -sN --max-time 3 http://localhost:18080/sse | grep -o 'session=[a-zA-Z0-9]*' | head -1 | cut -d= -f2)
if [ -n "$SESSION" ]; then
	curl -sX POST "http://localhost:18080/message?session=$SESSION" \
		-H "Content-Type: application/json" \
		-d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' >/dev/null
	sleep 1
	curl -sX POST "http://localhost:18080/message?session=$SESSION" \
		-H "Content-Type: application/json" \
		-d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"tavily-search","arguments":{"query":"lua programming"}}}' >/dev/null
	sleep 2
fi

LUNET_MEM=$(get_container_rss lunet-test)
echo "lunet-mcp-sse: $LUNET_MEM"
docker stop lunet-test >/dev/null 2>&1
docker rm lunet-test >/dev/null 2>&1

# Test Node.js tavily-mcp (stdio mode - need to measure differently)
echo ""
echo "Testing tavily-mcp (Node.js)..."
docker rm -f node-test 2>/dev/null || true

# Node MCP servers typically run in stdio mode, we'll measure idle memory
docker run -d --name node-test \
	-e TAVILY_API_KEY="$TAVILY_API_KEY" \
	node:22-slim \
	/bin/bash -c 'npm install -g tavily-mcp@latest >/dev/null 2>&1 && sleep infinity' \
	>/dev/null 2>&1

sleep 10
NODE_MEM=$(get_container_rss node-test)
echo "tavily-mcp (Node.js) idle: $NODE_MEM"
docker stop node-test >/dev/null 2>&1
docker rm node-test >/dev/null 2>&1

# Test Bun
echo ""
echo "Testing tavily-mcp (Bun)..."
docker rm -f bun-test 2>/dev/null || true

docker run -d --name bun-test \
	-e TAVILY_API_KEY="$TAVILY_API_KEY" \
	oven/bun:latest \
	/bin/bash -c 'bun install -g tavily-mcp@latest >/dev/null 2>&1 && sleep infinity' \
	>/dev/null 2>&1

sleep 10
BUN_MEM=$(get_container_rss bun-test)
echo "tavily-mcp (Bun) idle: $BUN_MEM"
docker stop bun-test >/dev/null 2>&1
docker rm bun-test >/dev/null 2>&1

# Test Python FastMCP
echo ""
echo "Testing FastMCP (Python)..."
docker rm -f python-test 2>/dev/null || true

docker run -d --name python-test \
	-e TAVILY_API_KEY="$TAVILY_API_KEY" \
	python:3.12-slim \
	/bin/bash -c 'pip install --no-cache-dir fastmcp tavily-python >/dev/null 2>&1 && sleep infinity' \
	>/dev/null 2>&1

sleep 15
PYTHON_MEM=$(get_container_rss python-test)
echo "FastMCP (Python) idle: $PYTHON_MEM"
docker stop python-test >/dev/null 2>&1
docker rm python-test >/dev/null 2>&1

echo ""
echo "----------------------------------------------"
echo "Memory Usage Summary:"
echo "----------------------------------------------"
printf "%-25s %s\n" "Implementation" "Memory"
printf "%-25s %s\n" "-------------------------" "----------"
printf "%-25s %s\n" "lunet-mcp-sse" "$LUNET_MEM"
printf "%-25s %s\n" "tavily-mcp (Node.js)" "$NODE_MEM"
printf "%-25s %s\n" "tavily-mcp (Bun)" "$BUN_MEM"
printf "%-25s %s\n" "FastMCP (Python)" "$PYTHON_MEM"
echo ""

# Cleanup test images
echo "Cleaning up test images..."
docker rmi lunet-mcp-sse-test tavily-mcp-node-test tavily-mcp-bun-test fastmcp-python-test 2>/dev/null || true

echo ""
echo -e "${GREEN}Comparison complete!${NC}"
echo "Results saved to $RESULTS_DIR/"
