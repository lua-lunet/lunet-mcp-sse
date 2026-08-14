# lunet-mcp-sse Makefile
#
# A demo MCP-SSE server for Tavily search using the Lunet framework.
# Consumes the official Lunet binary release.

LUNET_VERSION ?= v0.9.2
FETCHER := ./scripts/lunet_fetch_release_$(LUNET_VERSION).lua

LUA_CMD := $(shell command -v lua 2>/dev/null || command -v luajit 2>/dev/null || echo "")

ifeq ($(OS),Windows_NT)
  LUNET_BIN := .lunet/$(LUNET_VERSION)/lunet-run.exe
else
  LUNET_BIN := .lunet/$(LUNET_VERSION)/lunet-run
endif

# Default timeout for commands (seconds)
TIMEOUT := 10

# Detect timeout command (GNU coreutils vs BSD)
TIMEOUT_CMD := $(shell command -v gtimeout 2>/dev/null || command -v timeout 2>/dev/null || echo "")

.PHONY: all build run run-info run-debug run-trace run-port test stress bench bench-heavy bench-shell stress-shell clean clean-all help

all: help

# Fetch official Lunet binary release and sync types
build:
	@if [ -z "$(LUA_CMD)" ]; then \
		echo "ERROR: lua or luajit interpreter not found on PATH" >&2; \
		exit 1; \
	fi
	@"$(LUA_CMD)" "$(FETCHER)" >/dev/null
	@rm -rf types && cp -r .lunet/$(LUNET_VERSION)/types types
	@echo "Build complete. Lunet runner: $(LUNET_BIN)"

# Run the MCP server (no tracing)
run: build
	@"$(LUNET_BIN)" app/main.lua

# Run with info-level tracing
run-info: build
	@MCP_TRACE=info "$(LUNET_BIN)" app/main.lua

# Run with debug-level tracing
run-debug: build
	@MCP_TRACE=debug "$(LUNET_BIN)" app/main.lua

# Run with full tracing
run-trace: build
	@MCP_TRACE=trace "$(LUNET_BIN)" app/main.lua

# Run with custom port
run-port: build
	@PORT=$(PORT) "$(LUNET_BIN)" app/main.lua

# Test the server (must be running)
test:
	@echo "Testing server info endpoint..."
	@curl -s --max-time 5 http://localhost:8080/ || echo "ERROR: Server not responding"
	@echo ""
	@echo "Testing SSE endpoint (3 seconds)..."
	@curl -sN --max-time 3 http://localhost:8080/sse || true
	@echo ""

# Shell-based benchmark (server must be running)
bench-shell:
	@./test/bench.sh 30 8080

# Quick stress test via shell (server must be running)
stress-shell:
	@echo "Running 50 sequential requests..."
	@for i in $$(seq 1 50); do \
		curl -s --max-time 3 http://localhost:8080/ > /dev/null && echo -n "." || echo -n "X"; \
	done
	@echo ""
	@echo "Done"

# Lua stress test (server must be running)
stress: build
ifneq ($(TIMEOUT_CMD),)
	@$(TIMEOUT_CMD) 60 "$(LUNET_BIN)" test/stress_mcp.lua || echo "Stress test timed out or failed"
else
	@echo "WARNING: No timeout command available, running without timeout"
	@"$(LUNET_BIN)" test/stress_mcp.lua
endif

# Memory benchmark (starts its own server)
bench: build
ifneq ($(TIMEOUT_CMD),)
	@$(TIMEOUT_CMD) 30 "$(LUNET_BIN)" test/bench_memory.lua || echo "Benchmark timed out or failed"
else
	@echo "WARNING: No timeout command available, running without timeout"
	@"$(LUNET_BIN)" test/bench_memory.lua
endif

# Run benchmark with more clients
bench-heavy: build
ifneq ($(TIMEOUT_CMD),)
	@BENCH_CLIENTS=100 BENCH_REQUESTS=50 $(TIMEOUT_CMD) 60 "$(LUNET_BIN)" test/bench_memory.lua || echo "Heavy benchmark timed out or failed"
else
	@BENCH_CLIENTS=100 BENCH_REQUESTS=50 "$(LUNET_BIN)" test/bench_memory.lua
endif

# Clean temporary files
clean:
	rm -rf .tmp/*.log
	@echo "Cleaned temporary files"

# Deep clean (including fetched runtime and types)
clean-all: clean
	rm -rf .lunet types
	@echo "Cleaned all build artifacts and runtime binaries"

# Show help
help:
	@echo "lunet-mcp-sse"
	@echo "============="
	@echo ""
	@echo "A demo MCP-SSE server exposing Tavily search via the Lunet framework."
	@echo ""
	@echo "Usage:"
	@echo "  make build       - Fetch official Lunet binary release ($(LUNET_VERSION))"
	@echo "  make run         - Start the MCP server (port 8080)"
	@echo "  make run-info    - Start with info-level tracing"
	@echo "  make run-debug   - Start with debug-level tracing"
	@echo "  make run-trace   - Start with full tracing"
	@echo "  make run-port PORT=9000 - Start on custom port"
	@echo "  make test        - Test endpoints (server must be running)"
	@echo "  make bench-shell - Run shell-based benchmark"
	@echo "  make stress-shell - Run shell-based stress test"
	@echo "  make stress      - Run Lua stress test (server must be running)"
	@echo "  make bench       - Run Lua memory benchmark"
	@echo "  make clean       - Clean temporary files"
	@echo "  make clean-all   - Clean all including fetched Lunet runtime and types"
	@echo ""
	@echo "Environment:"
	@echo "  LUNET_VERSION    - Lunet release tag (default: $(LUNET_VERSION))"
	@echo "  TAVILY_API_KEY   - Your Tavily API key (in .env file)"
	@echo "  PORT             - Server port (default 8080)"
	@echo "  MCP_TRACE        - Trace level: off|error|warn|info|debug|trace"
	@echo "  MCP_TRACE_FILE   - Trace output file (default: stderr)"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. Create .env with TAVILY_API_KEY=your_key"
	@echo "  2. make build"
	@echo "  3. make run"
	@echo "  4. curl http://localhost:8080/"
