#!/usr/bin/env luajit
-- MCP-SSE Stress Test
--
-- Tests the MCP server under load to measure:
-- - Memory usage (RSS)
-- - Connection handling
-- - Request throughput
-- - Session management
--
-- Usage:
--   # Start server first:
--   ./lunet/build/lunet app/main.lua &
--   
--   # Then run stress test:
--   ./lunet/build/lunet test/stress_mcp.lua
--
-- Environment:
--   STRESS_CLIENTS   - Number of concurrent clients (default 20)
--   STRESS_REQUESTS  - Requests per client (default 10)
--   STRESS_PORT      - Server port (default 8080)
--   STRESS_TIMEOUT   - Timeout in ms (default 30000)

io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

local lunet = require("lunet")
local socket = require("lunet.socket")

-- Configuration
local NUM_CLIENTS = tonumber(os.getenv("STRESS_CLIENTS")) or 20
local REQUESTS_PER_CLIENT = tonumber(os.getenv("STRESS_REQUESTS")) or 10
local PORT = tonumber(os.getenv("STRESS_PORT")) or 8080
local TIMEOUT_MS = tonumber(os.getenv("STRESS_TIMEOUT")) or 30000
local HOST = "127.0.0.1"

-- Statistics
local stats = {
    connections = 0,
    requests = 0,
    responses = 0,
    errors = 0,
    bytes_sent = 0,
    bytes_recv = 0,
    start_time = 0,
    end_time = 0,
}

-- Simple HTTP request sender
local function http_request(method, path, body)
    local client, err = socket.connect(HOST, PORT)
    if not client then
        return nil, "connect failed: " .. (err or "unknown")
    end
    
    stats.connections = stats.connections + 1
    
    local headers = method .. " " .. path .. " HTTP/1.1\r\n"
    headers = headers .. "Host: " .. HOST .. ":" .. PORT .. "\r\n"
    headers = headers .. "Connection: close\r\n"
    
    if body then
        headers = headers .. "Content-Type: application/json\r\n"
        headers = headers .. "Content-Length: " .. #body .. "\r\n"
    end
    
    headers = headers .. "\r\n"
    
    local request = headers
    if body then
        request = request .. body
    end
    
    stats.bytes_sent = stats.bytes_sent + #request
    local write_err = socket.write(client, request)
    if write_err then
        socket.close(client)
        return nil, "write failed: " .. tostring(write_err)
    end
    
    stats.requests = stats.requests + 1
    
    local response = socket.read(client)
    socket.close(client)
    
    if not response then
        return nil, "read failed"
    end
    
    stats.bytes_recv = stats.bytes_recv + #response
    stats.responses = stats.responses + 1
    
    return response
end

-- Test the info endpoint
local function test_info()
    local resp, err = http_request("GET", "/")
    if not resp then
        stats.errors = stats.errors + 1
        return false, err
    end
    
    if not resp:match("200 OK") then
        stats.errors = stats.errors + 1
        return false, "unexpected status"
    end
    
    return true
end

-- Simulate an SSE session with message exchanges
local function test_session(client_id)
    -- First, get a session via /sse
    local client, err = socket.connect(HOST, PORT)
    if not client then
        return false, "connect failed: " .. (err or "unknown")
    end
    
    stats.connections = stats.connections + 1
    
    local sse_request = "GET /sse HTTP/1.1\r\n"
    sse_request = sse_request .. "Host: " .. HOST .. ":" .. PORT .. "\r\n"
    sse_request = sse_request .. "Accept: text/event-stream\r\n"
    sse_request = sse_request .. "Connection: keep-alive\r\n\r\n"
    
    stats.bytes_sent = stats.bytes_sent + #sse_request
    socket.write(client, sse_request)
    stats.requests = stats.requests + 1
    
    -- Read the SSE response to get session ID
    local response = socket.read(client)
    if not response then
        socket.close(client)
        stats.errors = stats.errors + 1
        return false, "no SSE response"
    end
    
    stats.bytes_recv = stats.bytes_recv + #response
    stats.responses = stats.responses + 1
    
    -- Extract session ID from endpoint event
    local session_id = response:match("session=([%w]+)")
    if not session_id then
        socket.close(client)
        stats.errors = stats.errors + 1
        return false, "no session ID in response"
    end
    
    -- Send initialize request
    local init_body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"stress-test","version":"1.0"}}}'
    local init_resp, init_err = http_request("POST", "/message?session=" .. session_id, init_body)
    if not init_resp then
        socket.close(client)
        stats.errors = stats.errors + 1
        return false, "initialize failed: " .. (init_err or "unknown")
    end
    
    -- Send tools/list request
    local list_body = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
    local list_resp, list_err = http_request("POST", "/message?session=" .. session_id, list_body)
    if not list_resp then
        socket.close(client)
        stats.errors = stats.errors + 1
        return false, "tools/list failed: " .. (list_err or "unknown")
    end
    
    -- Send multiple ping requests
    for i = 1, REQUESTS_PER_CLIENT do
        local ping_body = '{"jsonrpc":"2.0","id":' .. (i + 10) .. ',"method":"ping","params":{}}'
        local ping_resp, ping_err = http_request("POST", "/message?session=" .. session_id, ping_body)
        if not ping_resp then
            stats.errors = stats.errors + 1
        end
    end
    
    -- Close SSE connection
    socket.close(client)
    
    return true
end

-- Worker function
local function worker(worker_id)
    local ok, err = test_session(worker_id)
    if not ok then
        io.stderr:write(string.format("[STRESS] Worker %d failed: %s\n", worker_id, err or "unknown"))
    end
end

-- Memory reporting (platform-specific)
local function get_rss_kb()
    -- Try macOS/BSD first
    local handle = io.popen("ps -o rss= -p $PPID 2>/dev/null")
    if handle then
        local rss = handle:read("*a")
        handle:close()
        rss = tonumber(rss:match("%d+"))
        if rss then return rss end
    end
    
    -- Try Linux
    handle = io.popen("cat /proc/$PPID/status 2>/dev/null | grep VmRSS | awk '{print $2}'")
    if handle then
        local rss = handle:read("*a")
        handle:close()
        rss = tonumber(rss:match("%d+"))
        if rss then return rss end
    end
    
    return nil
end

-- Report statistics
local function report_stats()
    local elapsed = stats.end_time - stats.start_time
    
    print("\n[STRESS] ========== Results ==========")
    print(string.format("[STRESS] Clients:      %d", NUM_CLIENTS))
    print(string.format("[STRESS] Req/Client:   %d", REQUESTS_PER_CLIENT))
    print(string.format("[STRESS] Connections:  %d", stats.connections))
    print(string.format("[STRESS] Requests:     %d", stats.requests))
    print(string.format("[STRESS] Responses:    %d", stats.responses))
    print(string.format("[STRESS] Errors:       %d", stats.errors))
    print(string.format("[STRESS] Bytes Sent:   %d", stats.bytes_sent))
    print(string.format("[STRESS] Bytes Recv:   %d", stats.bytes_recv))
    print(string.format("[STRESS] Duration:     %.3fs", elapsed))
    
    if elapsed > 0 then
        print(string.format("[STRESS] Requests/sec: %.0f", stats.requests / elapsed))
        print(string.format("[STRESS] Throughput:   %.2f KB/s", (stats.bytes_sent + stats.bytes_recv) / 1024 / elapsed))
    end
    
    local rss = get_rss_kb()
    if rss then
        print(string.format("[STRESS] Client RSS:   %.2f MB", rss / 1024))
    end
    
    print("[STRESS] ================================")
    
    if stats.errors > 0 then
        print("[STRESS] FAILED - errors detected")
        return 1
    else
        print("[STRESS] PASSED")
        return 0
    end
end

-- Main
print("[STRESS] MCP-SSE Stress Test")
print(string.format("[STRESS] Target: http://%s:%d", HOST, PORT))
print(string.format("[STRESS] Config: %d clients x %d requests", NUM_CLIENTS, REQUESTS_PER_CLIENT))

-- Check server is running
local check_resp, check_err = http_request("GET", "/")
if not check_resp then
    print("[STRESS] FATAL: Server not running at " .. HOST .. ":" .. PORT)
    print("[STRESS] Start the server first: ./lunet/build/lunet app/main.lua")
    os.exit(1)
end

print("[STRESS] Server is running, starting stress test...")

local completed_workers = 0

-- Watchdog
lunet.spawn(function()
    local waited = 0
    while waited < TIMEOUT_MS and completed_workers < NUM_CLIENTS do
        lunet.sleep(100)
        waited = waited + 100
    end
    
    if completed_workers < NUM_CLIENTS then
        io.stderr:write(string.format("\n[STRESS] TIMEOUT after %dms!\n", TIMEOUT_MS))
        stats.end_time = os.clock()
        report_stats()
        os.exit(1)
    end
end)

-- Start workers
stats.start_time = os.clock()

for i = 1, NUM_CLIENTS do
    lunet.spawn(function()
        worker(i)
        completed_workers = completed_workers + 1
        
        if completed_workers % 5 == 0 then
            io.write(".")
            io.flush()
        end
    end)
end

-- Wait for completion
lunet.spawn(function()
    while completed_workers < NUM_CLIENTS do
        lunet.sleep(50)
    end
    
    stats.end_time = os.clock()
    local exit_code = report_stats()
    os.exit(exit_code)
end)
