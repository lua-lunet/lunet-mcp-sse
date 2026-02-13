#!/usr/bin/env luajit
-- Memory Benchmark for MCP-SSE Server
--
-- Measures memory usage of the server under various loads.
-- This script starts the server, measures baseline memory,
-- then applies load and measures peak memory.
--
-- Usage:
--   make bench
--   # or: LUNET_BIN=$(find ../lunet/build -path '*/release/lunet-run*' -type f | head -1) && $LUNET_BIN test/bench_memory.lua
--
-- Environment:
--   BENCH_PORT      - Server port (default 8081, different to avoid conflicts)
--   BENCH_CLIENTS   - Number of concurrent clients (default 50)
--   BENCH_REQUESTS  - Requests per client (default 20)
--   BENCH_DURATION  - Test duration in seconds (default 10)

io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

local lunet = require("lunet")
local socket = require("lunet.socket")

-- Configuration
local PORT = tonumber(os.getenv("BENCH_PORT")) or 8081
local NUM_CLIENTS = tonumber(os.getenv("BENCH_CLIENTS")) or 50
local REQUESTS_PER_CLIENT = tonumber(os.getenv("BENCH_REQUESTS")) or 20
local DURATION_SEC = tonumber(os.getenv("BENCH_DURATION")) or 10
local HOST = "127.0.0.1"

-- Memory tracking
local memory_samples = {}
local sample_interval_ms = 100

-- Get memory usage via collectgarbage
local function get_lua_memory_kb()
    collectgarbage("collect")
    return collectgarbage("count")
end

-- Statistics
local stats = {
    requests = 0,
    responses = 0,
    errors = 0,
    active_sessions = 0,
    peak_sessions = 0,
}

-- Simple JSON helpers (reused from main.lua)
local function escape_json_string(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"', '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return s
end

local function json_encode(val)
    local t = type(val)
    if val == nil then return "null"
    elseif t == "boolean" then return val and "true" or "false"
    elseif t == "number" then return tostring(val)
    elseif t == "string" then return '"' .. escape_json_string(val) .. '"'
    elseif t == "table" then
        local is_array = #val > 0 or next(val) == nil
        if is_array then
            local parts = {}
            for i, v in ipairs(val) do parts[i] = json_encode(v) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                if type(k) == "string" then
                    parts[#parts + 1] = '"' .. escape_json_string(k) .. '":' .. json_encode(v)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- HTTP response helpers
local function http_response(status, headers, body)
    local status_texts = {
        [200] = "OK", [202] = "Accepted", [400] = "Bad Request", [404] = "Not Found",
    }
    local parts = {"HTTP/1.1 " .. status .. " " .. (status_texts[status] or "OK") .. "\r\n"}
    headers = headers or {}
    if body then headers["Content-Length"] = #body end
    for name, value in pairs(headers) do
        parts[#parts + 1] = name .. ": " .. tostring(value) .. "\r\n"
    end
    parts[#parts + 1] = "\r\n"
    if body then parts[#parts + 1] = body end
    return table.concat(parts)
end

local function parse_http_request(data)
    local req = {headers = {}, body = nil}
    local header_end = data:find("\r\n\r\n")
    if not header_end then return nil end
    local header_section = data:sub(1, header_end - 1)
    local body = data:sub(header_end + 4)
    local first_line = header_section:match("^([^\r\n]+)")
    if not first_line then return nil end
    req.method, req.path = first_line:match("^(%S+)%s+(%S+)")
    if not req.method then return nil end
    local path_only, query = req.path:match("^([^?]+)%??(.*)")
    req.path = path_only or req.path
    req.query = {}
    if query and query ~= "" then
        for pair in query:gmatch("[^&]+") do
            local k, v = pair:match("^([^=]+)=?(.*)")
            if k then req.query[k] = v or "" end
        end
    end
    for line in header_section:gmatch("\r\n([^\r\n]+)") do
        local name, value = line:match("^([^:]+):%s*(.*)$")
        if name then req.headers[name:lower()] = value end
    end
    local content_length = req.headers["content-length"]
    if content_length then
        content_length = tonumber(content_length)
        if content_length and content_length > 0 then
            req.body = body:sub(1, content_length)
        end
    end
    return req
end

-- Session management
local sessions = {}
local session_counter = 0

local function random_id()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local id = {}
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        id[i] = chars:sub(idx, idx)
    end
    return table.concat(id)
end

local function sse_event(event_name, data)
    local lines = {}
    if event_name then lines[#lines + 1] = "event: " .. event_name end
    lines[#lines + 1] = "data: " .. data
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

-- Minimal MCP server (embedded for benchmarking)
local function handle_mcp_request(msg)
    local method = msg.method
    local id = msg.id
    
    if method == "initialize" then
        return json_encode({
            jsonrpc = "2.0", id = id,
            result = {
                protocolVersion = "2024-11-05",
                capabilities = {tools = {}},
                serverInfo = {name = "bench-server", version = "1.0"},
            },
        })
    elseif method == "notifications/initialized" then
        return nil
    elseif method == "tools/list" then
        return json_encode({
            jsonrpc = "2.0", id = id,
            result = {tools = {}},
        })
    elseif method == "ping" then
        return json_encode({jsonrpc = "2.0", id = id, result = {}})
    else
        return json_encode({
            jsonrpc = "2.0", id = id,
            error = {code = -32601, message = "Method not found"},
        })
    end
end

-- Request handler
local function handle_client(client)
    local data = socket.read(client)
    if not data then
        socket.close(client)
        return
    end
    
    local req = parse_http_request(data)
    if not req then
        socket.write(client, http_response(400, {}, "Bad Request"))
        socket.close(client)
        return
    end
    
    stats.requests = stats.requests + 1
    
    -- SSE endpoint
    if req.path == "/sse" and req.method == "GET" then
        local session_id = random_id()
        session_counter = session_counter + 1
        stats.active_sessions = stats.active_sessions + 1
        if stats.active_sessions > stats.peak_sessions then
            stats.peak_sessions = stats.active_sessions
        end
        
        local headers = {
            ["Content-Type"] = "text/event-stream",
            ["Cache-Control"] = "no-cache",
            ["Connection"] = "keep-alive",
        }
        local header_str = "HTTP/1.1 200 OK\r\n"
        for k, v in pairs(headers) do
            header_str = header_str .. k .. ": " .. v .. "\r\n"
        end
        header_str = header_str .. "\r\n"
        socket.write(client, header_str)
        socket.write(client, sse_event("endpoint", "/message?session=" .. session_id))
        
        sessions[session_id] = {client = client}
        stats.responses = stats.responses + 1
        -- Don't close - SSE connection stays open
        return
    end
    
    -- Message endpoint
    if req.path == "/message" and req.method == "POST" then
        local session_id = req.query.session
        local session = sessions[session_id]
        
        if not session then
            socket.write(client, http_response(404, {["Content-Type"] = "application/json"}, '{"error":"session not found"}'))
            socket.close(client)
            stats.errors = stats.errors + 1
            return
        end
        
        socket.write(client, http_response(202, {}, ""))
        socket.close(client)
        
        if req.body then
            local ok, msg = pcall(function()
                return (loadstring or load)("return " .. req.body:gsub('":', '"='):gsub('null', 'nil'))()
            end)
            
            -- Simple JSON parse fallback
            if not ok then
                local method = req.body:match('"method"%s*:%s*"([^"]+)"')
                local id = req.body:match('"id"%s*:%s*(%d+)')
                if method then
                    msg = {method = method, id = tonumber(id) or 1}
                end
            end
            
            if msg then
                local response = handle_mcp_request(msg)
                if response and session.client then
                    socket.write(session.client, sse_event("message", response))
                end
            end
        end
        
        stats.responses = stats.responses + 1
        return
    end
    
    -- Health check
    if req.path == "/" then
        socket.write(client, http_response(200, {["Content-Type"] = "application/json"}, json_encode({
            name = "bench-server",
            sessions = stats.active_sessions,
            memory_kb = math.floor(get_lua_memory_kb()),
        })))
        socket.close(client)
        stats.responses = stats.responses + 1
        return
    end
    
    socket.write(client, http_response(404, {}, "Not Found"))
    socket.close(client)
end

-- Memory sampler
local sampling = true
local function memory_sampler()
    while sampling do
        local mem = get_lua_memory_kb()
        memory_samples[#memory_samples + 1] = mem
        lunet.sleep(sample_interval_ms)
    end
end

-- Calculate statistics
local function calc_stats(samples)
    if #samples == 0 then return 0, 0, 0 end
    local sum = 0
    local min = samples[1]
    local max = samples[1]
    for _, v in ipairs(samples) do
        sum = sum + v
        if v < min then min = v end
        if v > max then max = v end
    end
    return sum / #samples, min, max
end

-- Report
local function report()
    print("\n[BENCH] ========== Memory Benchmark Results ==========")
    print(string.format("[BENCH] Port:           %d", PORT))
    print(string.format("[BENCH] Clients:        %d", NUM_CLIENTS))
    print(string.format("[BENCH] Req/Client:     %d", REQUESTS_PER_CLIENT))
    print(string.format("[BENCH] Duration:       %ds", DURATION_SEC))
    print("")
    print(string.format("[BENCH] Requests:       %d", stats.requests))
    print(string.format("[BENCH] Responses:      %d", stats.responses))
    print(string.format("[BENCH] Errors:         %d", stats.errors))
    print(string.format("[BENCH] Peak Sessions:  %d", stats.peak_sessions))
    print("")
    
    local avg, min, max = calc_stats(memory_samples)
    print("[BENCH] Memory (Lua heap):")
    print(string.format("[BENCH]   Baseline:     %.2f KB", memory_samples[1] or 0))
    print(string.format("[BENCH]   Average:      %.2f KB", avg))
    print(string.format("[BENCH]   Min:          %.2f KB", min))
    print(string.format("[BENCH]   Max:          %.2f KB", max))
    print(string.format("[BENCH]   Growth:       %.2f KB", (max - (memory_samples[1] or 0))))
    print(string.format("[BENCH]   Samples:      %d", #memory_samples))
    print("[BENCH] ================================================")
    
    if stats.errors > 0 then
        print("[BENCH] WARNING: Errors detected during benchmark")
    end
end

-- HTTP client for load generation
local function http_request(method, path, body)
    local client, err = socket.connect(HOST, PORT)
    if not client then return nil, err end
    
    local req = method .. " " .. path .. " HTTP/1.1\r\n"
    req = req .. "Host: " .. HOST .. "\r\n"
    req = req .. "Connection: close\r\n"
    if body then
        req = req .. "Content-Type: application/json\r\n"
        req = req .. "Content-Length: " .. #body .. "\r\n"
    end
    req = req .. "\r\n"
    if body then req = req .. body end
    
    socket.write(client, req)
    local resp = socket.read(client)
    socket.close(client)
    return resp
end

-- Load generator client
local function load_client(client_id)
    -- Get SSE session
    local client, err = socket.connect(HOST, PORT)
    if not client then
        stats.errors = stats.errors + 1
        return
    end
    
    local sse_req = "GET /sse HTTP/1.1\r\nHost: " .. HOST .. "\r\nConnection: keep-alive\r\n\r\n"
    socket.write(client, sse_req)
    local resp = socket.read(client)
    if not resp then
        socket.close(client)
        stats.errors = stats.errors + 1
        return
    end
    
    local session_id = resp:match("session=([%w]+)")
    if not session_id then
        socket.close(client)
        stats.errors = stats.errors + 1
        return
    end
    
    -- Initialize
    http_request("POST", "/message?session=" .. session_id, 
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
    
    -- Send requests
    for i = 1, REQUESTS_PER_CLIENT do
        http_request("POST", "/message?session=" .. session_id,
            '{"jsonrpc":"2.0","id":' .. (i + 10) .. ',"method":"ping","params":{}}')
    end
    
    socket.close(client)
    stats.active_sessions = stats.active_sessions - 1
end

-- Main
math.randomseed(os.time())

print("[BENCH] MCP-SSE Memory Benchmark")
print(string.format("[BENCH] Starting embedded server on port %d...", PORT))

lunet.spawn(function()
    local listener, err = socket.listen("tcp", HOST, PORT)
    if not listener then
        print("[BENCH] FATAL: Cannot listen on port " .. PORT .. ": " .. (err or "unknown"))
        os.exit(1)
    end
    
    print("[BENCH] Server started")
    
    -- Start memory sampler
    lunet.spawn(memory_sampler)
    
    -- Take baseline measurement
    lunet.sleep(100)
    print(string.format("[BENCH] Baseline memory: %.2f KB", get_lua_memory_kb()))
    
    -- Start load after brief warmup
    print("[BENCH] Starting load generation...")
    local completed = 0
    
    for i = 1, NUM_CLIENTS do
        lunet.spawn(function()
            load_client(i)
            completed = completed + 1
            if completed % 10 == 0 then
                io.write(".")
                io.flush()
            end
        end)
    end
    
    -- Accept connections
    local start_time = os.time()
    while os.time() - start_time < DURATION_SEC do
        local client = socket.accept(listener)
        if client then
            lunet.spawn(function() handle_client(client) end)
        end
    end
    
    -- Stop and report
    sampling = false
    lunet.sleep(200)
    
    socket.close(listener)
    report()
    os.exit(stats.errors > 0 and 1 or 0)
end)
