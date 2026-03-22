# lunet-mcp-sse Makefile (compatibility wrapper)
#
# Prefer xmake directly: xmake lunet-build && xmake lunet-run
# This Makefile delegates to xmake tasks for convenience.

.PHONY: all build run run-info run-debug run-trace run-port test stress bench bench-heavy bench-shell stress-shell smoke clean clean-all help

all: help

build:
	@xmake lunet-build

run: build
	@xmake lunet-run

run-info: build
	@xmake lunet-run --trace=info

run-debug: build
	@xmake lunet-run --trace=debug

run-trace: build
	@xmake lunet-run --trace=trace

run-port: build
	@xmake lunet-run --port=$(PORT)

test:
	@xmake lunet-test

stress: build
	@xmake lunet-stress

bench: build
	@xmake lunet-bench

bench-heavy: build
	@xmake lunet-bench-heavy

smoke: build
	@xmake lunet-smoke

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

clean:
	rm -rf .tmp/*.log
	@echo "Cleaned temporary files"

clean-all: clean
	cd deps/lunet && xmake clean 2>/dev/null || true
	@echo "Cleaned all build artifacts"

help:
	@echo "lunet-mcp-sse (make -> xmake wrapper)"
	@echo "======================================"
	@echo ""
	@echo "Prefer using xmake directly (see xmake.lua):"
	@echo "  xmake lunet-build              Build Lunet runtime + modules"
	@echo "  xmake lunet-run [--trace=LVL]  Start the MCP server"
	@echo "  xmake lunet-smoke              Run httpc smoke test"
	@echo ""
	@echo "make targets (delegating to xmake):"
	@echo "  make build       - xmake lunet-build"
	@echo "  make run         - xmake lunet-run"
	@echo "  make run-info    - xmake lunet-run --trace=info"
	@echo "  make run-debug   - xmake lunet-run --trace=debug"
	@echo "  make run-trace   - xmake lunet-run --trace=trace"
	@echo "  make test        - xmake lunet-test"
	@echo "  make stress      - xmake lunet-stress"
	@echo "  make bench       - xmake lunet-bench"
	@echo "  make smoke       - xmake lunet-smoke"
	@echo "  make clean       - Clean temp files"
	@echo "  make clean-all   - Clean all including lunet build"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. git submodule update --init --recursive"
	@echo "  2. echo 'TAVILY_API_KEY=your_key' > .env"
	@echo "  3. make build && make run"
	@echo "  4. curl http://localhost:8080/"
