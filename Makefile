# lunet-mcp-sse Makefile
#
# A demo MCP-SSE server for Tavily search using the Lunet framework.
# Assumes lunet is a sibling directory (../lunet)

LUNET_DIR := ../lunet
LUNET_BIN := $(LUNET_DIR)/build/lunet

# Default timeout for commands (seconds)
TIMEOUT := 10

# Detect timeout command (GNU coreutils vs BSD)
TIMEOUT_CMD := $(shell command -v gtimeout 2>/dev/null || command -v timeout 2>/dev/null || echo "")

.PHONY: all build run run-debug run-trace test stress bench bench-shell clean help

all: help

# Build lunet if needed
$(LUNET_BIN):
	@echo "Building lunet..."
	cd $(LUNET_DIR) && $(MAKE) build

build: $(LUNET_BIN)
	@echo "Build complete. Lunet binary: $(LUNET_BIN)"

# Run the MCP server (no tracing)
run: $(LUNET_BIN)
	$(LUNET_BIN) app/main.lua

# Run with info-level tracing
run-info: $(LUNET_BIN)
	MCP_TRACE=info $(LUNET_BIN) app/main.lua

# Run with debug-level tracing
run-debug: $(LUNET_BIN)
	MCP_TRACE=debug $(LUNET_BIN) app/main.lua

# Run with full tracing
run-trace: $(LUNET_BIN)
	MCP_TRACE=trace $(LUNET_BIN) app/main.lua

# Run with custom port
run-port: $(LUNET_BIN)
	PORT=$(PORT) $(LUNET_BIN) app/main.lua

# Test the server (must be running) - with timeout
test:
	@echo "Testing server info endpoint..."
	@curl -s --max-time 5 http://localhost:8080/ || echo "ERROR: Server not responding"
	@echo ""
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

# Lua stress test (server must be running) - with timeout
stress: $(LUNET_BIN)
ifneq ($(TIMEOUT_CMD),)
	$(TIMEOUT_CMD) 60 $(LUNET_BIN) test/stress_mcp.lua || echo "Stress test timed out or failed"
else
	@echo "WARNING: No timeout command available, running without timeout"
	$(LUNET_BIN) test/stress_mcp.lua
endif

# Memory benchmark (starts its own server) - with timeout
bench: $(LUNET_BIN)
ifneq ($(TIMEOUT_CMD),)
	$(TIMEOUT_CMD) 30 $(LUNET_BIN) test/bench_memory.lua || echo "Benchmark timed out or failed"
else
	@echo "WARNING: No timeout command available, running without timeout"
	$(LUNET_BIN) test/bench_memory.lua
endif

# Run benchmark with more clients
bench-heavy: $(LUNET_BIN)
ifneq ($(TIMEOUT_CMD),)
	BENCH_CLIENTS=100 BENCH_REQUESTS=50 $(TIMEOUT_CMD) 60 $(LUNET_BIN) test/bench_memory.lua || echo "Heavy benchmark timed out or failed"
else
	BENCH_CLIENTS=100 BENCH_REQUESTS=50 $(LUNET_BIN) test/bench_memory.lua
endif

# Clean build artifacts
clean:
	rm -rf .tmp/*.log
	@echo "Cleaned temporary files"

# Deep clean (including lunet build)
clean-all: clean
	cd $(LUNET_DIR) && $(MAKE) clean 2>/dev/null || true
	@echo "Cleaned all build artifacts"

# Show help
help:
	@echo "lunet-mcp-sse"
	@echo "============="
	@echo ""
	@echo "A demo MCP-SSE server exposing Tavily search via the Lunet framework."
	@echo ""
	@echo "Usage:"
	@echo "  make build       - Build the lunet runtime"
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
	@echo "  make clean-all   - Clean all including lunet build"
	@echo ""
	@echo "Environment:"
	@echo "  TAVILY_API_KEY   - Your Tavily API key (in .env file)"
	@echo "  PORT             - Server port (default 8080)"
	@echo "  MCP_TRACE        - Trace level: off|error|warn|info|debug|trace"
	@echo "  MCP_TRACE_FILE   - Trace output file (default: stderr)"
	@echo ""
	@echo "Tracing Examples:"
	@echo "  MCP_TRACE=info make run     # Info-level tracing"
	@echo "  MCP_TRACE=debug make run    # Debug-level tracing"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. Create .env with TAVILY_API_KEY=your_key"
	@echo "  2. make build"
	@echo "  3. make run"
	@echo "  4. curl http://localhost:8080/"
