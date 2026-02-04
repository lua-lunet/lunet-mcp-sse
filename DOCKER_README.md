# Docker Testing for lunet-mcp-sse

This directory contains files for testing the lunet-mcp-sse nightly build in Docker.

## Files

- `Dockerfile` - Debian Trixie image with LuaJIT, libuv, and the nightly build
- `docker-compose.yml` - Orchestrates the MCP server and test runner
- `docker_test/test_info.lua` - Lua script to test info endpoint
- `docker_test/test_sse_session.lua` - Lua script for full SSE session test
- `docker_test/run_tests.sh` - Shell script for comprehensive tests
- `test_mcp.sh` - Quick curl-based test

## Quick Start

### Option 1: Build and run with docker compose

```bash
# Ensure .env has TAVILY_API_KEY
cat .env

# Build and start
docker compose up --build -d

# Run tests
./docker_test/run_tests.sh

# Or manually
docker compose exec lunet-mcp curl -s http://localhost:8080/
```

### Option 2: Build and run manually

```bash
# Build
docker build -t lunet-mcp-test .

# Run with env file mounted
docker run -it --rm \
    -p 8080:8080 \
    -v $(pwd)/.env:/app/.env:ro \
    lunet-mcp-test

# In another terminal, test
curl http://localhost:8080/
```

### Option 3: Interactive shell

```bash
docker run -it --rm \
    -p 8080:8080 \
    -v $(pwd):/app \
    lunet-mcp-test /bin/bash

# Inside container
./run.sh

# In another terminal
./test_mcp.sh
```

## API Testing

The server exposes three endpoints:

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Server info (JSON) |
| GET | `/sse` | SSE stream (creates session) |
| POST | `/message?session=<id>` | Send JSON-RPC message |

## Test with curl

```bash
# Server info
curl http://localhost:8080/

# SSE stream (keeps connection open)
curl -N http://localhost:8080/sse

# Send MCP message (needs valid session from SSE)
curl -X POST "http://localhost:8080/message?session=<session-id>" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# Full session test
curl -N http://localhost:8080/sse > /tmp/sse.log &
SESSION_ID=$(grep -o 'session=[a-zA-Z0-9]*' /tmp/sse.log | head -1 | cut -d= -f2)
curl -X POST "http://localhost:8080/message?session=$SESSION_ID" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl-test","version":"1.0"}}}'
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TAVILY_API_KEY` | - | Required for Tavily search |
| `PORT` | 8080 | Server port |
| `MCP_TRACE` | off | Trace level: off\|error\|warn\|info\|debug\|trace |