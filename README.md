# lunet-mcp-sse

[![Lunet v0.1.2](https://img.shields.io/badge/Lunet-v0.1.2-blue?logo=lua&logoColor=white)](https://github.com/lua-lunet/lunet/releases/tag/v0.1.2)

A minimal MCP (Model Context Protocol) server demonstrating Tavily web search via SSE transport, built on the [Lunet](https://github.com/lua-lunet/lunet) framework.

[中文文档](README-CN.md)

## Why Lunet?

MCP servers are often deployed as sidecar processes or in resource-constrained environments. This implementation prioritizes:

- **Minimal footprint** - 7 MB runtime memory vs 14-28 MB for Node/Bun/Python
- **Small image size** - 171 MB Docker image vs 367-420 MB for alternatives
- **Stable dependencies** - libuv and LuaJIT are mature, battle-tested libraries with Debian LTS support
- **No dependency churn** - No npm/pip ecosystem overhead or constant security patches

### Performance Comparison

Run `./compare.sh` to reproduce these benchmarks:

| Implementation | Docker Image | Runtime Memory |
|----------------|--------------|----------------|
| **lunet-mcp-sse** | **171 MB** | **7 MB** |
| tavily-mcp (Node.js) | 420 MB | 18 MB |
| tavily-mcp (Bun) | 382 MB | 14 MB |
| FastMCP (Python) | 367 MB | 28 MB |

lunet-mcp-sse uses **2.5x less memory** than Node.js, **2x less** than Bun, and **4x less** than Python.

## Features

- **MCP 2024-11-05** protocol support
- **SSE transport** for real-time communication
- **Tavily search** integration
- **Memory-efficient** (~7 MB RSS in Docker, ~2 MB native)
- **Zero-cost tracing** for debugging (no overhead when disabled)
- **Cross-platform** binaries (Linux amd64/arm64, macOS arm64, Windows amd64)

## Downloads

Pre-built binaries are available from [GitHub Releases](https://github.com/lua-lunet/lunet-mcp-sse/releases/tag/nightly):

| Platform | Archive |
|----------|---------|
| Linux (amd64) | `lunet-mcp-sse-linux-amd64.tar.gz` |
| Linux (arm64) | `lunet-mcp-sse-linux-arm64.tar.gz` |
| macOS (arm64) | `lunet-mcp-sse-macos.tar.gz` |
| Windows (amd64) | `lunet-mcp-sse-windows-amd64.zip` |

## Running

### macOS (arm64)

```bash
# Download and extract
curl -L -o lunet-mcp-sse-macos.tar.gz \
  https://github.com/lua-lunet/lunet-mcp-sse/releases/download/nightly/lunet-mcp-sse-macos.tar.gz
tar -xzf lunet-mcp-sse-macos.tar.gz

# Set up API key
echo "TAVILY_API_KEY=your_key_here" > .env

# Run
./run.sh
```

### Linux (Debian/Ubuntu)

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y libuv1 libluajit-5.1-2 curl

# Download and extract (use arm64 or amd64 as appropriate)
curl -L -o lunet-mcp-sse-linux-arm64.tar.gz \
  https://github.com/lua-lunet/lunet-mcp-sse/releases/download/nightly/lunet-mcp-sse-linux-arm64.tar.gz
tar -xzf lunet-mcp-sse-linux-arm64.tar.gz

# Set up API key
echo "TAVILY_API_KEY=your_key_here" > .env

# Run
./run.sh
```

### Windows (amd64)

```powershell
# Download and extract the zip from GitHub releases
# Then in the extracted directory:

# Set up API key
echo TAVILY_API_KEY=your_key_here > .env

# Run
.\run.bat
```

## Testing with Docker

You can run the Linux binary in a Docker container. This is useful for testing on macOS or other platforms.

```bash
# Start a container with the binary mounted
docker run -d --name mcp-server -p 8080:8080 \
  -v /path/to/extracted/linux-app:/app -w /app \
  debian:trixie-slim \
  /bin/bash -c 'apt-get update -qq && apt-get install -y -qq libuv1 libluajit-5.1-2 curl >/dev/null 2>&1 && export $(cat .env | xargs) && HOST=0.0.0.0 ./bin/lunet --dangerously-skip-loopback-restriction app/main.lua'

# Test
curl http://localhost:8080/

# Stop
docker stop mcp-server && docker rm mcp-server
```

### macOS with Colima

On macOS, use [Colima](https://github.com/abiosoft/colima) to run Linux arm64 containers:

```bash
# Start Colima
colima start

# Download and extract the Linux arm64 build
curl -L -o lunet-mcp-sse-linux-arm64.tar.gz \
  https://github.com/lua-lunet/lunet-mcp-sse/releases/download/nightly/lunet-mcp-sse-linux-arm64.tar.gz
mkdir -p linux-app
tar -xzf lunet-mcp-sse-linux-arm64.tar.gz -C linux-app

# Copy into Colima VM
colima ssh -- mkdir -p /tmp/testapp
tar -czf - -C linux-app . | colima ssh -- tar -xzf - -C /tmp/testapp

# Copy your .env
echo "TAVILY_API_KEY=your_key_here" | colima ssh -- tee /tmp/testapp/.env

# Run the server
docker run -d --name mcp-server -p 8080:8080 \
  -v /tmp/testapp:/app -w /app \
  debian:trixie-slim \
  /bin/bash -c 'apt-get update -qq && apt-get install -y -qq libuv1 libluajit-5.1-2 curl >/dev/null 2>&1 && export $(cat .env | xargs) && HOST=0.0.0.0 ./bin/lunet --dangerously-skip-loopback-restriction app/main.lua'

# Test from macOS
curl http://localhost:8080/
./test_tavily.sh

# Cleanup
docker stop mcp-server && docker rm mcp-server
colima stop
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

# Run Tavily search test
./test_tavily.sh

# Connect to SSE stream manually
curl -N http://localhost:8080/sse
```

## MCP Protocol Flow

1. Client GETs `/sse` to establish SSE connection
2. Server sends `endpoint` event with session ID
3. Client POSTs JSON-RPC messages to `/message?session=<id>`
4. Server responds via SSE events on the GET connection

There is no HTTPS termination support in this repo by design. 
If you want to run a public-facing MCP SSE you can trivially
deploy this code with nginx as a sidecar else on a private cloud 
network behind a cloud load balancer. That is The Unix Way of piping 
data between specialist tools. It gives you the “QMail Security Model” 
where dealing protocol attacks is process segregated from any 
business logic. 

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

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAVILY_API_KEY` | - | Tavily API key (required) |
| `PORT` | 8080 | Server port |
| `HOST` | 127.0.0.1 | Bind address (use 0.0.0.0 for Docker) |
| `MCP_TRACE` | off | Trace level (off/error/warn/info/debug/trace) |
| `MCP_TRACE_FILE` | stderr | Output file for traces |

## Building from Source

Requires [xmake](https://xmake.io/) and Lunet v0.1.2+. See [XMAKE_INTEGRATION.md](https://github.com/lua-lunet/lunet/blob/main/docs/XMAKE_INTEGRATION.md) for the canonical integration guide.

```bash
# Clone and init submodules
git clone https://github.com/lua-lunet/lunet-mcp-sse.git
cd lunet-mcp-sse
git submodule update --init --recursive

# Run
echo "TAVILY_API_KEY=your_key_here" > .env
make run
```

## Zero-Cost Tracing

The server includes a zero-cost tracing system that has **no overhead when disabled**.

```bash
# No tracing (production, zero overhead)
./run.sh

# Verbose startup - show server banner
./run.sh -v
# or: ./run.sh --verbose

# Info level - see sessions and tool calls
MCP_TRACE=info ./run.sh

# Debug level - see HTTP requests and MCP methods
MCP_TRACE=debug ./run.sh
```

## Benchmarking

Compare memory and image size against other MCP implementations:

```bash
./compare.sh
```

This tests against:
- `tavily-mcp` (Node.js via npx)
- `tavily-mcp` (Bun)
- FastMCP (Python)

## License

MIT

---

> This project uses [Lunet](https://github.com/lua-lunet/lunet), which is based on [xialeistudio/lunet](https://github.com/xialeistudio/lunet) by [夏磊 (Xia Lei)](https://github.com/xialeistudio). See also his excellent write-up: [Lunet: Design and Implementation of a High-Performance Coroutine Network Library](https://www.ddhigh.com/en/2025/07/12/lunet-high-performance-coroutine-network-library/).
