# lunet-mcp-sse

A minimal MCP (Model Context Protocol) server demonstrating Tavily web search via SSE transport, built on the [Lunet](https://github.com/lua-lunet/lunet) framework.

## Features

- **MCP 2024-11-05** protocol support
- **SSE transport** for real-time communication
- **Tavily search** integration
- **Memory-efficient** (~2 MB RSS)
- **Zero-cost tracing** for debugging (no overhead when disabled)
- **Stress testing** and benchmarking tools

## Quick Start

```bash
# 1. Clone the lua-lunet org repos (lunet-mcp-sse requires sibling lunet repo)
mkdir lua-lunet && cd lua-lunet
git clone https://github.com/lua-lunet/lunet.git
git clone https://github.com/lua-lunet/lunet-mcp-sse.git

# 2. Build lunet
cd lunet && make build && cd ..

# 3. Set up API key and run
cd lunet-mcp-sse
echo "TAVILY_API_KEY=your_key_here" > .env
make run
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Server info (JSON) |
| GET | `/sse` | SSE stream (creates session) |
| POST | `/message?session=<id>` | Send JSON-RPC message |

## Testing

```bash
# Check server info
curl http://localhost:8080/

# Connect to SSE stream
curl -N http://localhost:8080/sse

# Run stress test (server must be running)
make stress

# Run memory benchmark
make bench
```

## MCP Protocol Flow

1. Client GETs `/sse` to establish SSE connection
2. Server sends `endpoint` event with session ID
3. Client POSTs JSON-RPC messages to `/message?session=<id>`
4. Server responds via SSE events on the GET connection

## Tools Available

### tavily-search

Search the web using Tavily AI search engine.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "tavily-search",
    "arguments": {
      "query": "latest AI news",
      "max_results": 5
    }
  }
}
```

## Memory Usage

Measured on macOS with LuaJIT + libuv:

| Implementation | RSS |
|----------------|-----|
| Pure Lua stdio | ~1.6 MB |
| Lunet SSE server | ~2.2 MB |

The ~0.6 MB overhead is from libuv and TCP socket handling.

## Project Structure

```
lua-lunet/                # GitHub org directory
├── lunet/                # Lunet framework (sibling repo)
├── lunet-mcp-sse/        # This repo
│   ├── app/
│   │   ├── main.lua      # MCP-SSE server
│   │   └── trace.lua     # Zero-cost tracing module
│   ├── test/
│   │   ├── stress_mcp.lua    # Connection stress test
│   │   ├── bench_memory.lua  # Memory benchmark
│   │   └── bench.sh          # Shell-based benchmark
│   ├── .env              # API keys (not committed)
│   └── Makefile
└── lunet-realworld-example-app/  # Another sibling repo
```

## Zero-Cost Tracing

The server includes a zero-cost tracing system that has **no overhead when disabled**. 
When `MCP_TRACE` is not set (or set to `0`/`off`), all trace calls compile to empty 
functions via LuaJIT's dead code elimination.

### Trace Levels

| Level | Name | Description |
|-------|------|-------------|
| 0 | off | No tracing (default, zero overhead) |
| 1 | error | Errors only |
| 2 | warn | Warnings and above |
| 3 | info | Informational messages (sessions, tools) |
| 4 | debug | Debug messages (HTTP requests, MCP methods) |
| 5 | trace | All messages including fine-grained tracing |

### Usage Examples

```bash
# No tracing (production, zero overhead)
../lunet/build/lunet app/main.lua

# Info level - see sessions and tool calls
MCP_TRACE=info ../lunet/build/lunet app/main.lua

# Debug level - see HTTP requests and MCP methods
MCP_TRACE=debug ../lunet/build/lunet app/main.lua

# Full tracing - all messages
MCP_TRACE=trace ../lunet/build/lunet app/main.lua

# Write traces to file
MCP_TRACE=debug MCP_TRACE_FILE=server.log ../lunet/build/lunet app/main.lua

# Or use make targets
make run          # No tracing
make run-info     # Info level
make run-debug    # Debug level
make run-trace    # Full tracing
```

### Trace Output Format

```
[timestamp] [LEVEL] [CATEGORY] message
```

Example output at `debug` level:
```
[0.001] [INFO] [SERVER] Starting on port 8080
[0.052] [DEBUG] [HTTP] GET /
[0.103] [DEBUG] [HTTP] GET /sse
[0.104] [INFO] [SSE] Session abc123 connected
[0.205] [DEBUG] [MCP] Request: method=initialize id=1
[0.310] [DEBUG] [HTTP] POST /message
[0.311] [DEBUG] [MCP] Request: method=tools/call id=2
[0.312] [INFO] [TOOL] Calling tool: tavily-search
```

### Trace Categories

| Category | Description |
|----------|-------------|
| SERVER | Server lifecycle events |
| HTTP | HTTP request handling |
| SSE | SSE session management |
| MCP | MCP JSON-RPC protocol |
| TOOL | Tool invocations |
| CONFIG | Configuration issues |

### Programmatic Usage

```lua
local trace = require("app.trace")

-- Check if level is enabled (for expensive operations)
if trace.is_enabled("debug") then
    trace.debug("CAT", "Expensive data: %s", json_encode(big_table))
end

-- Get statistics
local stats = trace.get_stats()
print("Total messages:", stats.messages)

-- Dump statistics at shutdown
trace.dump_stats()
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAVILY_API_KEY` | - | Tavily API key (required) |
| `PORT` | 8080 | Server port |
| `MCP_TRACE` | off | Trace level (see Tracing section) |
| `MCP_TRACE_FILE` | stderr | Output file for traces |
| `STRESS_CLIENTS` | 20 | Concurrent clients for stress test |
| `STRESS_REQUESTS` | 10 | Requests per client |
| `BENCH_CLIENTS` | 50 | Clients for memory benchmark |
| `BENCH_DURATION` | 10 | Benchmark duration (seconds) |

## Requirements

- LuaJIT 2.1+
- libuv 1.x
- curl (for Tavily API calls)
- xmake (for building Lunet)

## License

MIT
