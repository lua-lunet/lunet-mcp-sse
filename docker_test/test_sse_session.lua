#!/usr/bin/env luajit

local socket = require("socket")
local url = require("socket.url")

local HOST = "127.0.0.1"
local PORT = 8080

local function send_http(client, method, path, body)
    local request = method .. " " .. path .. " HTTP/1.1\r\n"
    request = request .. "Host: " .. HOST .. ":" .. PORT .. "\r\n"
    request = request .. "Accept: text/event-stream\r\n"
    request = request .. "Connection: close\r\n"

    if body then
        request = request .. "Content-Type: application/json\r\n"
        request = request .. "Content-Length: " .. #body .. "\r\n"
    end

    request = request .. "\r\n"
    if body then
        request = request .. body
    end

    client:send(request)
    local response = {}
    while true do
        local chunk, err = client:receive("*l")
        if not chunk then break end
        table.insert(response, chunk)
        if chunk == "" then break end
    end
    return table.concat(response, "\r\n")
end

local function read_sse_line(client)
    local line, err = client:receive("*l")
    if not line then return nil, err end
    return line
end

print("=== MCP-SSE Session Test ===")
print("")

local client = socket.connect(HOST, PORT)
if not client then
    print("FAIL: Cannot connect to server")
    os.exit(1)
end

print("1. Connecting to SSE endpoint...")
local response = send_http(client, "GET", "/sse")
print("   Response received")

local session_id = response:match("session=([%w]+)")
if session_id then
    print("   PASS: Session ID: " .. session_id)
else
    print("   FAIL: No session ID found")
    client:close()
    os.exit(1)
end

print("")
print("2. Sending initialize request...")
local init_body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"lua-test","version":"1.0"}}}'
local init_resp = send_http(client, "POST", "/message?session=" .. session_id, init_body)
print("   Status: " .. (init_resp:match("HTTP/1.1 (%d+)") or "unknown"))

print("")
print("3. Sending tools/list request...")
local tools_body = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
local tools_resp = send_http(client, "POST", "/message?session=" .. session_id, tools_body)
print("   Status: " .. (tools_resp:match("HTTP/1.1 (%d+)") or "unknown"))

print("")
print("4. Sending ping request...")
local ping_body = '{"jsonrpc":"2.0","id":3,"method":"ping","params":{}}'
local ping_resp = send_http(client, "POST", "/message?session=" .. session_id, ping_body)
print("   Status: " .. (ping_resp:match("HTTP/1.1 (%d+)") or "unknown"))

client:close()

print("")
print("=== Session Test Complete ===")